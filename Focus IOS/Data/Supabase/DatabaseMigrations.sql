-- Focus iOS App - Database Schema
-- Run this in Supabase SQL Editor to create all tables with Row Level Security

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==============================================
-- CATEGORIES TABLE
-- User-defined tags for organizing tasks
-- NOTE: Created first because tasks table references it
-- ==============================================

CREATE TABLE IF NOT EXISTS categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  created_date TIMESTAMPTZ DEFAULT NOW(),

  -- Unique constraint: one user can't have duplicate category names
  UNIQUE(user_id, name)
);

-- Indexes for categories
CREATE INDEX IF NOT EXISTS idx_categories_user_id ON categories(user_id);

-- Enable Row Level Security
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

-- RLS Policies for categories
DROP POLICY IF EXISTS "Users can view their own categories" ON categories;
CREATE POLICY "Users can view their own categories"
  ON categories FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own categories" ON categories;
CREATE POLICY "Users can insert their own categories"
  ON categories FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own categories" ON categories;
CREATE POLICY "Users can update their own categories"
  ON categories FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own categories" ON categories;
CREATE POLICY "Users can delete their own categories"
  ON categories FOR DELETE
  USING (auth.uid() = user_id);

-- ==============================================
-- TASKS TABLE
-- Core table for tasks, projects, and lists
-- ==============================================

CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL CHECK (type IN ('task', 'project', 'list')),
  is_completed BOOLEAN DEFAULT false,
  completed_date TIMESTAMPTZ,
  created_date TIMESTAMPTZ DEFAULT NOW(),
  modified_date TIMESTAMPTZ DEFAULT NOW(),
  sort_order INTEGER DEFAULT 0,
  is_in_library BOOLEAN DEFAULT true,
  previous_completion_state JSONB,
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('high', 'medium', 'low')),

  -- Foreign keys
  category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
  project_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
  parent_task_id UUID REFERENCES tasks(id) ON DELETE CASCADE
);

-- Indexes for tasks table
CREATE INDEX IF NOT EXISTS idx_tasks_user_id ON tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id ON tasks(parent_task_id);
CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_type ON tasks(type);
CREATE INDEX IF NOT EXISTS idx_tasks_is_completed ON tasks(is_completed);

-- Enable Row Level Security
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- RLS Policies for tasks
DROP POLICY IF EXISTS "Users can view their own tasks" ON tasks;
CREATE POLICY "Users can view their own tasks"
  ON tasks FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own tasks" ON tasks;
CREATE POLICY "Users can insert their own tasks"
  ON tasks FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own tasks" ON tasks;
CREATE POLICY "Users can update their own tasks"
  ON tasks FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own tasks" ON tasks;
CREATE POLICY "Users can delete their own tasks"
  ON tasks FOR DELETE
  USING (auth.uid() = user_id);

-- ==============================================
-- SCHEDULES TABLE
-- Task schedules to timeframes (Daily/Weekly/Monthly/Yearly)
-- ==============================================

CREATE TABLE IF NOT EXISTS schedules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  task_id UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
  timeframe TEXT NOT NULL CHECK (timeframe IN ('daily', 'weekly', 'monthly', 'yearly')),
  section TEXT NOT NULL CHECK (section IN ('target', 'todo')),
  schedule_date TIMESTAMPTZ NOT NULL,
  sort_order INTEGER DEFAULT 0,
  created_date TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for schedules - optimized for frequent queries
CREATE INDEX IF NOT EXISTS idx_schedules_user_id ON schedules(user_id);
CREATE INDEX IF NOT EXISTS idx_schedules_task_id ON schedules(task_id);
CREATE INDEX IF NOT EXISTS idx_schedules_lookup ON schedules(user_id, timeframe, schedule_date, section, sort_order);

-- Enable Row Level Security
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;

-- RLS Policies for schedules
DROP POLICY IF EXISTS "Users can view their own schedules" ON schedules;
CREATE POLICY "Users can view their own schedules"
  ON schedules FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own schedules" ON schedules;
CREATE POLICY "Users can insert their own schedules"
  ON schedules FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own schedules" ON schedules;
CREATE POLICY "Users can update their own schedules"
  ON schedules FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own schedules" ON schedules;
CREATE POLICY "Users can delete their own schedules"
  ON schedules FOR DELETE
  USING (auth.uid() = user_id);

-- ==============================================
-- TRICKLE-DOWN SCHEDULE SUPPORT
-- Parent-child relationship for breaking down schedules
-- ==============================================

-- Add parent_schedule_id column for hierarchical schedules
-- This enables Year → Month → Week → Day breakdown
ALTER TABLE schedules
ADD COLUMN IF NOT EXISTS parent_schedule_id UUID REFERENCES schedules(id) ON DELETE CASCADE;

-- Index for efficient parent-child lookups
CREATE INDEX IF NOT EXISTS idx_schedules_parent_id ON schedules(parent_schedule_id);

-- ==============================================
-- CATEGORY TYPE COLUMN (VESTIGIAL)
-- Previously used to separate task/list/project categories.
-- Categories are now shared across all item types.
-- The column remains for backward compatibility but is no longer
-- filtered on or set explicitly by the app.
-- ==============================================

-- Add type column to categories (default 'task' for backward compatibility)
ALTER TABLE categories ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'task';

-- Index for type-filtered lookups (kept for backward compatibility)
CREATE INDEX IF NOT EXISTS idx_categories_type ON categories(type);

-- ==============================================
-- SCHEDULED TIME SUPPORT
-- Time-of-day scheduling for calendar timeline
-- ==============================================

-- Add scheduled time and duration for timeline display
ALTER TABLE schedules ADD COLUMN IF NOT EXISTS scheduled_time TIMESTAMPTZ;
ALTER TABLE schedules ADD COLUMN IF NOT EXISTS duration_minutes INTEGER DEFAULT 30;

-- Index for efficient timeline queries (fetching timed schedules for a day)
CREATE INDEX IF NOT EXISTS idx_schedules_scheduled_time
ON schedules(user_id, scheduled_time)
WHERE scheduled_time IS NOT NULL;

-- ==============================================
-- TASK PRIORITY SUPPORT
-- Categorize tasks by priority level (high, medium, low)
-- ==============================================

-- Add priority column with default 'medium'
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'medium';

-- Add check constraint (safe for existing rows since default is 'medium')
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'tasks_priority_check'
  ) THEN
    ALTER TABLE tasks ADD CONSTRAINT tasks_priority_check CHECK (priority IN ('high', 'medium', 'low'));
  END IF;
END$$;

-- ==============================================
-- VERIFICATION QUERIES
-- Run these after migration to verify setup
-- ==============================================

-- Check that all tables were created
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('tasks', 'categories', 'schedules');

-- Check that RLS is enabled
-- SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('tasks', 'categories', 'schedules');

-- Check policies
-- SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('tasks', 'categories', 'schedules');

-- Check parent_schedule_id column exists
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'schedules' AND column_name = 'parent_schedule_id';

-- ==============================================
-- SECTION VALUE RENAME
-- Rename section values from 'focus'/'extra' to 'target'/'todo'
-- Run AFTER deploying the updated app code
-- ==============================================

-- Update check constraint to allow new values (drop old, add new)
ALTER TABLE schedules DROP CONSTRAINT IF EXISTS schedules_section_check;
ALTER TABLE schedules ADD CONSTRAINT schedules_section_check CHECK (section IN ('target', 'todo'));

-- Migrate existing data
UPDATE schedules SET section = 'target' WHERE section = 'focus';
UPDATE schedules SET section = 'todo'   WHERE section = 'extra';

-- ==============================================
-- PROJECT SECTIONS SUPPORT
-- Sections are visual header dividers within projects.
-- Stored as task rows with is_section = true.
-- ==============================================

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS is_section BOOLEAN DEFAULT false;

-- ==============================================
-- ARCHIVE SOFT-DELETE SUPPORT
-- Cleared items are hidden from local views but
-- remain visible in Archive. Only Archive can
-- permanently delete items.
-- ==============================================

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS is_cleared BOOLEAN DEFAULT false;

-- ==============================================
-- RENAME COMMITMENTS → SCHEDULES (MIGRATION)
-- Run this on existing databases to rename the table and columns.
-- Safe to run multiple times (uses IF EXISTS checks).
-- ==============================================

-- 1. Rename columns first (before table rename)
ALTER TABLE IF EXISTS commitments RENAME COLUMN commitment_date TO schedule_date;
ALTER TABLE IF EXISTS commitments RENAME COLUMN parent_commitment_id TO parent_schedule_id;

-- 2. Rename the table
ALTER TABLE IF EXISTS commitments RENAME TO schedules;

-- 3. Drop old indexes and recreate with new names
DROP INDEX IF EXISTS idx_commitments_user_id;
DROP INDEX IF EXISTS idx_commitments_task_id;
DROP INDEX IF EXISTS idx_commitments_lookup;
DROP INDEX IF EXISTS idx_commitments_parent_id;
DROP INDEX IF EXISTS idx_commitments_scheduled_time;

CREATE INDEX IF NOT EXISTS idx_schedules_user_id ON schedules(user_id);
CREATE INDEX IF NOT EXISTS idx_schedules_task_id ON schedules(task_id);
CREATE INDEX IF NOT EXISTS idx_schedules_lookup ON schedules(user_id, timeframe, schedule_date, section, sort_order);
CREATE INDEX IF NOT EXISTS idx_schedules_parent_id ON schedules(parent_schedule_id);
CREATE INDEX IF NOT EXISTS idx_schedules_scheduled_time ON schedules(user_id, scheduled_time) WHERE scheduled_time IS NOT NULL;

-- 4. Drop old RLS policies and recreate with new names
DROP POLICY IF EXISTS "Users can view their own commitments" ON schedules;
DROP POLICY IF EXISTS "Users can insert their own commitments" ON schedules;
DROP POLICY IF EXISTS "Users can update their own commitments" ON schedules;
DROP POLICY IF EXISTS "Users can delete their own commitments" ON schedules;

CREATE POLICY "Users can view their own schedules" ON schedules FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own schedules" ON schedules FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own schedules" ON schedules FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own schedules" ON schedules FOR DELETE USING (auth.uid() = user_id);

-- 5. Rename constraints
ALTER TABLE schedules DROP CONSTRAINT IF EXISTS commitments_section_check;
ALTER TABLE schedules ADD CONSTRAINT schedules_section_check CHECK (section IN ('target', 'todo'));

-- ==============================================
-- PIN TO HOME SUPPORT
-- Pinned projects/lists appear on the Home page.
-- ==============================================

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- ==============================================
-- SYSTEM CATEGORY SUPPORT (SOMEDAY)
-- System categories are auto-created per user
-- and cannot be deleted or renamed.
-- ==============================================

ALTER TABLE categories ADD COLUMN IF NOT EXISTS is_system BOOLEAN DEFAULT false;

-- ==============================================
-- GOAL SUPPORT
-- Goals are FocusTask entries with type = 'goal'.
-- Also adds due_date for deadline tracking (any task type).
-- ==============================================

-- 1. Update type CHECK to include 'goal'
DO $$
DECLARE
  cname TEXT;
BEGIN
  SELECT conname INTO cname
  FROM pg_constraint
  WHERE conrelid = 'tasks'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%type%';
  IF cname IS NOT NULL THEN
    EXECUTE 'ALTER TABLE tasks DROP CONSTRAINT ' || cname;
  END IF;
END$$;

ALTER TABLE tasks ADD CONSTRAINT tasks_type_check CHECK (type IN ('task', 'project', 'list', 'goal'));

-- 2. Add due_date column (nullable, usable by any task type)
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS due_date TIMESTAMPTZ;

-- 3. Index for goal lookups
CREATE INDEX IF NOT EXISTS idx_tasks_goals ON tasks(user_id, type) WHERE type = 'goal';

-- 4. Index for due date queries
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date) WHERE due_date IS NOT NULL;

-- ==============================================
-- NOTIFICATION SUPPORT
-- Local notification scheduling for tasks
-- ==============================================

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS notification_enabled BOOLEAN DEFAULT false;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS notification_date TIMESTAMPTZ;

-- ==============================================
-- SHARING SUPPORT
-- Link-based sharing of projects, lists, and goals
-- ==============================================

-- 1. Shares table
CREATE TABLE IF NOT EXISTS task_shares (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  task_id UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
  owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  shared_with_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  share_token TEXT UNIQUE,
  created_date TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_shares_task_id ON task_shares(task_id);
CREATE INDEX IF NOT EXISTS idx_task_shares_owner ON task_shares(owner_id);
CREATE INDEX IF NOT EXISTS idx_task_shares_recipient ON task_shares(shared_with_user_id);
CREATE INDEX IF NOT EXISTS idx_task_shares_token ON task_shares(share_token) WHERE share_token IS NOT NULL;

ALTER TABLE task_shares ENABLE ROW LEVEL SECURITY;

-- 2. Helper function: returns task IDs accessible via sharing
CREATE OR REPLACE FUNCTION shared_task_ids_for_user(uid UUID)
RETURNS SETOF UUID AS $$
  SELECT DISTINCT task_id FROM task_shares
  WHERE shared_with_user_id = uid
     OR (owner_id = uid AND shared_with_user_id IS NOT NULL)
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 3. RLS on task_shares
CREATE POLICY "Users can view their shares" ON task_shares FOR SELECT
  USING (owner_id = auth.uid() OR shared_with_user_id = auth.uid());

CREATE POLICY "Users can create shares" ON task_shares FOR INSERT
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Users can delete their shares" ON task_shares FOR DELETE
  USING (owner_id = auth.uid() OR shared_with_user_id = auth.uid());

-- 4. Updated RLS on tasks (replace existing policies)
DROP POLICY IF EXISTS "Users can view their own tasks" ON tasks;
CREATE POLICY "Users can view accessible tasks" ON tasks FOR SELECT
  USING (
    user_id = auth.uid()
    OR id IN (SELECT shared_task_ids_for_user(auth.uid()))
    OR project_id IN (SELECT shared_task_ids_for_user(auth.uid()))
    OR parent_task_id IN (SELECT shared_task_ids_for_user(auth.uid()))
  );

DROP POLICY IF EXISTS "Users can insert their own tasks" ON tasks;
CREATE POLICY "Users can insert accessible tasks" ON tasks FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own tasks" ON tasks;
CREATE POLICY "Users can update accessible tasks" ON tasks FOR UPDATE
  USING (
    user_id = auth.uid()
    OR project_id IN (SELECT shared_task_ids_for_user(auth.uid()))
    OR parent_task_id IN (SELECT shared_task_ids_for_user(auth.uid()))
  );

DROP POLICY IF EXISTS "Users can delete their own tasks" ON tasks;
CREATE POLICY "Users can delete accessible tasks" ON tasks FOR DELETE
  USING (
    user_id = auth.uid()
    OR project_id IN (SELECT shared_task_ids_for_user(auth.uid()))
    OR parent_task_id IN (SELECT shared_task_ids_for_user(auth.uid()))
  );

-- 5. Updated RLS on schedules (for shared task schedules)
DROP POLICY IF EXISTS "Users can view their own schedules" ON schedules;
DROP POLICY IF EXISTS "Users can view accessible schedules" ON schedules;
CREATE POLICY "Users can view accessible schedules" ON schedules FOR SELECT
  USING (
    user_id = auth.uid()
    OR task_id IN (SELECT shared_task_ids_for_user(auth.uid()))
    OR task_id IN (SELECT id FROM tasks WHERE project_id IN (SELECT shared_task_ids_for_user(auth.uid())) OR parent_task_id IN (SELECT shared_task_ids_for_user(auth.uid())))
  );

DROP POLICY IF EXISTS "Users can insert their own schedules" ON schedules;
DROP POLICY IF EXISTS "Users can insert accessible schedules" ON schedules;
CREATE POLICY "Users can insert accessible schedules" ON schedules FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own schedules" ON schedules;
DROP POLICY IF EXISTS "Users can update accessible schedules" ON schedules;
CREATE POLICY "Users can update accessible schedules" ON schedules FOR UPDATE
  USING (
    user_id = auth.uid()
    OR task_id IN (SELECT shared_task_ids_for_user(auth.uid()))
    OR task_id IN (SELECT id FROM tasks WHERE project_id IN (SELECT shared_task_ids_for_user(auth.uid())))
  );

DROP POLICY IF EXISTS "Users can delete their own schedules" ON schedules;
DROP POLICY IF EXISTS "Users can delete accessible schedules" ON schedules;
CREATE POLICY "Users can delete accessible schedules" ON schedules FOR DELETE
  USING (
    user_id = auth.uid()
    OR task_id IN (SELECT shared_task_ids_for_user(auth.uid()))
    OR task_id IN (SELECT id FROM tasks WHERE project_id IN (SELECT shared_task_ids_for_user(auth.uid())))
  );

-- 6. Accept share RPC
CREATE OR REPLACE FUNCTION accept_share(p_token TEXT)
RETURNS UUID AS $$
DECLARE
  v_task_id UUID;
  v_owner_id UUID;
BEGIN
  SELECT task_id, owner_id INTO v_task_id, v_owner_id
  FROM task_shares WHERE share_token = p_token LIMIT 1;

  IF v_task_id IS NULL THEN
    RAISE EXCEPTION 'Invalid share link';
  END IF;

  IF v_owner_id = auth.uid() THEN
    RETURN v_task_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM task_shares WHERE task_id = v_task_id AND shared_with_user_id = auth.uid()) THEN
    INSERT INTO task_shares (task_id, owner_id, shared_with_user_id)
    VALUES (v_task_id, v_owner_id, auth.uid());
  END IF;

  RETURN v_task_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
