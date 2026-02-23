# =============================================================================
# Shinycannon Load Test Analysis
# Load shinycannon result directories, generate the shinyloadtest HTML report,
# and print summary statistics to the console.
#
# Prerequisites:
#   1. Record a session with scripts/record_session.R
#   2. Replay at varying concurrency with shinycannon (see record_session.R
#      output for exact commands)
#   3. Run this script to analyze the results
#
# Expected directory layout:
#   loadtest/run_1user/    — baseline (1 worker)
#   loadtest/run_5users/   — 5 workers
#   loadtest/run_10users/  — 10 workers
#   loadtest/run_25users/  — 25 workers
#
# Usage:
#   Rscript scripts/analyze_loadtest.R
#   Rscript scripts/analyze_loadtest.R loadtest   # custom base directory
#
#   # Or from the R console:
#   source("scripts/analyze_loadtest.R")
# =============================================================================

cat("
+=========================================================+
|     DigiLab - Load Test Analyzer (shinyloadtest)        |
+=========================================================+
\n")

# ---------------------------------------------------------------------------
# Check that shinyloadtest is installed
# ---------------------------------------------------------------------------

if (!requireNamespace("shinyloadtest", quietly = TRUE)) {
  cat("shinyloadtest is not installed.\n")
  response <- readline("Install shinyloadtest now? (y/n): ")
  if (tolower(response) == "y") {
    install.packages("shinyloadtest")
  } else {
    stop("shinyloadtest is required. Install with: install.packages('shinyloadtest')")
  }
}

library(shinyloadtest)

# ---------------------------------------------------------------------------
# Parse base directory from command-line args (default: loadtest)
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1) args[1] else "loadtest"

if (!dir.exists(base_dir)) {
  stop("Base directory '", base_dir, "' does not exist. ",
       "Run shinycannon first to generate result directories.")
}

# ---------------------------------------------------------------------------
# Auto-discover run directories (directories matching run_*)
# ---------------------------------------------------------------------------

cat("Scanning for run directories in:", normalizePath(base_dir), "\n\n")

run_dirs <- sort(list.dirs(base_dir, full.names = TRUE, recursive = FALSE))
run_dirs <- run_dirs[grepl("run_", basename(run_dirs))]

if (length(run_dirs) == 0) {
  stop("No run directories found in '", base_dir, "/'.\n",
       "Expected directories matching 'run_*' (e.g., run_1user, run_5users).\n",
       "Run shinycannon first — see scripts/record_session.R for instructions.")
}

cat("Found", length(run_dirs), "run(s):\n")
for (d in run_dirs) {
  cat("  -", basename(d), "\n")
}
cat("\n")

# ---------------------------------------------------------------------------
# Build named argument list for load_runs()
# ---------------------------------------------------------------------------

# Use directory basenames as run labels (e.g., "run_1user" -> "1 user")
make_label <- function(dirname) {
  label <- sub("^run_", "", dirname)
  label <- sub("users?$", " user(s)", label)
  label
}

run_args <- stats::setNames(run_dirs, vapply(basename(run_dirs), make_label, character(1)))

cat("+---------------------------------------------------------+\n")
cat("|  LOADING RUNS                                           |\n")
cat("+---------------------------------------------------------+\n\n")

for (i in seq_along(run_args)) {
  cat("  Loading:", names(run_args)[i],
      "  <-", normalizePath(run_args[[i]]), "\n")
}
cat("\n")

# ---------------------------------------------------------------------------
# Load all runs into a single tidy data frame
# ---------------------------------------------------------------------------

df <- do.call(shinyloadtest::load_runs, as.list(run_args))

# ---------------------------------------------------------------------------
# Print console summary statistics
# ---------------------------------------------------------------------------

cat("+---------------------------------------------------------+\n")
cat("|  SUMMARY STATISTICS                                     |\n")
cat("+---------------------------------------------------------+\n\n")

runs <- unique(df$run)

for (run_name in runs) {
  run_data <- df[df$run == run_name, ]
  n_events <- nrow(run_data)
  n_sessions <- length(unique(run_data$session_id))
  event_types <- table(run_data$event)

  cat(sprintf("  --- %s ---\n", run_name))
  cat(sprintf("    Sessions:     %d\n", n_sessions))
  cat(sprintf("    Total events: %d\n", n_events))

  # Event type breakdown
  cat("    Event breakdown:\n")
  for (etype in names(sort(event_types, decreasing = TRUE))) {
    cat(sprintf("      %-30s %d\n", etype, event_types[[etype]]))
  }

  # Event duration statistics (the 'time' column = end - start for each event)
  if ("time" %in% names(run_data)) {
    times <- run_data$time
    times <- times[!is.na(times)]
    if (length(times) > 0) {
      cat(sprintf("    Event durations (seconds):\n"))
      cat(sprintf("      Median: %.3f\n", stats::median(times)))
      cat(sprintf("      p95:    %.3f\n", stats::quantile(times, 0.95)))
      cat(sprintf("      p99:    %.3f\n", stats::quantile(times, 0.99)))
      cat(sprintf("      Max:    %.3f\n", max(times)))

      # Flag if p95 exceeds the 3-second threshold
      p95 <- stats::quantile(times, 0.95)
      if (p95 > 3) {
        cat(sprintf("      ** WARNING: p95 (%.3fs) exceeds 3s threshold **\n", p95))
      }
    }
  }

  # Per-event-type latency (top 10 slowest by median)
  if ("time" %in% names(run_data) && "event" %in% names(run_data)) {
    event_names <- unique(run_data$event)
    event_stats <- data.frame(
      event = character(0),
      median = numeric(0),
      p95 = numeric(0),
      count = integer(0),
      stringsAsFactors = FALSE
    )
    for (etype in event_names) {
      t <- run_data$time[run_data$event == etype]
      t <- t[!is.na(t)]
      if (length(t) > 0) {
        event_stats <- rbind(event_stats, data.frame(
          event = etype,
          median = stats::median(t),
          p95 = stats::quantile(t, 0.95, names = FALSE),
          count = length(t),
          stringsAsFactors = FALSE
        ))
      }
    }
    if (nrow(event_stats) > 0) {
      event_stats <- event_stats[order(-event_stats$median), ]
      top_n <- min(10, nrow(event_stats))
      cat("    Slowest events by median (top", top_n, "):\n")
      cat(sprintf("      %-35s %8s %8s %6s\n", "Event", "Median", "p95", "Count"))
      cat(sprintf("      %-35s %8s %8s %6s\n", "-----", "------", "---", "-----"))
      for (i in seq_len(top_n)) {
        row <- event_stats[i, ]
        cat(sprintf("      %-35s %7.3fs %7.3fs %6d\n",
                    row$event, row$median, row$p95, row$count))
      }
    }
  }

  cat("\n")
}

# ---------------------------------------------------------------------------
# Generate the shinyloadtest HTML report
# ---------------------------------------------------------------------------

cat("+---------------------------------------------------------+\n")
cat("|  GENERATING HTML REPORT                                 |\n")
cat("+---------------------------------------------------------+\n\n")

report_path <- file.path(base_dir, "loadtest_report.html")

cat("  Generating report...\n")
cat("  This may take a moment for large result sets.\n\n")

shinyloadtest::shinyloadtest_report(
  df,
  output = report_path,
  self_contained = TRUE,
  open_browser = FALSE
)

cat("  Report saved to:", normalizePath(report_path, mustWork = FALSE), "\n\n")

# ---------------------------------------------------------------------------
# Print next steps
# ---------------------------------------------------------------------------

cat("+---------------------------------------------------------+\n")
cat("|  ANALYSIS COMPLETE                                      |\n")
cat("+---------------------------------------------------------+\n")
cat("|                                                         |\n")
cat("|  What to look for in the report:                        |\n")
cat("|                                                         |\n")
cat("|  1. Session duration vs baseline                        |\n")
cat("|     -> Are higher-concurrency runs much slower?         |\n")
cat("|                                                         |\n")
cat("|  2. Event waterfall                                     |\n")
cat("|     -> Which outputs are slowest under load?            |\n")
cat("|                                                         |\n")
cat("|  3. Latency distribution (p50 / p95 / p99)              |\n")
cat("|     -> Where does p95 exceed 3 seconds?                 |\n")
cat("|                                                         |\n")
cat("|  4. The 'knee' — the concurrency level where            |\n")
cat("|     response times spike sharply.                       |\n")
cat("|                                                         |\n")
cat("|  Key concerns for DigiLab:                              |\n")
cat("|  - Dashboard complex queries under load                 |\n")
cat("|  - Single DuckDB connection bottleneck                  |\n")
cat("|  - Memory growth per session (max users per GB)         |\n")
cat("|                                                         |\n")
cat("|  Use findings to populate docs/profiling-report.md      |\n")
cat("|  with bottlenecks, knee point, and tier recommendation. |\n")
cat("|                                                         |\n")
cat("+---------------------------------------------------------+\n\n")

cat("To view the report, open:\n")
cat(" ", normalizePath(report_path, mustWork = FALSE), "\n\n")
