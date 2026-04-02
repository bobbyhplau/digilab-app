# Run migration 017 - Archetype Matchups MV
# Reverts mv_archetype_store_stats to original, creates mv_archetype_matchups.
# Usage: source("scripts/run_migration_017.R")

library(DBI)
library(RPostgres)
library(dotenv)

load_dot_env()

message("Connecting to database...")

con <- dbConnect(
  Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)

message("\n=== Migration 017: Archetype Matchups MV ===\n")

sql <- readLines("db/migrations/017_mirror_match_columns.sql")
sql <- paste(sql, collapse = "\n")

# Strip comment-only lines so they don't interfere with statement splitting
sql_lines <- strsplit(sql, "\n")[[1]]
sql_lines <- sql_lines[!grepl("^\\s*--", sql_lines)]
sql <- paste(sql_lines, collapse = "\n")

# Split on semicolons and run each statement
statements <- strsplit(sql, ";")[[1]]
statements <- trimws(statements)
statements <- statements[nchar(statements) > 0]

for (stmt in statements) {
  # Extract first meaningful line for description
  desc <- trimws(strsplit(stmt, "\n")[[1]])
  desc <- desc[!grepl("^--", desc) & nchar(desc) > 0][1]
  desc <- substr(desc, 1, 80)

  tryCatch({
    dbExecute(con, paste0(stmt, ";"))
    message(sprintf("  OK: %s", desc))
  }, error = function(e) {
    message(sprintf("  ERROR: %s\n         %s", desc, e$message))
  })
}

message("\n=== Migration 017 complete ===")

dbDisconnect(con)
message("Done.")
