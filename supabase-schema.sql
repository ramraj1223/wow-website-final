-- ============================================================
-- WOW HOME TRANSFORMATIONS - SUPABASE SCHEMA
-- Copy & paste this entire script into your Supabase SQL Editor
-- ============================================================

-- Create leads table
CREATE TABLE leads (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT NOT NULL,
  project_type TEXT,
  timeline TEXT,
  address TEXT,
  message TEXT,
  photo_urls JSONB,
  estimate_total INTEGER,
  selected_addons JSONB,
  material_grade TEXT,
  source TEXT NOT NULL,
  status TEXT DEFAULT 'new',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable row-level security
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;

-- Create policy: allow anyone to INSERT (public form submission)
CREATE POLICY "Allow public form submissions"
ON leads FOR INSERT
WITH CHECK (true);

-- Create policy: allow authenticated users to SELECT all leads (for your admin dashboard)
CREATE POLICY "Allow authenticated users to view leads"
ON leads FOR SELECT
USING (auth.role() = 'authenticated');

-- Create an index on email for faster lookups
CREATE INDEX idx_leads_email ON leads(email);

-- Create an index on created_at for sorting
CREATE INDEX idx_leads_created_at ON leads(created_at DESC);

-- Create an index on source for filtering
CREATE INDEX idx_leads_source ON leads(source);

-- Create an index on status for filtering
CREATE INDEX idx_leads_status ON leads(status);

-- ============================================================
-- STORAGE BUCKET FOR PHOTOS (Optional)
-- This is for the photo uploads from forms
-- ============================================================

-- Supabase creates storage buckets via the UI. 
-- Do this manually in Supabase console:
-- 1. Go to Storage → New Bucket
-- 2. Name: "project-photos"
-- 3. Make it PUBLIC (so URLs are accessible)
-- 4. You're done — the JavaScript will handle uploads

-- ============================================================
-- NOTES:
-- - Leads table is ready for production
-- - All fields are nullable except: id, name, phone, email, source
-- - Status field defaults to 'new' — update manually in dashboard
-- - JSONB fields store arrays (photo URLs, add-ons, etc.)
-- ============================================================
