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
-- COMMITMENTS TABLE
-- Task commitments to timeframes (Daily/Weekly/Monthly/Yearly)
-- ==============================================

CREATE TABLE IF NOT EXISTS commitments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  task_id UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
  timeframe TEXT NOT NULL CHECK (timeframe IN ('daily', 'weekly', 'monthly', 'yearly')),
  section TEXT NOT NULL CHECK (section IN ('target', 'todo')),
  commitment_date TIMESTAMPTZ NOT NULL,
  sort_order INTEGER DEFAULT 0,
  created_date TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for commitments - optimized for frequent queries
CREATE INDEX IF NOT EXISTS idx_commitments_user_id ON commitments(user_id);
CREATE INDEX IF NOT EXISTS idx_commitments_task_id ON commitments(task_id);
CREATE INDEX IF NOT EXISTS idx_commitments_lookup ON commitments(user_id, timeframe, commitment_date, section, sort_order);

-- Enable Row Level Security
ALTER TABLE commitments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for commitments
DROP POLICY IF EXISTS "Users can view their own commitments" ON commitments;
CREATE POLICY "Users can view their own commitments"
  ON commitments FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own commitments" ON commitments;
CREATE POLICY "Users can insert their own commitments"
  ON commitments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own commitments" ON commitments;
CREATE POLICY "Users can update their own commitments"
  ON commitments FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own commitments" ON commitments;
CREATE POLICY "Users can delete their own commitments"
  ON commitments FOR DELETE
  USING (auth.uid() = user_id);

-- ==============================================
-- TRICKLE-DOWN COMMITMENT SUPPORT
-- Parent-child relationship for breaking down commitments
-- ==============================================

-- Add parent_commitment_id column for hierarchical commitments
-- This enables Year → Month → Week → Day breakdown
ALTER TABLE commitments
ADD COLUMN IF NOT EXISTS parent_commitment_id UUID REFERENCES commitments(id) ON DELETE CASCADE;

-- Index for efficient parent-child lookups
CREATE INDEX IF NOT EXISTS idx_commitments_parent_id ON commitments(parent_commitment_id);

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
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS scheduled_time TIMESTAMPTZ;
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS duration_minutes INTEGER DEFAULT 30;

-- Index for efficient timeline queries (fetching timed commitments for a day)
CREATE INDEX IF NOT EXISTS idx_commitments_scheduled_time
ON commitments(user_id, scheduled_time)
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
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('tasks', 'categories', 'commitments');

-- Check that RLS is enabled
-- SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('tasks', 'categories', 'commitments');

-- Check policies
-- SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('tasks', 'categories', 'commitments');

-- Check parent_commitment_id column exists
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'commitments' AND column_name = 'parent_commitment_id';

-- ==============================================
-- SECTION VALUE RENAME
-- Rename section values from 'focus'/'extra' to 'target'/'todo'
-- Run AFTER deploying the updated app code
-- ==============================================

-- Update check constraint to allow new values (drop old, add new)
ALTER TABLE commitments DROP CONSTRAINT IF EXISTS commitments_section_check;
ALTER TABLE commitments ADD CONSTRAINT commitments_section_check CHECK (section IN ('target', 'todo'));

-- Migrate existing data
UPDATE commitments SET section = 'target' WHERE section = 'focus';
UPDATE commitments SET section = 'todo'   WHERE section = 'extra';
