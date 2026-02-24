# International Physical Store Support

**Date:** 2026-02-23
**Status:** Approved

## Problem

The store admin form only supports US addresses — it has a hardcoded US state dropdown (50 states + DC) and a "ZIP Code" field. Physical stores always default to `country = "USA"`. Users from Vancouver BC Canada need to be onboarded, so we need international address support.

## Design

### Approach: Free-text State/Province + Full Country List

Replace the US-only state dropdown with a free-text input and add a full ~195 country dropdown with type-to-search. Mapbox geocoding already works internationally.

### Changes

**1. New file: `R/constants.R`**
- Define `COUNTRY_CHOICES` — full ISO country list with USA at top, then alphabetical
- Sourced by app.R so it's available to both UI and server

**2. UI: `views/admin-stores-ui.R`**
- Physical store form: Add Country dropdown (`selectize = TRUE` for search), replace State `selectInput` with free-text `textInput` ("State / Province"), rename "ZIP Code" to "Postal Code"
- Online store form: Replace 6-item country list with shared `COUNTRY_CHOICES`

**3. Server: `server/admin-stores-server.R`**
- Add store: Use selected country instead of hardcoding "USA". Include country in geocoding address string.
- Update store: Same country handling.
- Form resets: Default to "USA" country, empty state/province.

**4. Schema: `db/schema.sql`**
- Remove `DEFAULT 'TX'` from `state` column (documentation only, no migration needed)

### No Changes Needed
- Mapbox geocoding works internationally as-is
- Public stores display (`public-stores-server.R`) handles state as a generic string
- Scenes hierarchy already supports international regions
