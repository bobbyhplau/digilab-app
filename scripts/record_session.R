# =============================================================================
# Shiny Session Recording for shinyloadtest
# Record a user session that can be replayed with shinycannon at varying
# concurrency levels to find performance bottlenecks.
#
# Prerequisites:
#   1. Start the Shiny app in a SEPARATE R session: shiny::runApp()
#   2. Note which port the app is running on (e.g., 3838, 8080, etc.)
#   3. Run this script, pointing at that port.
#
# Usage:
#   Rscript scripts/record_session.R          # defaults to port 3838
#   Rscript scripts/record_session.R 8080     # custom port
#
#   # Or from the R console:
#   source("scripts/record_session.R")
# =============================================================================

cat("
+=========================================================+
|     DigiLab - Session Recorder (shinyloadtest)          |
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
# Parse port from command-line args (default: 3838)
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
port <- if (length(args) >= 1) as.integer(args[1]) else 3838L

if (is.na(port) || port < 1 || port > 65535) {
  stop("Invalid port number. Usage: Rscript scripts/record_session.R [PORT]")
}

app_url <- paste0("http://127.0.0.1:", port)

# ---------------------------------------------------------------------------
# Set up output path
# ---------------------------------------------------------------------------

output_dir <- "loadtest"
output_file <- file.path(output_dir, "recording.log")

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# ---------------------------------------------------------------------------
# Print instructions for the developer
# ---------------------------------------------------------------------------

cat("
+---------------------------------------------------------+
|  RECORDING SESSION                                      |
+---------------------------------------------------------+
|                                                         |
|  BEFORE YOU CONTINUE:                                   |
|  Make sure the Shiny app is already running in a        |
|  separate R session (shiny::runApp()).                   |
|                                                         |
|  Target app URL:", formatC(app_url, width = 32), "     |
|  Recording to:  ", formatC(output_file, width = 32), "     |
|                                                         |
+---------------------------------------------------------+
|                                                         |
|  WHAT HAPPENS NEXT:                                     |
|  1. A proxy browser window will open automatically.     |
|  2. Walk through these key user flows:                  |
|     - Dashboard load (charts, value boxes, hot deck)    |
|     - Switch scenes (full data refresh)                 |
|     - Open a player modal (rating history query)        |
|     - Open a deck modal (meta stats)                    |
|     - Switch to Tournaments tab, click a tournament     |
|     - Switch formats                                    |
|  3. When done, close the browser tab/window.            |
|     The recording will be saved automatically.          |
|                                                         |
+---------------------------------------------------------+
\n")

cat("Starting recording proxy for", app_url, "...\n\n")

# ---------------------------------------------------------------------------
# Record the session
# ---------------------------------------------------------------------------

shinyloadtest::record_session(
  target_app_url = app_url,
  output_file = output_file
)

# ---------------------------------------------------------------------------
# Print summary and next steps
# ---------------------------------------------------------------------------

cat("
+---------------------------------------------------------+
|  RECORDING COMPLETE                                     |
+---------------------------------------------------------+
|                                                         |
|  Session saved to: loadtest/recording.log               |
|                                                         |
|  NEXT STEPS - Replay with shinycannon:                  |
|                                                         |
|  1. Install shinycannon (Java 8+ required):             |
|     https://github.com/rstudio/shinycannon/releases     |
|                                                         |
|  2. Start the app again if it's not running:            |
|     shiny::runApp()                                     |
|                                                         |
|  3. Run shinycannon at increasing concurrency:          |
|                                                         |
|     # Baseline (1 user)                                 |
|     shinycannon loadtest/recording.log                  |
|       http://127.0.0.1:PORT                             |
|       --workers 1                                       |
|       --loaded-duration-minutes 2                       |
|       --output-dir loadtest/run_1user                   |
|                                                         |
|     # 5 concurrent users                                |
|     shinycannon loadtest/recording.log                  |
|       http://127.0.0.1:PORT                             |
|       --workers 5                                       |
|       --loaded-duration-minutes 2                       |
|       --output-dir loadtest/run_5users                  |
|                                                         |
|     # 10 concurrent users                               |
|     shinycannon loadtest/recording.log                  |
|       http://127.0.0.1:PORT                             |
|       --workers 10                                      |
|       --loaded-duration-minutes 2                       |
|       --output-dir loadtest/run_10users                 |
|                                                         |
|     # 25 concurrent users                               |
|     shinycannon loadtest/recording.log                  |
|       http://127.0.0.1:PORT                             |
|       --workers 25                                      |
|       --loaded-duration-minutes 2                       |
|       --output-dir loadtest/run_25users                 |
|                                                         |
|  4. Analyze results:                                    |
|     Rscript scripts/analyze_loadtest.R                  |
|                                                         |
+---------------------------------------------------------+
\n")

cat("Recording file:", normalizePath(output_file, mustWork = FALSE), "\n\n")
