-- Highlights table was missing the UNIQUE(user_id, book, chapter, verse)
-- constraint that highlights_service.dart's upsertHighlight() relies on via
-- onConflict: 'user_id,book,chapter,verse'. Without it, every upsert failed
-- with Postgres 42P10 ("no unique or exclusion constraint matching the
-- ON CONFLICT specification"), which the app's generic catch-all surfaced as
-- "Could not save highlight — check your connection" — masking the real
-- cause. Zero highlights had ever been saved successfully as a result.
-- Applied directly to the live project on 2026-07-23; mirrored here so it
-- isn't lost on the next `supabase db push --linked`.

ALTER TABLE public.highlights
  ADD CONSTRAINT highlights_user_book_chapter_verse_key
  UNIQUE (user_id, book, chapter, verse);
