# OCR Layout-Aware Parser Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the text-based OCR parser with a layout-aware parser that uses GCV bounding box coordinates to accurately extract player data from Bandai TCG+ standings screenshots.

**Architecture:** Modify `gcv_detect_text()` to return word-level bounding boxes alongside full text. Build a new `parse_standings_layout()` function that normalizes coordinates, clusters text into rows by Y-position, assigns text to columns by X-position, and extracts structured player data. Update the multi-screenshot merge logic to use real ranking numbers. Keep the text parser as a permanent fallback.

**Tech Stack:** R, Google Cloud Vision API (DOCUMENT_TEXT_DETECTION), httr2, base64enc

**Design Doc:** `docs/plans/2026-02-22-ocr-layout-parser-design.md`

---

### Task 1: Create Ground Truth CSV Files

Create `expected.csv` files for each test screenshot folder so we have a baseline to test against. These are hand-verified from visually reading the screenshots.

**Files:**
- Create: `screenshots/standings/8players_3rounds_1screenshot/expected.csv`
- Create: `screenshots/standings/9players_4rounds_1screenshot/expected.csv`
- Create: `screenshots/standings/13players_3rounds_1screenshot_cutofffinalplayer/expected.csv`
- Create: `screenshots/standings/14players_4rounds_2screenshots_screenshotsfromdifferentphones/expected.csv`
- Create: `screenshots/standings/17players_4rounds_2screenshots_screenshotsfromdifferentphones/expected.csv`
- Create: `screenshots/standings/18players_4rounds_2screenshots_01/expected.csv`
- Create: `screenshots/standings/18players_4rounds_2screenshots_02/expected.csv`

**Step 1: Visually inspect each screenshot and create CSVs**

Open each screenshot image and record the exact data visible on screen. Each CSV uses format:

```csv
rank,username,member_number,points
1,PlayerName,0000123456,12
2,AnotherPlayer,0000789012,9
```

Important notes:
- `rank` is the number shown in the circle on the left side of each row in the Bandai TCG+ app
- `username` is exactly as displayed (case-sensitive)
- `member_number` is the 10-digit number or GUEST##### format shown below the username
- `points` is the "Win Points" number
- For the `13players_cutoff` folder, the final player may be partially visible — include only fully readable rows
- For multi-screenshot folders, the expected.csv should contain the **merged** result (all unique players across all screenshots, sorted by rank)
- The `12players_4rounds_1screenshot` folder is empty — skip it

**Step 2: Commit ground truth files**

```bash
git add screenshots/standings/*/expected.csv
git commit -m "test: add ground truth CSVs for OCR test screenshots"
```

---

### Task 2: Modify `gcv_detect_text()` to Return Bounding Box Annotations

Modify the GCV API function to extract word-level bounding box data from the existing API response alongside the full text.

**Files:**
- Modify: `R/ocr.R:13-77` (the `gcv_detect_text()` function)

**Step 1: Update the function to return a structured list**

The GCV `DOCUMENT_TEXT_DETECTION` response includes `textAnnotations` — an array where element `[0]` is the full-page text and elements `[1..N]` are individual words with bounding polygon vertices.

Replace the current return logic (which returns just the text string) with a list containing both text and annotations:

```r
gcv_detect_text <- function(image_data, api_key = Sys.getenv("GOOGLE_CLOUD_VISION_API_KEY"), verbose = TRUE) {
  if (verbose) message("[OCR] Starting text detection...")

  if (is.null(api_key) || api_key == "") {
    warning("GOOGLE_CLOUD_VISION_API_KEY not set")
    if (verbose) message("[OCR] ERROR: API key not set")
    return(NULL)
  }
  if (verbose) message("[OCR] API key found (length: ", nchar(api_key), ")")

  # Handle both file path and raw bytes
  if (is.character(image_data) && file.exists(image_data)) {
    if (verbose) message("[OCR] Reading file: ", image_data)
    image_base64 <- base64encode(image_data)
  } else if (is.raw(image_data)) {
    if (verbose) message("[OCR] Using raw bytes (length: ", length(image_data), ")")
    image_base64 <- base64encode(image_data)
  } else {
    warning("Invalid image_data: must be file path or raw bytes")
    if (verbose) message("[OCR] ERROR: Invalid image_data type: ", class(image_data))
    return(NULL)
  }
  if (verbose) message("[OCR] Base64 encoded (length: ", nchar(image_base64), ")")

  # Build and execute request
  tryCatch({
    if (verbose) message("[OCR] Calling Google Cloud Vision API...")

    response <- request("https://vision.googleapis.com/v1/images:annotate") |>
      req_url_query(key = api_key) |>
      req_body_json(list(
        requests = list(list(
          image = list(content = image_base64),
          features = list(list(type = "DOCUMENT_TEXT_DETECTION"))
        ))
      )) |>
      req_perform() |>
      resp_body_json()

    if (verbose) message("[OCR] API response received")

    # Check for API errors in response
    if (!is.null(response$responses[[1]]$error)) {
      err <- response$responses[[1]]$error
      warning(paste("Vision API error:", err$message))
      if (verbose) message("[OCR] API ERROR: ", err$message)
      return(NULL)
    }

    # Extract full text annotation
    text <- response$responses[[1]]$fullTextAnnotation$text
    if (is.null(text)) {
      warning("No text detected in image")
      if (verbose) message("[OCR] No text detected in image")
      return(list(text = "", annotations = data.frame(), image_width = 0, image_height = 0))
    }

    if (verbose) message("[OCR] Text extracted (", nchar(text), " chars)")

    # Extract word-level bounding box annotations
    text_annotations <- response$responses[[1]]$textAnnotations
    annotations <- data.frame(
      text = character(),
      x_min = numeric(),
      y_min = numeric(),
      x_max = numeric(),
      y_max = numeric(),
      stringsAsFactors = FALSE
    )

    image_width <- 0
    image_height <- 0

    if (!is.null(text_annotations) && length(text_annotations) > 0) {
      # First annotation is full-page — use its bounding box for image dimensions
      full_page <- text_annotations[[1]]
      if (!is.null(full_page$boundingPoly$vertices)) {
        verts <- full_page$boundingPoly$vertices
        xs <- sapply(verts, function(v) if (!is.null(v$x)) v$x else 0)
        ys <- sapply(verts, function(v) if (!is.null(v$y)) v$y else 0)
        image_width <- max(xs)
        image_height <- max(ys)
      }

      # Word-level annotations start at index 2 (skip full-page)
      if (length(text_annotations) > 1) {
        word_list <- lapply(text_annotations[2:length(text_annotations)], function(ann) {
          verts <- ann$boundingPoly$vertices
          if (is.null(verts) || length(verts) < 4) return(NULL)
          xs <- sapply(verts, function(v) if (!is.null(v$x)) v$x else 0)
          ys <- sapply(verts, function(v) if (!is.null(v$y)) v$y else 0)
          data.frame(
            text = ann$description %||% "",
            x_min = min(xs),
            y_min = min(ys),
            x_max = max(xs),
            y_max = max(ys),
            stringsAsFactors = FALSE
          )
        })
        word_list <- word_list[!sapply(word_list, is.null)]
        if (length(word_list) > 0) {
          annotations <- do.call(rbind, word_list)
        }
      }

      if (verbose) message("[OCR] Extracted ", nrow(annotations), " word annotations, image: ", image_width, "x", image_height)
    }

    list(
      text = text,
      annotations = annotations,
      image_width = image_width,
      image_height = image_height
    )
  }, error = function(e) {
    warning(paste("OCR API error:", e$message))
    if (verbose) message("[OCR] EXCEPTION: ", e$message)
    return(NULL)
  })
}
```

Key changes:
- Return value is now a `list(text, annotations, image_width, image_height)` instead of a plain character string
- `annotations` is a data frame with columns: `text`, `x_min`, `y_min`, `x_max`, `y_max`
- `image_width` and `image_height` come from the full-page annotation's bounding box
- Uses `%||%` operator (available in R 4.5+) for null coalescing on annotation description
- On error or empty image, returns NULL (unchanged from current behavior)
- On no text detected, returns the list structure with empty annotations

**Step 2: Update all callers to handle the new return type**

The function is called in 4 places. Update each to extract `$text` from the list:

1. **`server/public-submit-server.R` ~line 170-183** — The main submit handler calls `gcv_detect_text()` and checks the result. Change:
   - Store full result: `ocr_result <- gcv_detect_text(...)`
   - Extract text: `ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result`
   - Store annotations for later: `ocr_annotations <- if (is.list(ocr_result)) ocr_result$annotations else NULL`
   - Also store `image_width` and `image_height` similarly
   - Keep `ocr_texts` accumulator as-is (it stores text strings)

2. **`server/public-submit-server.R` ~line 1270** — Match history OCR call. Same pattern: extract `$text` from the result. (Match history doesn't use bounding boxes — out of scope.)

3. **`scripts/test_ocr.R:64`** — `test_image()` calls `gcv_detect_text()`. Update to handle list return:
   ```r
   ocr_result <- gcv_detect_text(image_path, verbose = verbose)
   if (is.null(ocr_result)) { ... }
   ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result
   ```

4. **`scripts/batch_test_ocr.R:69-74`** — `process_standings()` calls `gcv_detect_text()`. Same pattern. Also save annotation data to a file for offline re-testing:
   ```r
   ocr_result <- gcv_detect_text(image_path, verbose = verbose)
   ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result
   ocr_annotations <- if (is.list(ocr_result)) ocr_result$annotations else NULL
   # Save annotations alongside OCR text
   if (!is.null(ocr_annotations) && nrow(ocr_annotations) > 0) {
     ann_file <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_annotations.rds"))
     saveRDS(ocr_result, ann_file)
   }
   ```

**Step 3: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('R/ocr.R')"`

Verify no parse errors.

**Step 4: Commit**

```bash
git add R/ocr.R server/public-submit-server.R scripts/test_ocr.R scripts/batch_test_ocr.R
git commit -m "feat: extract bounding box annotations from GCV response

gcv_detect_text() now returns a list with text, annotations data frame,
and image dimensions. All callers updated to handle the new return type."
```

---

### Task 3: Create `parse_standings_layout()` — Core Layout Parser

Build the new layout-aware parser that uses bounding box coordinates to extract structured player data.

**Files:**
- Modify: `R/ocr.R` (add new function after `should_autofill_points()`, before `parse_tournament_standings()`)

**Step 1: Write the `parse_standings_layout()` function**

Add the following function to `R/ocr.R` at approximately line 203 (after `should_autofill_points()` and before `parse_tournament_standings()`):

```r
#' Parse tournament standings using layout-aware bounding box analysis
#'
#' Uses GCV word-level bounding boxes to understand the visual table structure.
#' Each text element's X/Y position determines which column (ranking, username,
#' points) and which row it belongs to.
#'
#' @param annotations Data frame with columns: text, x_min, y_min, x_max, y_max
#' @param image_width Image width in pixels (for normalization)
#' @param image_height Image height in pixels (for normalization)
#' @param total_rounds Total rounds in tournament (for calculating W-L-T)
#' @param verbose Print debug messages
#' @return Data frame with columns: placement, username, member_number, points, wins, losses, ties
parse_standings_layout <- function(annotations, image_width, image_height,
                                    total_rounds = 4, verbose = TRUE) {
  if (verbose) message("[LAYOUT] Starting layout-aware parsing...")

  if (is.null(annotations) || nrow(annotations) == 0 || image_width == 0 || image_height == 0) {
    if (verbose) message("[LAYOUT] No annotations or invalid dimensions")
    return(data.frame(
      placement = integer(), username = character(), member_number = character(),
      points = integer(), wins = integer(), losses = integer(), ties = integer(),
      stringsAsFactors = FALSE
    ))
  }

  # Step 1: Normalize coordinates to percentages of image dimensions
  annotations$x_center <- ((annotations$x_min + annotations$x_max) / 2) / image_width * 100
  annotations$y_center <- ((annotations$y_min + annotations$y_max) / 2) / image_height * 100
  annotations$x_min_pct <- annotations$x_min / image_width * 100
  annotations$x_max_pct <- annotations$x_max / image_width * 100
  annotations$y_min_pct <- annotations$y_min / image_height * 100
  annotations$y_max_pct <- annotations$y_max / image_height * 100

  if (verbose) message("[LAYOUT] Normalized ", nrow(annotations), " annotations")

  # Step 2: Filter noise — remove annotations in top/bottom 7% (status bar, nav bar)
  annotations <- annotations[annotations$y_center > 7 & annotations$y_center < 93, ]
  if (verbose) message("[LAYOUT] After noise filter: ", nrow(annotations), " annotations")

  if (nrow(annotations) == 0) {
    return(data.frame(
      placement = integer(), username = character(), member_number = character(),
      points = integer(), wins = integer(), losses = integer(), ties = integer(),
      stringsAsFactors = FALSE
    ))
  }

  # Step 3: Detect header row and column boundaries
  # Look for header keywords to set precise column boundaries
  header_keywords <- c("ranking", "user", "name", "win", "points", "omw", "gw")
  header_annotations <- annotations[tolower(annotations$text) %in% header_keywords, ]

  col_boundaries <- list(
    ranking_max = 15,    # Ranking column: 0-15%
    username_min = 15,   # Username column: 15-60%
    username_max = 60,
    points_min = 60,     # Points column: 60-78%
    points_max = 78
  )

  if (nrow(header_annotations) >= 2) {
    # Found header row — use actual header positions for more precise boundaries
    ranking_header <- header_annotations[tolower(header_annotations$text) == "ranking", ]
    points_header <- header_annotations[tolower(header_annotations$text) %in% c("win", "points"), ]
    user_header <- header_annotations[tolower(header_annotations$text) %in% c("user", "name"), ]

    if (nrow(ranking_header) > 0) {
      col_boundaries$ranking_max <- ranking_header$x_max_pct[1] + 2
      col_boundaries$username_min <- ranking_header$x_max_pct[1] + 2
    }
    if (nrow(points_header) > 0) {
      col_boundaries$username_max <- min(points_header$x_min_pct) - 2
      col_boundaries$points_min <- min(points_header$x_min_pct) - 2
      col_boundaries$points_max <- max(points_header$x_max_pct) + 5
    }

    # Remove header row (same Y-cluster as header keywords)
    if (nrow(header_annotations) > 0) {
      header_y <- median(header_annotations$y_center)
      annotations <- annotations[abs(annotations$y_center - header_y) > 2, ]
    }

    if (verbose) message("[LAYOUT] Found header row, refined column boundaries")
  }

  if (verbose) {
    message("[LAYOUT] Column boundaries: ranking=0-", round(col_boundaries$ranking_max),
            "%, username=", round(col_boundaries$username_min), "-", round(col_boundaries$username_max),
            "%, points=", round(col_boundaries$points_min), "-", round(col_boundaries$points_max), "%")
  }

  # Step 4: Filter out known noise text
  noise_patterns <- c("^B⭑", "privacy", "policy", "copyright", "digimon card game",
                       "home", "my events", "event search", "decks", "others",
                       "store events", "match history", "results")
  noise_mask <- sapply(annotations$text, function(t) {
    t_lower <- tolower(t)
    any(sapply(noise_patterns, function(p) grepl(p, t_lower)))
  })
  annotations <- annotations[!noise_mask, ]

  # Step 5: Cluster annotations into rows by Y-position
  # Group text blocks whose vertical centers are within ~2% of image height
  if (nrow(annotations) == 0) {
    return(data.frame(
      placement = integer(), username = character(), member_number = character(),
      points = integer(), wins = integer(), losses = integer(), ties = integer(),
      stringsAsFactors = FALSE
    ))
  }

  # Sort by Y center
  annotations <- annotations[order(annotations$y_center), ]

  # Cluster using gap-based grouping: new row when Y gap > 1.5%
  row_ids <- integer(nrow(annotations))
  current_row <- 1
  row_ids[1] <- 1
  for (i in 2:nrow(annotations)) {
    if (annotations$y_center[i] - annotations$y_center[i - 1] > 1.5) {
      current_row <- current_row + 1
    }
    row_ids[i] <- current_row
  }
  annotations$row_id <- row_ids

  if (verbose) message("[LAYOUT] Clustered into ", max(row_ids), " rows")

  # Step 6: For each row, assign text to columns and extract player data
  results <- list()

  for (rid in unique(annotations$row_id)) {
    row_data <- annotations[annotations$row_id == rid, ]

    # Assign each annotation to a column based on X-center
    ranking_texts <- row_data[row_data$x_center <= col_boundaries$ranking_max, ]
    username_texts <- row_data[row_data$x_center > col_boundaries$username_min &
                                row_data$x_center <= col_boundaries$username_max, ]
    points_texts <- row_data[row_data$x_center > col_boundaries$points_min &
                              row_data$x_center <= col_boundaries$points_max, ]

    # Extract ranking: should be integer 1-64
    ranking <- NA_integer_
    if (nrow(ranking_texts) > 0) {
      for (rt in ranking_texts$text) {
        rt_clean <- gsub("[^0-9]", "", rt)
        if (nchar(rt_clean) > 0) {
          val <- as.integer(rt_clean)
          if (!is.na(val) && val >= 1 && val <= 128) {
            ranking <- val
            break
          }
        }
      }
    }

    # Extract username and member number from username column
    username <- NA_character_
    member_number <- NA_character_

    if (nrow(username_texts) > 0) {
      # Sort username column texts top-to-bottom within the row
      username_texts <- username_texts[order(username_texts$y_center), ]

      for (ut_idx in seq_len(nrow(username_texts))) {
        ut <- username_texts$text[ut_idx]

        # Check for member number pattern
        if (grepl("^\\d{10}$", ut) || grepl("^GUEST\\d{5}$", ut, ignore.case = TRUE)) {
          member_number <- ut
          next
        }

        # Check for "Member" or "Number" keywords (part of member number label)
        if (grepl("^Member$|^Number$|^Number:?$", ut, ignore.case = TRUE)) next

        # Check for member number with label: "Member Number 0000123456"
        member_match <- regmatches(ut, regexec("Member\\s*Number\\s*:?\\s*(\\d{10}|GUEST\\d{5})", ut, ignore.case = TRUE))[[1]]
        if (length(member_match) > 1) {
          member_number <- member_match[2]
          next
        }

        # Skip percentages
        if (grepl("%", ut)) next

        # Skip pure numbers that are likely data from other columns bleeding in
        if (grepl("^\\d{1,3}$", ut)) next

        # This is likely the username — take the first non-noise text
        if (is.na(username)) {
          # Username can contain letters, numbers, underscores, dots, apostrophes, spaces
          # Clean up any OCR artifacts
          username <- trimws(ut)
        }
      }
    }

    # If member number not found in username column, check if it spans columns
    # (sometimes the full "Member Number XXXXXXXXXX" wraps and its parts scatter)
    if (is.na(member_number)) {
      all_row_text <- paste(row_data$text, collapse = " ")
      member_match <- regmatches(all_row_text, regexec("(\\d{10}|GUEST\\d{5})", all_row_text))[[1]]
      if (length(member_match) > 0 && nchar(member_match[1]) >= 5) {
        member_number <- member_match[1]
      }
    }

    # Extract points: integer from points column
    points <- NA_integer_
    if (nrow(points_texts) > 0) {
      for (pt in points_texts$text) {
        pt_clean <- gsub("[^0-9]", "", pt)
        if (nchar(pt_clean) > 0) {
          val <- as.integer(pt_clean)
          if (!is.na(val) && val >= 0 && val <= 99) {
            points <- val
            break
          }
        }
      }
    }

    # Skip rows without enough data (need at least ranking or username)
    if (is.na(ranking) && is.na(username)) next

    # Skip rows without member number (not a real player row)
    # Unless we have both ranking and username (partial data worth keeping)
    if (is.na(member_number) && is.na(username)) next

    if (verbose) {
      message("[LAYOUT] Row ", rid, ": rank=", ranking, ", user='", username,
              "', member=", member_number, ", pts=", points)
    }

    # Default points to 0 if not found
    if (is.na(points)) points <- 0L

    # Calculate W-L-T from points
    wins <- points %/% 3
    remaining <- points %% 3
    ties <- remaining
    losses <- max(0L, as.integer(total_rounds) - wins - ties)

    results[[length(results) + 1]] <- data.frame(
      placement = if (is.na(ranking)) NA_integer_ else ranking,
      username = if (is.na(username)) "" else username,
      member_number = if (is.na(member_number)) "" else member_number,
      points = points,
      wins = wins,
      losses = losses,
      ties = ties,
      stringsAsFactors = FALSE
    )
  }

  if (length(results) == 0) {
    if (verbose) message("[LAYOUT] No player rows extracted")
    return(data.frame(
      placement = integer(), username = character(), member_number = character(),
      points = integer(), wins = integer(), losses = integer(), ties = integer(),
      stringsAsFactors = FALSE
    ))
  }

  result_df <- do.call(rbind, results)

  # Autofill missing points for players who shouldn't have 0
  player_count <- nrow(result_df)
  for (i in seq_len(player_count)) {
    if (should_autofill_points(result_df$placement[i], player_count, result_df$points[i])) {
      estimated <- estimate_points_for_placement(result_df$placement[i], player_count, total_rounds)
      if (verbose) {
        message("[LAYOUT] Autofill: ", result_df$username[i], " (rank ", result_df$placement[i],
                ") points 0 -> ", estimated)
      }
      result_df$points[i] <- estimated
      result_df$wins[i] <- estimated %/% 3
      remaining <- estimated %% 3
      result_df$ties[i] <- remaining
      result_df$losses[i] <- max(0L, as.integer(total_rounds) - result_df$wins[i] - result_df$ties[i])
    }
  }

  # Sort by ranking
  result_df <- result_df[order(result_df$placement), ]

  if (verbose) message("[LAYOUT] Parsed ", nrow(result_df), " players")
  result_df
}
```

**Step 2: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('R/ocr.R')"`

**Step 3: Commit**

```bash
git add R/ocr.R
git commit -m "feat: add parse_standings_layout() layout-aware parser

Uses GCV bounding box coordinates to detect table structure:
- Normalizes coordinates to percentages (resolution-independent)
- Clusters text into rows by Y-position
- Assigns text to columns (ranking, username, points) by X-position
- Extracts ranking numbers, usernames, member numbers, and points"
```

---

### Task 4: Add Fallback Orchestration — Try Layout Parser First, Fall Back to Text Parser

Create a wrapper function that tries the layout parser first and falls back to the text parser if it fails.

**Files:**
- Modify: `R/ocr.R` (add orchestrator function)
- Modify: `server/public-submit-server.R:170-200` (use orchestrator in submit handler)

**Step 1: Add `parse_standings()` orchestrator function**

Add this function to `R/ocr.R` after `parse_standings_layout()` and before `parse_tournament_standings()`:

```r
#' Parse tournament standings with layout-first fallback strategy
#'
#' Tries the layout-aware parser first (uses bounding boxes for accuracy).
#' Falls back to the text-based parser if layout parsing fails.
#'
#' @param ocr_result Result from gcv_detect_text() — either a list or plain text
#' @param total_rounds Total rounds in tournament
#' @param verbose Print debug messages
#' @return Data frame with columns: placement, username, member_number, points, wins, losses, ties
parse_standings <- function(ocr_result, total_rounds = 4, verbose = TRUE) {
  # Handle both new list format and legacy plain text
  if (is.list(ocr_result)) {
    text <- ocr_result$text
    annotations <- ocr_result$annotations
    image_width <- ocr_result$image_width
    image_height <- ocr_result$image_height
  } else {
    text <- ocr_result
    annotations <- NULL
    image_width <- 0
    image_height <- 0
  }

  # Try layout-aware parser first
  if (!is.null(annotations) && nrow(annotations) > 0 && image_width > 0 && image_height > 0) {
    if (verbose) message("[OCR] Trying layout-aware parser...")

    layout_result <- tryCatch({
      parse_standings_layout(annotations, image_width, image_height,
                              total_rounds = total_rounds, verbose = verbose)
    }, error = function(e) {
      if (verbose) message("[OCR] Layout parser error: ", e$message)
      data.frame()
    })

    # Validate: need at least 1 player with ranking, username, and member number
    if (nrow(layout_result) > 0) {
      has_ranking <- any(!is.na(layout_result$placement) & layout_result$placement > 0)
      has_username <- any(!is.na(layout_result$username) & layout_result$username != "")
      has_member <- any(!is.na(layout_result$member_number) & layout_result$member_number != "")

      if (has_ranking && has_username && has_member) {
        if (verbose) message("[OCR] Using layout parser (", nrow(layout_result), " players found)")
        return(layout_result)
      } else {
        if (verbose) message("[OCR] Layout parser returned incomplete data, falling back to text parser")
      }
    } else {
      if (verbose) message("[OCR] Layout parser returned 0 players, falling back to text parser")
    }
  }

  # Fallback to text-based parser
  if (verbose) message("[OCR] Using text-based parser")
  parse_tournament_standings(text, total_rounds = total_rounds, verbose = verbose)
}
```

**Step 2: Update the submit handler to use the orchestrator**

In `server/public-submit-server.R`, the OCR processing loop (~lines 160-200) currently calls `gcv_detect_text()` then `parse_tournament_standings()`. Update it to:

1. Store the full OCR result (list with annotations)
2. Call `parse_standings()` (the new orchestrator) instead of `parse_tournament_standings()`

Find the section that looks like:
```r
ocr_text <- tryCatch({
  gcv_detect_text(raw_data, verbose = TRUE)
}, ...)
...
parsed <- tryCatch({
  parse_tournament_standings(ocr_text, total_rounds, verbose = TRUE)
}, ...)
```

Replace with:
```r
ocr_result <- tryCatch({
  gcv_detect_text(raw_data, verbose = TRUE)
}, error = function(e) {
  ...
  NULL
})

# Extract text for backward compatibility
ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

if (!is.null(ocr_text) && ocr_text != "") {
  ocr_texts <- c(ocr_texts, ocr_text)

  parsed <- tryCatch({
    parse_standings(ocr_result, total_rounds, verbose = TRUE)
  }, error = function(e) {
    ...
  })
  ...
}
```

**Step 3: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('R/ocr.R'); parse('server/public-submit-server.R')"`

**Step 4: Commit**

```bash
git add R/ocr.R server/public-submit-server.R
git commit -m "feat: add parse_standings() orchestrator with layout-first fallback

Tries layout-aware parser first, validates result has ranking + username +
member number, falls back to text parser on failure. Submit handler updated."
```

---

### Task 5: Update Multi-Screenshot Merge Logic

Update the deduplication and merge logic in `public-submit-server.R` to use real ranking numbers from the layout parser instead of sequential re-assignment.

**Files:**
- Modify: `server/public-submit-server.R:231-292`

**Step 1: Update the merge/dedup section**

Replace the current merge logic (~lines 231-292) with ranking-aware merging:

```r
  # Combine results from all screenshots
  combined <- do.call(rbind, all_results)

  # Smart deduplication for overlapping screenshots
  if (nrow(combined) > 1) {
    original_count <- nrow(combined)

    # Dedup by member number (primary key) — keep first occurrence
    if (any(!is.na(combined$member_number) & combined$member_number != "")) {
      has_member <- !is.na(combined$member_number) & combined$member_number != ""

      # Separate GUEST IDs from real member numbers
      is_guest <- has_member & grepl("^GUEST\\d+$", combined$member_number, ignore.case = TRUE)
      has_real_member <- has_member & !is_guest

      with_real_member <- combined[has_real_member, ]
      with_guest <- combined[is_guest, ]
      without_member <- combined[!has_member, ]

      # Dedup real member numbers
      with_real_member <- with_real_member[!duplicated(with_real_member$member_number), ]

      # Dedup GUEST players by username (case-insensitive)
      if (nrow(with_guest) > 0) {
        with_guest$username_lower <- tolower(with_guest$username)
        with_guest <- with_guest[!duplicated(with_guest$username_lower), ]
        with_guest$username_lower <- NULL
      }

      # Dedup no-member players by username
      if (nrow(without_member) > 0) {
        without_member$username_lower <- tolower(without_member$username)
        without_member <- without_member[!duplicated(without_member$username_lower), ]
        without_member$username_lower <- NULL
      }

      combined <- rbind(with_real_member, with_guest, without_member)
    } else {
      combined$username_lower <- tolower(combined$username)
      combined <- combined[!duplicated(combined$username_lower), ]
      combined$username_lower <- NULL
    }

    deduped_count <- nrow(combined)
    if (original_count != deduped_count) {
      message("[SUBMIT] Deduplication: ", original_count, " -> ", deduped_count, " players")
    }
  }

  # Sort by placement (which now contains real ranking numbers from layout parser)
  combined <- combined[order(combined$placement), ]

  # Track how many were parsed from OCR
  parsed_count <- nrow(combined)

  # Rank-based validation against declared player count
  max_rank <- max(combined$placement, na.rm = TRUE)

  if (max_rank > total_players) {
    # Screenshots show more players than declared — auto-correct upward
    message("[SUBMIT] Auto-correcting player count: ", total_players, " -> ", max_rank,
            " (screenshots show rank ", max_rank, ")")
    total_players <- max_rank
  }

  # Enforce exactly total_players rows
  if (nrow(combined) > total_players) {
    combined <- combined[1:total_players, ]
  } else if (nrow(combined) < total_players) {
    # Pad with blank rows for missing ranks
    existing_ranks <- combined$placement
    for (p in seq_len(total_players)) {
      if (!(p %in% existing_ranks)) {
        blank_row <- data.frame(
          placement = p,
          username = "",
          member_number = "",
          points = 0,
          wins = 0,
          losses = total_rounds,
          ties = 0,
          stringsAsFactors = FALSE
        )
        combined <- rbind(combined, blank_row)
      }
    }
  }

  # Re-sort after adding blank rows (keep ranking order)
  combined <- combined[order(combined$placement), ]

  # Re-assign placements sequentially (1 to N) for the review UI
  # Store original ranking for reference
  combined$original_rank <- combined$placement
  combined$placement <- seq_len(nrow(combined))
```

Key changes:
- GUEST member numbers now dedup by username separately from real member numbers
- Sort by `placement` which contains real ranking numbers from the layout parser
- Auto-correct `total_players` upward if screenshots show higher ranks
- Pad missing ranks with blank rows at the correct positions (not just at the end)
- Store `original_rank` for reference before sequential re-assignment

**Step 2: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('server/public-submit-server.R')"`

**Step 3: Commit**

```bash
git add server/public-submit-server.R
git commit -m "feat: ranking-aware multi-screenshot merge with GUEST dedup

- Separate dedup for real member numbers, GUEST IDs, and no-member players
- Sort by real ranking numbers from layout parser
- Auto-correct player count if screenshots show more players
- Pad blank rows at correct rank positions for gaps"
```

---

### Task 6: Enhance GUEST Player Database Lookup

Update the player pre-matching section to look up GUEST players by username in the database, potentially recovering their real member number.

**Files:**
- Modify: `server/public-submit-server.R:297-347`

**Step 1: Update the GUEST player handling**

In the player pre-matching loop (~lines 297-347), update the GUEST ID handling to query the database by username:

Find the section:
```r
# Clear GUEST IDs so they don't get stored (they're not real member numbers)
if (is_guest_id) {
  combined$member_number[i] <- ""
}
```

Replace with:
```r
# GUEST IDs aren't real member numbers — try to find this player by username
if (is_guest_id) {
  combined$member_number[i] <- ""

  # Look up by username to find their real member number
  if (!is.null(username) && !is.na(username) && nchar(username) > 0) {
    guest_lookup <- safe_query(rv$db_con, "
      SELECT player_id, display_name, member_number FROM players
      WHERE LOWER(display_name) = LOWER(?)
      LIMIT 1
    ", params = list(username))

    if (nrow(guest_lookup) > 0) {
      combined$matched_player_id[i] <- guest_lookup$player_id[1]
      combined$matched_player_name[i] <- guest_lookup$display_name[1]

      # If the DB has their real member number, pre-fill it
      if (!is.na(guest_lookup$member_number[1]) && nchar(guest_lookup$member_number[1]) > 0) {
        combined$member_number[i] <- guest_lookup$member_number[1]
        combined$match_status[i] <- "matched"
        if (verbose) message("[SUBMIT] GUEST '", username, "' matched to player with member number: ", guest_lookup$member_number[1])
      } else {
        combined$match_status[i] <- "matched"
        if (verbose) message("[SUBMIT] GUEST '", username, "' matched to existing player (no member number)")
      }
      next
    }
  }
}
```

**Step 2: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('server/public-submit-server.R')"`

**Step 3: Commit**

```bash
git add server/public-submit-server.R
git commit -m "feat: GUEST player database lookup by username

When a player has a GUEST member number, look up their username in the
database. If found with a real member number, pre-fill it in the review UI."
```

---

### Task 7: Update Batch Test Script for Ground Truth Comparison

Update `scripts/batch_test_ocr.R` to work with the new folder-based test structure and compare parsed results against `expected.csv` ground truth files.

**Files:**
- Modify: `scripts/batch_test_ocr.R`

**Step 1: Add folder-based batch testing function**

Add a new `batch_test_folders()` function that processes each test folder (containing one or more screenshots) and compares results against `expected.csv`:

```r
#' Run batch test on folder-based test cases
#'
#' Each subfolder in screenshots/standings/ represents one tournament.
#' Folder name format: Xplayers_Yrounds_Zscreenshots[_notes]
#' Each folder should contain screenshot images and an expected.csv ground truth.
#'
#' @param verbose Print detailed OCR/parse logs
#' @return Summary data frame with per-folder accuracy
batch_test_folders <- function(verbose = FALSE) {
  ensure_dirs()

  folders <- list.dirs(STANDINGS_DIR, full.names = TRUE, recursive = FALSE)
  if (length(folders) == 0) {
    message("No test folders found in ", STANDINGS_DIR)
    return(invisible(NULL))
  }

  message("\n", strrep("=", 60))
  message("FOLDER-BASED BATCH OCR TESTING")
  message(strrep("=", 60))
  message("Test folders: ", length(folders))
  message(strrep("=", 60), "\n")

  folder_results <- list()

  for (folder in folders) {
    folder_name <- basename(folder)
    images <- get_images(folder)

    if (length(images) == 0) {
      message("[", folder_name, "] No images found - SKIPPED")
      next
    }

    # Parse folder name for metadata
    parts <- strsplit(folder_name, "_")[[1]]
    total_players <- as.integer(gsub("players", "", parts[1]))
    total_rounds <- as.integer(gsub("rounds", "", parts[2]))

    message("[", folder_name, "] ", length(images), " images, ",
            total_players, " players, ", total_rounds, " rounds")

    # Process each screenshot
    all_parsed <- list()
    for (img in images) {
      ocr_result <- tryCatch({
        gcv_detect_text(img, verbose = verbose)
      }, error = function(e) {
        message("  OCR error on ", basename(img), ": ", e$message)
        NULL
      })

      if (is.null(ocr_result)) next

      parsed <- tryCatch({
        parse_standings(ocr_result, total_rounds = total_rounds, verbose = verbose)
      }, error = function(e) {
        message("  Parse error on ", basename(img), ": ", e$message)
        data.frame()
      })

      if (nrow(parsed) > 0) {
        all_parsed[[length(all_parsed) + 1]] <- parsed
        message("  ", basename(img), ": ", nrow(parsed), " players")
      }

      # Save annotation data for offline re-testing
      if (is.list(ocr_result)) {
        ann_file <- file.path(RESULTS_DIR, "ocr_text",
                              paste0(tools::file_path_sans_ext(basename(img)), "_annotations.rds"))
        saveRDS(ocr_result, ann_file)
      }
      # Save OCR text
      ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result
      txt_file <- file.path(RESULTS_DIR, "ocr_text",
                            paste0(tools::file_path_sans_ext(basename(img)), "_standings.txt"))
      writeLines(ocr_text, txt_file)
    }

    if (length(all_parsed) == 0) {
      message("  NO RESULTS PARSED")
      folder_results[[folder_name]] <- list(
        folder = folder_name, images = length(images),
        parsed = 0, expected = total_players,
        rank_correct = 0, username_correct = 0,
        member_correct = 0, points_correct = 0,
        accuracy = 0
      )
      next
    }

    # Merge multiple screenshots (same logic as submit handler)
    combined <- do.call(rbind, all_parsed)
    if (nrow(combined) > 1) {
      has_member <- !is.na(combined$member_number) & combined$member_number != ""
      if (any(has_member)) {
        is_guest <- has_member & grepl("^GUEST\\d+$", combined$member_number, ignore.case = TRUE)
        with_real <- combined[has_member & !is_guest, ]
        with_guest <- combined[is_guest, ]
        without <- combined[!has_member, ]

        with_real <- with_real[!duplicated(with_real$member_number), ]
        if (nrow(with_guest) > 0) {
          with_guest$ul <- tolower(with_guest$username)
          with_guest <- with_guest[!duplicated(with_guest$ul), ]
          with_guest$ul <- NULL
        }
        if (nrow(without) > 0) {
          without$ul <- tolower(without$username)
          without <- without[!duplicated(without$ul), ]
          without$ul <- NULL
        }
        combined <- rbind(with_real, with_guest, without)
      } else {
        combined$ul <- tolower(combined$username)
        combined <- combined[!duplicated(combined$ul), ]
        combined$ul <- NULL
      }
    }
    combined <- combined[order(combined$placement), ]

    # Compare against expected.csv if it exists
    expected_file <- file.path(folder, "expected.csv")
    if (file.exists(expected_file)) {
      expected <- read.csv(expected_file, stringsAsFactors = FALSE)

      # Match by rank and compare fields
      rank_correct <- 0
      username_correct <- 0
      member_correct <- 0
      points_correct <- 0
      total_fields <- 0

      for (r in seq_len(nrow(expected))) {
        exp_rank <- expected$rank[r]
        exp_row <- expected[r, ]

        # Find this rank in parsed results
        parsed_row <- combined[combined$placement == exp_rank, ]

        total_fields <- total_fields + 4  # rank, username, member, points

        if (nrow(parsed_row) > 0) {
          parsed_row <- parsed_row[1, ]  # Take first if multiple

          rank_correct <- rank_correct + 1  # Rank found

          if (tolower(trimws(parsed_row$username)) == tolower(trimws(exp_row$username))) {
            username_correct <- username_correct + 1
          } else {
            if (verbose) message("  MISMATCH rank ", exp_rank, " username: expected='",
                                  exp_row$username, "' got='", parsed_row$username, "'")
          }

          parsed_member <- gsub("^0+", "", parsed_row$member_number)
          expected_member <- gsub("^0+", "", exp_row$member_number)
          if (tolower(parsed_member) == tolower(expected_member)) {
            member_correct <- member_correct + 1
          } else {
            if (verbose) message("  MISMATCH rank ", exp_rank, " member: expected='",
                                  exp_row$member_number, "' got='", parsed_row$member_number, "'")
          }

          if (!is.na(parsed_row$points) && parsed_row$points == exp_row$points) {
            points_correct <- points_correct + 1
          } else {
            if (verbose) message("  MISMATCH rank ", exp_rank, " points: expected=",
                                  exp_row$points, " got=", parsed_row$points)
          }
        } else {
          if (verbose) message("  MISSING rank ", exp_rank, " (", exp_row$username, ")")
        }
      }

      accuracy <- if (total_fields > 0) round(100 * (rank_correct + username_correct + member_correct + points_correct) / total_fields, 1) else 0

      message("  Results: ", nrow(combined), "/", nrow(expected), " players | ",
              "rank:", rank_correct, "/", nrow(expected), " | ",
              "user:", username_correct, "/", nrow(expected), " | ",
              "member:", member_correct, "/", nrow(expected), " | ",
              "pts:", points_correct, "/", nrow(expected), " | ",
              "accuracy: ", accuracy, "%")

      folder_results[[folder_name]] <- list(
        folder = folder_name, images = length(images),
        parsed = nrow(combined), expected = nrow(expected),
        rank_correct = rank_correct, username_correct = username_correct,
        member_correct = member_correct, points_correct = points_correct,
        total_fields = total_fields, accuracy = accuracy
      )
    } else {
      message("  No expected.csv - parsed ", nrow(combined), " players (no ground truth)")
      folder_results[[folder_name]] <- list(
        folder = folder_name, images = length(images),
        parsed = nrow(combined), expected = total_players,
        rank_correct = NA, username_correct = NA,
        member_correct = NA, points_correct = NA,
        accuracy = NA
      )
    }

    # Save merged CSV
    csv_file <- file.path(RESULTS_DIR, "standings_parsed", paste0(folder_name, "_merged.csv"))
    write.csv(combined, csv_file, row.names = FALSE)
  }

  # Print summary
  message("\n", strrep("=", 60))
  message("SUMMARY")
  message(strrep("=", 60))

  total_correct <- 0
  total_fields <- 0
  for (fr in folder_results) {
    if (!is.na(fr$accuracy)) {
      total_correct <- total_correct + fr$rank_correct + fr$username_correct + fr$member_correct + fr$points_correct
      total_fields <- total_fields + fr$total_fields
    }
  }

  if (total_fields > 0) {
    message("Overall accuracy: ", total_correct, "/", total_fields,
            " fields correct (", round(100 * total_correct / total_fields, 1), "%)")
  }

  message(strrep("=", 60), "\n")
  invisible(folder_results)
}
```

**Step 2: Add `batch_retest_folders()` for offline re-testing**

Add a companion function that uses saved annotation data (`.rds` files) instead of calling the API:

```r
#' Re-run folder-based tests using saved annotation data (no API calls)
#'
#' @param verbose Print detailed parse logs
#' @return Summary data frame
batch_retest_folders <- function(verbose = TRUE) {
  ensure_dirs()

  folders <- list.dirs(STANDINGS_DIR, full.names = TRUE, recursive = FALSE)
  if (length(folders) == 0) {
    message("No test folders found")
    return(invisible(NULL))
  }

  message("\n", strrep("=", 60))
  message("FOLDER-BASED RE-TEST (using saved annotation data)")
  message(strrep("=", 60), "\n")

  for (folder in folders) {
    folder_name <- basename(folder)
    images <- get_images(folder)
    if (length(images) == 0) next

    parts <- strsplit(folder_name, "_")[[1]]
    total_rounds <- as.integer(gsub("rounds", "", parts[2]))

    message("[", folder_name, "]")

    all_parsed <- list()
    for (img in images) {
      name_base <- tools::file_path_sans_ext(basename(img))

      # Try loading saved annotations first
      ann_file <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_annotations.rds"))
      txt_file <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_standings.txt"))

      ocr_result <- NULL
      if (file.exists(ann_file)) {
        ocr_result <- readRDS(ann_file)
      } else if (file.exists(txt_file)) {
        ocr_result <- paste(readLines(txt_file, warn = FALSE), collapse = "\n")
      }

      if (is.null(ocr_result)) {
        message("  No saved data for ", basename(img))
        next
      }

      parsed <- tryCatch({
        parse_standings(ocr_result, total_rounds = total_rounds, verbose = verbose)
      }, error = function(e) {
        message("  Parse error: ", e$message)
        data.frame()
      })

      if (nrow(parsed) > 0) {
        all_parsed[[length(all_parsed) + 1]] <- parsed
        message("  ", basename(img), ": ", nrow(parsed), " players")
      }
    }

    if (length(all_parsed) > 0) {
      combined <- do.call(rbind, all_parsed)
      # Dedup
      if (nrow(combined) > 1) {
        has_member <- !is.na(combined$member_number) & combined$member_number != ""
        if (any(has_member)) {
          combined <- combined[!duplicated(combined$member_number) | !has_member, ]
        }
        combined$ul <- tolower(combined$username)
        combined <- combined[!duplicated(paste(combined$member_number, combined$ul)), ]
        combined$ul <- NULL
      }
      combined <- combined[order(combined$placement), ]
      message("  Merged: ", nrow(combined), " unique players")
    }
  }

  message("\n", strrep("=", 60))
  message("Re-test complete.")
  message(strrep("=", 60), "\n")
}
```

**Step 3: Update the loaded message to show new commands**

Update the `if (interactive())` block at the bottom of the file to include the new functions:

```r
if (interactive()) {
  message("\n", strrep("=", 60))
  message("Batch OCR Test Script Loaded")
  message(strrep("=", 60))
  message("\nFolder structure:")
  message("  screenshots/standings/<folder>/  <- Tournament screenshots + expected.csv")
  message("  screenshots/match_history/       <- Match history screenshots")
  message("\nCommands:")
  message("  batch_test_folders()  - Process all test folders (calls API)")
  message("  batch_retest_folders() - Re-parse saved data (no API)")
  message("  batch_test()          - Legacy: process flat screenshots (calls API)")
  message("  batch_retest()        - Legacy: re-parse saved OCR text (no API)")
  message("  review_flagged()      - Interactively review problem files")
  message(strrep("=", 60), "\n")
}
```

**Step 4: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('scripts/batch_test_ocr.R')"`

**Step 5: Commit**

```bash
git add scripts/batch_test_ocr.R
git commit -m "feat: folder-based batch testing with ground truth comparison

batch_test_folders() processes each test folder, merges multi-screenshot
results, compares against expected.csv, reports per-field accuracy.
batch_retest_folders() uses saved annotation data for offline re-testing."
```

---

### Task 8: Update Interactive Test Script

Update `scripts/test_ocr.R` to support the new parser and show both layout and text parser results for comparison.

**Files:**
- Modify: `scripts/test_ocr.R`

**Step 1: Update `test_image()` to use new orchestrator**

Update the function to call `parse_standings()` (the orchestrator) and show which parser was used. Also save annotation data for re-testing.

Find `test_image()` (~line 54) and update the OCR call and parse sections:

```r
test_image <- function(image_path, rounds = 4, verbose = TRUE) {
  if (!file.exists(image_path)) {
    stop("File not found: ", image_path)
  }

  message("\n", strrep("=", 60))
  message("Testing OCR on: ", image_path)
  message(strrep("=", 60), "\n")

  # Step 1: Get OCR result (with annotations)
  ocr_result <- gcv_detect_text(image_path, verbose = verbose)

  if (is.null(ocr_result)) {
    message("\nOCR failed - check API key and image")
    return(NULL)
  }

  # Extract text for display
  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  # Save globally for easy re-testing
  assign(".last_ocr_text", ocr_text, envir = globalenv())
  assign(".last_ocr_result", ocr_result, envir = globalenv())

  # Save raw OCR text for debugging
  message("\n", strrep("-", 60))
  message("RAW OCR TEXT:")
  message(strrep("-", 60))
  cat(ocr_text)
  message("\n")

  # Show annotation count
  if (is.list(ocr_result) && nrow(ocr_result$annotations) > 0) {
    message("\nAnnotations: ", nrow(ocr_result$annotations), " words")
    message("Image dimensions: ", ocr_result$image_width, "x", ocr_result$image_height)
  }
```

Also update `test_parse()` and add a new `test_compare()` function that shows side-by-side output from both parsers:

```r
#' Compare layout vs text parser on last OCR result
#'
#' @param rounds Total rounds
#' @param verbose Print debug messages
test_compare <- function(rounds = 4, verbose = TRUE) {
  ocr_result <- get(".last_ocr_result", envir = globalenv())
  if (is.null(ocr_result)) {
    message("No saved OCR result. Run test_image() first.")
    return(NULL)
  }

  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  message("\n", strrep("=", 60))
  message("LAYOUT PARSER:")
  message(strrep("=", 60))
  if (is.list(ocr_result) && nrow(ocr_result$annotations) > 0) {
    layout_result <- parse_standings_layout(
      ocr_result$annotations, ocr_result$image_width, ocr_result$image_height,
      total_rounds = rounds, verbose = verbose
    )
    print(format_ui_preview(layout_result))
  } else {
    message("No annotation data available")
  }

  message("\n", strrep("=", 60))
  message("TEXT PARSER:")
  message(strrep("=", 60))
  text_result <- parse_tournament_standings(ocr_text, total_rounds = rounds, verbose = verbose)
  print(format_ui_preview(text_result))
}
```

**Step 2: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('scripts/test_ocr.R')"`

**Step 3: Commit**

```bash
git add scripts/test_ocr.R
git commit -m "feat: update test script for layout parser with comparison mode

test_image() now saves full annotation data. test_compare() shows
side-by-side output from layout vs text parser for debugging."
```

---

### Task 9: End-to-End Verification and Tuning

Run the batch tests against ground truth and tune the parser parameters.

**Files:**
- Possibly modify: `R/ocr.R` (tune column boundaries, row clustering threshold)
- Possibly modify: `screenshots/standings/*/expected.csv` (correct ground truth if needed)

**Step 1: Run batch_test_folders()**

```r
source("scripts/batch_test_ocr.R")
results <- batch_test_folders(verbose = TRUE)
```

Review the accuracy report. Target: >95% field accuracy across all test folders.

**Step 2: Identify and fix any systematic errors**

Common tuning areas:
- **Column boundary percentages** — If usernames are being placed in the wrong column, adjust `col_boundaries` defaults in `parse_standings_layout()`
- **Row clustering threshold** — If rows are being split or merged incorrectly, adjust the 1.5% gap threshold
- **Noise filtering** — If real data is being filtered, or noise is getting through, update the noise patterns
- **Member number detection** — If member numbers in the username column aren't being found, check the regex patterns
- **Points column overlap** — If OMW% values are leaking into points, tighten the `points_max` boundary

**Step 3: Run batch_retest_folders() to verify changes offline**

After any parser changes:
```r
batch_retest_folders(verbose = TRUE)
```

This re-parses using saved annotation data (no API calls) to iterate quickly.

**Step 4: Commit tuning changes**

```bash
git add R/ocr.R
git commit -m "fix: tune layout parser parameters based on test results

[Describe specific changes based on what needed tuning]"
```

---

## Files Changed Summary

| File | Change |
|------|--------|
| `R/ocr.R` | Modified `gcv_detect_text()` return type, added `parse_standings_layout()`, added `parse_standings()` orchestrator |
| `server/public-submit-server.R` | Updated OCR call to use new return type, ranking-aware merge logic, GUEST player DB lookup |
| `scripts/batch_test_ocr.R` | Added `batch_test_folders()` and `batch_retest_folders()` with ground truth comparison |
| `scripts/test_ocr.R` | Updated for new OCR return type, added `test_compare()` |
| `screenshots/standings/*/expected.csv` | Ground truth files (new) |

## Execution Notes

- Tasks 1-2 can be done in parallel (ground truth CSVs are independent of code changes)
- Tasks 3-4 must be sequential (Task 4 depends on Task 3's function)
- Task 5-6 can be done in parallel (merge logic and GUEST lookup are independent sections)
- Task 7-8 can be done in parallel (batch test and interactive test are independent scripts)
- Task 9 depends on all previous tasks

## Testing Strategy

- **No automated test suite** — This project uses manual R testing via the test scripts
- **Ground truth CSVs** are the closest thing to automated tests
- **batch_test_folders()** is the primary verification tool — run it after each task
- **batch_retest_folders()** allows fast iteration without API calls
- **test_compare()** helps debug individual screenshots by showing both parsers side-by-side
