# =============================================================================
# Submit Results: Grid Server (Paste + Manual Entry)
# Admin-only methods — lazy-loaded when admin logs in
# The actual paste modal + apply logic lives in submit-shared-server.R
# (sr_paste_btn, sr_paste_apply handlers)
# This file is kept as a placeholder for admin-only grid enhancements.
# =============================================================================

# No additional server logic needed beyond what submit-shared-server.R provides.
# Paste from Spreadsheet and Manual Entry both use the shared grid
# (sr_step2_content, sr_submit_results, sr_paste_btn, sr_paste_apply).
#
# This file exists for:
# 1. Lazy-loading pattern compatibility (sourced inside admin_modules_loaded block)
# 2. Future admin-only grid enhancements that don't belong in the shared module
