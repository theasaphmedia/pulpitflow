-- ── sermons table RLS ─────────────────────────────────────────────────────────
-- Ensure the table exists with a user_id column before enabling RLS.
-- (If the table was created manually in the dashboard, this won't conflict.)

ALTER TABLE public.sermons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own sermons"   ON public.sermons;
DROP POLICY IF EXISTS "Users can insert own sermons" ON public.sermons;
DROP POLICY IF EXISTS "Users can update own sermons" ON public.sermons;
DROP POLICY IF EXISTS "Users can delete own sermons" ON public.sermons;

CREATE POLICY "Users can view own sermons"
  ON public.sermons FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own sermons"
  ON public.sermons FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sermons"
  ON public.sermons FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own sermons"
  ON public.sermons FOR DELETE
  USING (auth.uid() = user_id);


-- ── highlights table RLS ───────────────────────────────────────────────────────

ALTER TABLE public.highlights ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own highlights"   ON public.highlights;
DROP POLICY IF EXISTS "Users can insert own highlights" ON public.highlights;
DROP POLICY IF EXISTS "Users can update own highlights" ON public.highlights;
DROP POLICY IF EXISTS "Users can delete own highlights" ON public.highlights;

CREATE POLICY "Users can view own highlights"
  ON public.highlights FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own highlights"
  ON public.highlights FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own highlights"
  ON public.highlights FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own highlights"
  ON public.highlights FOR DELETE
  USING (auth.uid() = user_id);
