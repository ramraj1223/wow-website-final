-- ============================================================
-- WOW HOME TRANSFORMATIONS - ADMIN DASHBOARD SCHEMA (admin.html)
-- Paste this whole script into Supabase → SQL Editor → Run.
-- Safe to run more than once (also safe if you ran an earlier version).
-- Builds on the existing "leads" table.
-- ============================================================

-- ------------------------------------------------------------
-- 1. STAFF — only emails listed here can see dashboard data.
--    (Protects your data even if Supabase sign-ups are left on.)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staff (
  email TEXT PRIMARY KEY CHECK (email = lower(email)),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can see own row" ON staff;
CREATE POLICY "Staff can see own row" ON staff
FOR SELECT USING (email = lower(auth.jwt() ->> 'email'));

CREATE OR REPLACE FUNCTION is_staff() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM staff WHERE email = lower(auth.jwt() ->> 'email'));
$$;

-- >>> EDIT THIS: put your own login email(s) here, in lowercase <<<
INSERT INTO staff (email) VALUES ('you@example.com')
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- 2. LEAD SOURCES — managed on the dashboard's Settings page.
--    is_paid = this source is paid for by your lead spend (used for ROAS).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lead_sources (
  key TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  is_paid BOOLEAN DEFAULT FALSE,
  sort INTEGER DEFAULT 100
);
ALTER TABLE lead_sources ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff manage sources" ON lead_sources;
CREATE POLICY "Staff manage sources" ON lead_sources
FOR ALL USING (is_staff()) WITH CHECK (is_staff());

INSERT INTO lead_sources (key, label, is_paid, sort) VALUES
  ('google_ads_landing',    'Google Ads landing page', TRUE,  10),
  ('google',                'Google',                  TRUE,  12),
  ('facebook',              'Facebook',                TRUE,  14),
  ('price_estimator',       'Price estimator',         TRUE,  20),
  ('bathroom_remodel_page', 'Bathroom remodel page',   TRUE,  30),
  ('homepage_hero_form',    'Homepage',                FALSE, 40),
  ('workshop_hero_form',    'Workshop page',           FALSE, 50),
  ('referral',              'Referral',                FALSE, 60),
  ('phone',                 'Phone call',              FALSE, 70),
  ('walk_in',               'Walk-in / showroom',      FALSE, 80),
  ('other',                 'Other',                   FALSE, 90)
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------
-- 3. LEADS — add dashboard fields, lock reading/editing to staff
-- ------------------------------------------------------------
ALTER TABLE leads ADD COLUMN IF NOT EXISTS appointment_date TIMESTAMPTZ;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS follow_up DATE;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS won_at TIMESTAMPTZ;
UPDATE leads SET status = 'new' WHERE status IS NULL;

-- Old policy let ANY logged-in user read leads; replace with staff-only
DROP POLICY IF EXISTS "Allow authenticated users to view leads" ON leads;
DROP POLICY IF EXISTS "Staff can view leads" ON leads;
DROP POLICY IF EXISTS "Staff can update leads" ON leads;
DROP POLICY IF EXISTS "Staff can delete leads" ON leads;
CREATE POLICY "Staff can view leads"   ON leads FOR SELECT USING (is_staff());
CREATE POLICY "Staff can update leads" ON leads FOR UPDATE USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Staff can delete leads" ON leads FOR DELETE USING (is_staff());
-- (The existing "Allow public form submissions" INSERT policy stays as-is,
--  and also lets staff add leads by hand from the dashboard.)

CREATE INDEX IF NOT EXISTS idx_leads_appointment ON leads(appointment_date);
CREATE INDEX IF NOT EXISTS idx_leads_won_at ON leads(won_at);

-- Stamp the "won on" date when a lead becomes won (cleared if it's moved back)
CREATE OR REPLACE FUNCTION set_lead_won_at() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'won' THEN
    NEW.won_at := COALESCE(NEW.won_at, NOW());
  ELSE
    NEW.won_at := NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS lead_set_won_at ON leads;
CREATE TRIGGER lead_set_won_at
BEFORE INSERT OR UPDATE OF status, won_at ON leads
FOR EACH ROW EXECUTE FUNCTION set_lead_won_at();

-- ------------------------------------------------------------
-- 4. CUSTOMERS
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID UNIQUE REFERENCES leads(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  city TEXT,
  source TEXT,
  reviewed BOOLEAN DEFAULT FALSE,
  notes TEXT,
  customer_since DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff manage customers" ON customers;
CREATE POLICY "Staff manage customers" ON customers
FOR ALL USING (is_staff()) WITH CHECK (is_staff());

-- When a lead is marked "won" (or added already won), create its customer
CREATE OR REPLACE FUNCTION create_customer_from_won_lead() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'won' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'won') THEN
    INSERT INTO customers (lead_id, name, phone, email, address, source, customer_since)
    VALUES (NEW.id, NEW.name, NEW.phone, NEW.email, NEW.address, NEW.source,
            COALESCE(NEW.won_at, NOW())::date)
    ON CONFLICT (lead_id) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS lead_won_to_customer ON leads;
CREATE TRIGGER lead_won_to_customer
AFTER INSERT OR UPDATE OF status ON leads
FOR EACH ROW EXECUTE FUNCTION create_customer_from_won_lead();

-- Backfill: leads already won get a "won on" date
UPDATE leads l SET won_at = COALESCE((SELECT c.created_at FROM customers c WHERE c.lead_id = l.id), l.created_at)
WHERE l.status = 'won' AND l.won_at IS NULL;

-- ------------------------------------------------------------
-- 5. JOBS
-- ------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS job_no_seq START 1001;

CREATE TABLE IF NOT EXISTS jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_no TEXT UNIQUE NOT NULL DEFAULT 'WOW-' || nextval('job_no_seq'),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
  project_type TEXT,
  crew TEXT,
  status TEXT NOT NULL DEFAULT 'scheduled',
  start_date DATE,
  end_date DATE,
  contract_value NUMERIC(10,2) DEFAULT 0,
  materials_cost NUMERIC(10,2) DEFAULT 0,
  labor_cost NUMERIC(10,2) DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
-- Custom job statuses can be added on the Settings page, so no fixed list here
ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_status_check;

ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff manage jobs" ON jobs;
CREATE POLICY "Staff manage jobs" ON jobs
FOR ALL USING (is_staff()) WITH CHECK (is_staff());

CREATE INDEX IF NOT EXISTS idx_jobs_customer ON jobs(customer_id);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);

-- ------------------------------------------------------------
-- 6. PAYMENTS — each payment received on a job (date + amount)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  paid_on DATE NOT NULL DEFAULT CURRENT_DATE,
  amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  method TEXT,
  note TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff manage payments" ON payments;
CREATE POLICY "Staff manage payments" ON payments
FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE INDEX IF NOT EXISTS idx_payments_job ON payments(job_id);
CREATE INDEX IF NOT EXISTS idx_payments_paid_on ON payments(paid_on);

-- If an earlier version of this script added a single "paid" total on jobs,
-- move those amounts into payments (one payment each), then remove the column.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'paid') THEN
    INSERT INTO payments (job_id, paid_on, amount, note)
    SELECT id, COALESCE(start_date, created_at::date), paid, 'Moved from old "amount paid" total'
    FROM jobs WHERE paid > 0;
    ALTER TABLE jobs DROP COLUMN paid;
  END IF;
END $$;

-- ------------------------------------------------------------
-- 7. MARKETING SPEND — what you spent per month, per source
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS marketing_spend (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  month DATE NOT NULL CHECK (EXTRACT(DAY FROM month) = 1),   -- first day of the month
  source TEXT NOT NULL REFERENCES lead_sources(key) ON UPDATE CASCADE,
  amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (month, source)
);
ALTER TABLE marketing_spend ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff manage spend" ON marketing_spend;
CREATE POLICY "Staff manage spend" ON marketing_spend
FOR ALL USING (is_staff()) WITH CHECK (is_staff());

-- ------------------------------------------------------------
-- 8. SETTINGS
--    monthly_lead_spend  = default for any month with no spend entered
--    extra_lead_statuses / extra_job_statuses   = your own added statuses
--    hidden_lead_statuses / hidden_job_statuses = built-in statuses you deleted
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff manage settings" ON app_settings;
CREATE POLICY "Staff manage settings" ON app_settings
FOR ALL USING (is_staff()) WITH CHECK (is_staff());

INSERT INTO app_settings (key, value) VALUES
  ('monthly_lead_spend', '2500'),
  ('extra_lead_statuses', '[]'),
  ('extra_job_statuses', '[]'),
  ('hidden_lead_statuses', '[]'),
  ('hidden_job_statuses', '[]')
ON CONFLICT (key) DO NOTHING;
