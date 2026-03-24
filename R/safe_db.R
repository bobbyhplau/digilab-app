# =============================================================================
# safe_db.R — Global safe database wrappers
# =============================================================================
# Extracted from shared-server.R so R/ utility files (ratings.R, admin_grid.R)
# can use the same retry + error handling logic.
#
# The server-scoped wrappers in shared-server.R delegate to these _impl functions
# and add session-level Sentry context tags.
# =============================================================================

#' Format an R vector as a PostgreSQL array literal string.
#'
#' RPostgres sends parameters as text, but PostgreSQL's ANY($1::int[]) expects
#' array literal format like "{1,2,3}". This helper bridges the gap.
#'
#' @param x Integer or character vector
#' @return Character string in PostgreSQL array literal format, e.g. "{1,2,3}"
pg_array <- function(x) {
  paste0("{", paste(x, collapse = ","), "}")
}

#' Helper to detect retryable connection pool / prepared statement errors
#' @param msg Character. Error message string to check
#' @return TRUE if the error is a retryable prepared statement error
is_prepared_stmt_error <- function(msg) {
  grepl("prepared statement", msg, ignore.case = TRUE) ||
  grepl("bind message supplies", msg, ignore.case = TRUE) ||
  grepl("needs to be bound", msg, ignore.case = TRUE) ||
  grepl("multiple queries.*same column", msg, ignore.case = TRUE) ||
  grepl("Query requires \\d+ params", msg, ignore.case = TRUE) ||
  grepl("invalid input syntax", msg, ignore.case = TRUE) ||
  grepl("statement.*does not exist", msg, ignore.case = TRUE)
}

#' Run a query on a dedicated connection checked out from the pool.
#' Bypasses prepared statement collisions by using a fresh connection.
#' @param pool Database connection pool
#' @param query SQL query string
#' @param params List or NULL
#' @param mode "query" for SELECT (dbGetQuery), "execute" for DML (dbExecute)
#' @return Query result or rows affected
run_on_dedicated_conn <- function(pool, query, params = NULL, mode = "query") {
  # If already a raw DBI connection (not a pool), use it directly
  if (!inherits(pool, "Pool")) {
    fn <- if (mode == "query") DBI::dbGetQuery else DBI::dbExecute
    if (!is.null(params) && length(params) > 0) return(fn(pool, query, params = params))
    return(fn(pool, query))
  }
  conn <- pool::poolCheckout(pool)
  on.exit(pool::poolReturn(conn), add = TRUE)
  fn <- if (mode == "query") DBI::dbGetQuery else DBI::dbExecute
  if (!is.null(params) && length(params) > 0) {
    fn(conn, query, params = params)
  } else {
    fn(conn, query)
  }
}

#' Safe Database Query (Implementation)
#'
#' Executes a database query with error handling and retry logic for
#' prepared statement collisions. Returns a sensible default instead of
#' crashing the app if the query fails.
#'
#' @param pool Database connection pool or DBI connection
#' @param query Character. SQL query string
#' @param params List or NULL. Parameters for parameterized query (default: NULL)
#' @param default Default value to return on error (default: empty data.frame)
#' @param sentry_tags Named list of Sentry context tags (default: empty list)
#'
#' @return Query result on success, or default value on error
safe_query_impl <- function(pool, query, params = NULL, default = data.frame(), sentry_tags = list()) {
  # Time the query for performance monitoring
  start_time <- proc.time()[["elapsed"]]

  # Retry up to 3 times with exponential backoff for prepared statement collisions.
  # Final retry uses a dedicated connection checkout to bypass pool contention.
  max_retries <- 3
  result <- NULL

  for (attempt in seq_len(max_retries + 1)) {
    result <- tryCatch({
      if (attempt <= max_retries) {
        # Normal pool-managed attempt
        if (!is.null(params) && length(params) > 0) {
          DBI::dbGetQuery(pool, query, params = params)
        } else {
          DBI::dbGetQuery(pool, query)
        }
      } else {
        # Final attempt: dedicated connection bypasses pool contention
        run_on_dedicated_conn(pool, query, params, mode = "query")
      }
    }, error = function(e) e)

    # Success — break out of retry loop
    if (!inherits(result, "error")) break

    # Not a retryable error — give up immediately
    if (!is_prepared_stmt_error(conditionMessage(result))) break

    # Log and backoff before next retry
    message(sprintf("[safe_query] Attempt %d/%d failed (prepared stmt collision): %s",
                    attempt, max_retries + 1, conditionMessage(result)))
    if (attempt <= max_retries) Sys.sleep(0.05 * (2 ^ (attempt - 1)))
  }

  # Log slow queries (>200ms)
  elapsed_ms <- (proc.time()[["elapsed"]] - start_time) * 1000
  if (elapsed_ms > 200) {
    query_preview <- substr(gsub("\\s+", " ", trimws(query)), 1, 120)
    rows <- if (is.data.frame(result)) nrow(result) else "?"
    message(sprintf("[SLOW QUERY %.0fms, %s rows] %s", elapsed_ms, rows, query_preview))
  }

  # Handle final result
  if (inherits(result, "error")) {
    query_preview <- substr(gsub("\\s+", " ", query), 1, 500)
    params_preview <- if (!is.null(params)) paste(sapply(params, as.character), collapse = ", ") else "NULL"
    message("[safe_query] Error: ", conditionMessage(result), " | Query: ", query_preview, " | Params: ", params_preview)
    if (exists("sentry_enabled") && isTRUE(sentry_enabled)) {
      tryCatch(
        sentryR::capture_exception(result, tags = c(
          sentry_tags,
          list(query_preview = query_preview, params = params_preview)
        )),
        error = function(se) NULL
      )
    }
    return(default)
  }

  result
}

#' Safe Database Execute (Implementation)
#'
#' Executes a database write operation (INSERT, UPDATE, DELETE) with error
#' handling and retry logic. Returns 0 rows affected instead of crashing on error.
#'
#' @param pool Database connection pool or DBI connection
#' @param query Character. SQL statement string
#' @param params List or NULL. Parameters for parameterized query (default: NULL)
#' @param sentry_tags Named list of Sentry context tags (default: empty list)
#'
#' @return Number of rows affected on success, or 0 on error
safe_execute_impl <- function(pool, query, params = NULL, sentry_tags = list()) {
  # Time the query for performance monitoring
  start_time <- proc.time()[["elapsed"]]

  # Retry up to 3 times with exponential backoff for prepared statement collisions.
  # Final retry uses a dedicated connection checkout to bypass pool contention.
  max_retries <- 3
  result <- NULL

  for (attempt in seq_len(max_retries + 1)) {
    result <- tryCatch({
      if (attempt <= max_retries) {
        if (!is.null(params) && length(params) > 0) {
          DBI::dbExecute(pool, query, params = params)
        } else {
          DBI::dbExecute(pool, query)
        }
      } else {
        run_on_dedicated_conn(pool, query, params, mode = "execute")
      }
    }, error = function(e) e)

    if (!inherits(result, "error")) break
    if (!is_prepared_stmt_error(conditionMessage(result))) break

    message(sprintf("[safe_execute] Attempt %d/%d failed (prepared stmt collision): %s",
                    attempt, max_retries + 1, conditionMessage(result)))
    if (attempt <= max_retries) Sys.sleep(0.05 * (2 ^ (attempt - 1)))
  }

  # Log slow writes (>200ms)
  elapsed_ms <- (proc.time()[["elapsed"]] - start_time) * 1000
  if (elapsed_ms > 200) {
    query_preview <- substr(gsub("\\s+", " ", trimws(query)), 1, 120)
    message(sprintf("[SLOW EXECUTE %.0fms] %s", elapsed_ms, query_preview))
  }

  # Handle final result
  if (inherits(result, "error")) {
    message("[safe_execute] Error: ", conditionMessage(result))
    message("[safe_execute] Query: ", substr(gsub("\\s+", " ", query), 1, 200))
    if (exists("sentry_enabled") && isTRUE(sentry_enabled)) {
      tryCatch(sentryR::capture_exception(result, tags = sentry_tags), error = function(se) NULL)
    }
    return(0)
  }

  result
}

#' Execute a function within a database transaction
#'
#' Checks out a connection from the pool, runs BEGIN, executes the function,
#' and COMMITs on success or ROLLBACKs on error. Uses raw DBI calls intentionally
#' — retry logic would break atomicity by grabbing a different connection.
#'
#' @param pool Database connection pool
#' @param fn Function that takes a single `conn` argument and returns a value
#' @return The return value of fn, or NULL on error (after rollback)
with_transaction <- function(pool, fn) {
  conn <- pool::localCheckout(pool)
  DBI::dbExecute(conn, "BEGIN")
  tryCatch({
    result <- fn(conn)
    DBI::dbExecute(conn, "COMMIT")
    result
  }, error = function(e) {
    tryCatch(DBI::dbExecute(conn, "ROLLBACK"), error = function(re) NULL)
    stop(e)
  })
}
