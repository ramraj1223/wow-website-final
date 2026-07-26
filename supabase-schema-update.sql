-- ============================================================
-- WOW HOME TRANSFORMATIONS — LEADS TABLE SCHEMA UPDATE
-- Run this once in the Supabase SQL Editor to add the columns the
-- new Google/Facebook funnel pages (google-consult.html,
-- qualify-booking.html, free-design.html, price-estimator.html,
-- index.html) now write to. Safe to run on the existing `leads`
-- table — every column is nullable, so it will not fail even if
-- rows already exist.
-- ============================================================

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS lead_source           TEXT,        -- ad channel: 'homepage' | 'google_ads' | 'facebook_ads' | 'price_estimator'
  ADD COLUMN IF NOT EXISTS flow                   TEXT,        -- funnel: 'homepage' | 'google_consult' | 'free_design' | 'guide_download' | 'render_photos'
  ADD COLUMN IF NOT EXISTS qualification_status   TEXT,        -- 'qualified' | 'unqualified' — google_consult flow only
  ADD COLUMN IF NOT EXISTS owns_property          TEXT,        -- 'Yes' | 'No' — google_consult flow only
  ADD COLUMN IF NOT EXISTS budget_tier            TEXT,        -- 'A' | 'B' | 'C' | 'D' — google_consult flow only, see google-consult.html §5.3
  ADD COLUMN IF NOT EXISTS city                   TEXT,        -- google_consult flow only
  ADD COLUMN IF NOT EXISTS zip_code               TEXT,        -- free_design flow only
  ADD COLUMN IF NOT EXISTS decision_makers_present TEXT,       -- 'Yes' | 'No' — google_consult flow only
  ADD COLUMN IF NOT EXISTS quiz_answers           JSONB,       -- { bathroom, finish, scope, room_size, labor_total, materials_low, materials_high } — free_design flow only
  ADD COLUMN IF NOT EXISTS utm                    JSONB;       -- { source, medium, campaign, term, content, page_url }

-- Indexes for the fields Make.com / any future dashboard will filter or branch on,
-- matching the existing indexing pattern already used on `source`/`status`.
CREATE INDEX IF NOT EXISTS idx_leads_flow                 ON leads(flow);
CREATE INDEX IF NOT EXISTS idx_leads_lead_source           ON leads(lead_source);
CREATE INDEX IF NOT EXISTS idx_leads_qualification_status  ON leads(qualification_status);

-- ============================================================
-- NOTES:
-- - The existing `source` column is untouched — it still tracks which
--   *form* on the site submitted (e.g. 'hero_form', 'google_consult_form',
--   'free_design_guide_form', 'price_estimator'), while the new `flow`
--   column tracks which *funnel stage* it belongs to.
-- - `qualification_status`, `owns_property`, `budget_tier`, `city`, and
--   `decision_makers_present` are only ever populated by google-consult.html's
--   qualification form. `zip_code` is only populated by free-design.html's
--   guide form — the two pages collect different location granularity.
-- - `quiz_answers` is only populated by free-design.html's 3-question quiz.
-- - `utm` is populated on every new-funnel page load from the URL's
--   utm_source/utm_medium/utm_campaign/utm_term/utm_content params, plus
--   the full page_url, so ad performance can be traced per lead.
-- ============================================================
