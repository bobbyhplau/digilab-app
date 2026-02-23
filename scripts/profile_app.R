# =============================================================================
# Shiny App Profiling with profvis
# Launch the app with profiling enabled, interact with it, then review the
# flamegraph to identify performance bottlenecks.
#
# Usage:
#   source("scripts/profile_app.R")
#   # Or from terminal:
#   Rscript scripts/profile_app.R
# =============================================================================

cat("
+=========================================================+
|     DigiLab - Shiny App Profiler (profvis)              |
+=========================================================+
\n")

# ---------------------------------------------------------------------------
# Check that profvis is installed
# ---------------------------------------------------------------------------

if (!requireNamespace("profvis", quietly = TRUE)) {
  cat("profvis is not installed.\n")
  response <- readline("Install profvis now? (y/n): ")
  if (tolower(response) == "y") {
    install.packages("profvis")
  } else {
    stop("profvis is required. Install with: install.packages('profvis')")
  }
}

library(profvis)

# ---------------------------------------------------------------------------
# Set up output path
# ---------------------------------------------------------------------------

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_dir <- "loadtest"
output_file <- file.path(output_dir, paste0("profvis_report_", timestamp, ".html"))

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# ---------------------------------------------------------------------------
# Print instructions for the developer
# ---------------------------------------------------------------------------

cat("
+---------------------------------------------------------+
|  PROFILING SESSION                                      |
+---------------------------------------------------------+
|                                                         |
|  The app will launch with profiling enabled.            |
|  Walk through these key user flows:                     |
|                                                         |
|  1. Dashboard load (charts, value boxes, hot deck)      |
|  2. Switch scenes (full data refresh)                   |
|  3. Open a player modal (rating history query)          |
|  4. Open a deck modal (meta stats)                      |
|  5. Switch to Tournaments tab, click a tournament       |
|  6. Switch formats                                      |
|                                                         |
|  When done, close the app (Ctrl+C or close browser).    |
|  profvis will generate an interactive flamegraph.       |
|                                                         |
+---------------------------------------------------------+
\n")

cat("Output will be saved to:", output_file, "\n\n")
cat("Starting profiled app...\n\n")

# ---------------------------------------------------------------------------
# Run the app under profvis
# ---------------------------------------------------------------------------

prof <- profvis::profvis({
  shiny::runApp(appDir = ".", launch.browser = TRUE)
})

# ---------------------------------------------------------------------------
# Save the report
# ---------------------------------------------------------------------------

cat("\nSaving profvis report...\n")
htmlwidgets::saveWidget(prof, file = normalizePath(output_file, mustWork = FALSE),
                        selfcontained = TRUE)
cat("Report saved to:", normalizePath(output_file, mustWork = FALSE), "\n")

# ---------------------------------------------------------------------------
# Print summary and next steps
# ---------------------------------------------------------------------------

cat("
+---------------------------------------------------------+
|  PROFILING COMPLETE                                     |
+---------------------------------------------------------+
|                                                         |
|  What to look for in the flamegraph:                    |
|                                                         |
|  - SQL queries taking >500ms                            |
|  - Reactive chains that re-fire unnecessarily           |
|  - Large data frame allocations                         |
|  - Startup time breakdown                               |
|                                                         |
|  Identify the top 5 slowest call stacks with            |
|  file:line references for targeted optimization.        |
|                                                         |
+---------------------------------------------------------+
\n")

cat("To view the report again, open:\n")
cat(" ", normalizePath(output_file, mustWork = FALSE), "\n\n")
