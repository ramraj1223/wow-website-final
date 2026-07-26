-- ============================================================
-- WOW HOME TRANSFORMATIONS — COMPLETE LEADS SCHEMA
-- Run this once, start to finish, in the Supabase SQL Editor.
-- Every statement is idempotent (IF NOT EXISTS / DROP+CREATE),
-- so it's safe to re-run any time — on a brand-new database or
-- one that already has some of this in place.
--
-- This single file supersedes supabase-schema.sql and
-- supabase-schema-update.sql — you only need to run this one.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS leads (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       TEXT NOT NULL,
  phone      TEXT NOT NULL,
  email      TEXT NOT NULL,
  source     TEXT NOT NULL,              -- which FORM submitted it, e.g. 'hero_form' | 'price_estimator' | 'google_consult_form' | 'free_design_breakdown_form' | 'qualify_booking_render_photos'
  status     TEXT DEFAULT 'new',         -- owner-editable pipeline stage: 'new' | 'contacted' | 'booked' | 'won' | 'lost'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Every column below is nullable — each form only fills in the subset
-- it collects. Safe no-ops if a column already exists.
ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS project_type            TEXT,
  ADD COLUMN IF NOT EXISTS timeline                TEXT,
  ADD COLUMN IF NOT EXISTS message                 TEXT,
  ADD COLUMN IF NOT EXISTS address                 TEXT,
  ADD COLUMN IF NOT EXISTS city                    TEXT,          -- google_consult flow only
  ADD COLUMN IF NOT EXISTS zip_code                TEXT,          -- legacy field, no longer written by any current form
  ADD COLUMN IF NOT EXISTS photo_urls              JSONB,         -- array of uploaded photo URLs (project-photos storage bucket)
  ADD COLUMN IF NOT EXISTS estimate_total           INTEGER,       -- price_estimator flow only
  ADD COLUMN IF NOT EXISTS selected_addons          JSONB,         -- legacy field, no longer written by any current form
  ADD COLUMN IF NOT EXISTS material_grade           TEXT,          -- legacy field, no longer written by any current form
  ADD COLUMN IF NOT EXISTS lead_source              TEXT,          -- ad channel: 'homepage' | 'price_estimator' | 'google_ads' | 'facebook_ads'
  ADD COLUMN IF NOT EXISTS flow                     TEXT,          -- funnel stage: 'homepage' | 'guide_download' | 'google_consult' | 'free_design' | 'render_photos'
  ADD COLUMN IF NOT EXISTS qualification_status     TEXT,          -- 'qualified' | 'unqualified' — google_consult flow only
  ADD COLUMN IF NOT EXISTS owns_property            TEXT,          -- 'Yes' | 'No' — google_consult flow only
  ADD COLUMN IF NOT EXISTS budget_tier              TEXT,          -- 'A' | 'B' | 'C' | 'D' — google_consult flow only
  ADD COLUMN IF NOT EXISTS decision_makers_present  TEXT,          -- 'Yes' | 'No' — google_consult flow only
  ADD COLUMN IF NOT EXISTS quiz_answers             JSONB,         -- { bathroom, finish, scope, room_size, labor_total, materials_low, materials_high } — free_design flow only
  ADD COLUMN IF NOT EXISTS utm                      JSONB;         -- { source, medium, campaign, term, content, page_url } — captured on every funnel page

-- Indexes for whatever dashboard/CRM view you build to browse this.
CREATE INDEX IF NOT EXISTS idx_leads_created_at           ON leads(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leads_email                ON leads(email);
CREATE INDEX IF NOT EXISTS idx_leads_source               ON leads(source);
CREATE INDEX IF NOT EXISTS idx_leads_status               ON leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_flow                 ON leads(flow);
CREATE INDEX IF NOT EXISTS idx_leads_lead_source           ON leads(lead_source);
CREATE INDEX IF NOT EXISTS idx_leads_qualification_status  ON leads(qualification_status);

-- ============================================================
-- ROW-LEVEL SECURITY
-- Public site visitors can INSERT (submit a form). Only a signed-in
-- (authenticated) user can SELECT — this is what your future owner
-- login/dashboard will rely on to read all lead data.
-- ============================================================
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public form submissions" ON leads;
CREATE POLICY "Allow public form submissions"
  ON leads FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users to view leads" ON leads;
CREATE POLICY "Allow authenticated users to view leads"
  ON leads FOR SELECT
  USING (auth.role() = 'authenticated');

-- ============================================================
-- NOTES
-- ============================================================
-- - source = which specific FORM submitted (hero_form, price_estimator,
--   google_consult_form, free_design_breakdown_form, qualify_booking_render_photos).
-- - flow = which FUNNEL STAGE it belongs to (homepage, guide_download,
--   google_consult, free_design, render_photos).
-- - quiz_answers / utm / photo_urls are JSONB, so their shape can change
--   later (e.g. adding a new quiz question) without another migration.
--
-- FOR YOUR FUTURE LOGIN/DASHBOARD:
-- - Create yourself a user under Supabase → Authentication → Users → Add User.
-- - Any page that signs that user in with supabase-js (supabase.auth.signInWithPassword)
--   and then queries `.from('leads').select('*')` will see every row, thanks to
--   the SELECT policy above — no further SQL changes needed for that part.
--
-- PHOTO UPLOADS:
-- - Requires a Storage bucket named "project-photos", set to Public.
--   Create it once via Supabase Dashboard → Storage → New Bucket
--   (bucket creation isn't something the SQL editor can do).
-- ============================================================
