import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase CRUD for verse highlights.
///
/// Table schema (run in Supabase SQL editor):
/// ```sql
/// CREATE TABLE IF NOT EXISTS public.highlights (
///   id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
///   user_id     UUID        REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
///   book        TEXT        NOT NULL,
///   chapter     INTEGER     NOT NULL,
///   verse       INTEGER     NOT NULL,
///   color       TEXT        NOT NULL DEFAULT 'amber',
///   created_at  TIMESTAMPTZ DEFAULT NOW(),
///   UNIQUE (user_id, book, chapter, verse)
/// );
/// ALTER TABLE public.highlights ENABLE ROW LEVEL SECURITY;
/// CREATE POLICY "Users manage own highlights"
///   ON public.highlights FOR ALL
///   USING  (auth.uid() = user_id)
///   WITH CHECK (auth.uid() = user_id);
/// ```
/// One saved verse highlight, as shown in the "My Highlights" list —
/// unlike [HighlightsService.fetchHighlights] (scoped to one chapter, for
/// rendering tinted verses while reading), this carries everything needed
/// to display and re-navigate to a highlight without a second lookup.
class SavedHighlight {
  final String book;
  final int chapter;
  final int verse;
  final String color;
  final DateTime createdAt;

  const SavedHighlight({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.color,
    required this.createdAt,
  });

  factory SavedHighlight.fromRow(Map<String, dynamic> row) {
    return SavedHighlight(
      book: row['book'] as String,
      chapter: row['chapter'] as int,
      verse: row['verse'] as int,
      color: row['color'] as String? ?? 'amber',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  String get reference => '$book $chapter:$verse';
}

class HighlightsService {
  final _client = Supabase.instance.client;

  /// All of a user's highlighted verses, newest first — powers the
  /// "My Highlights" screen. This was never built even though the table
  /// and per-chapter fetch already existed.
  Future<List<SavedHighlight>> fetchAllHighlights({
    required String userId,
  }) async {
    final rows = await _client
        .from('highlights')
        .select('book, chapter, verse, color, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => SavedHighlight.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns a map of verseNumber → colorKey for the given chapter.
  Future<Map<int, String>> fetchHighlights({
    required String userId,
    required String book,
    required int chapter,
  }) async {
    final rows = await _client
        .from('highlights')
        .select('verse, color')
        .eq('user_id', userId)
        .eq('book', book)
        .eq('chapter', chapter);
    final map = <int, String>{};
    for (final row in rows as List) {
      map[row['verse'] as int] = row['color'] as String;
    }
    return map;
  }

  /// Insert or update a single verse highlight.
  Future<void> upsertHighlight({
    required String userId,
    required String book,
    required int chapter,
    required int verse,
    required String color,
  }) async {
    await _client.from('highlights').upsert(
      {
        'user_id': userId,
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'color': color,
      },
      onConflict: 'user_id,book,chapter,verse',
    );
  }

  /// Delete a single verse highlight.
  Future<void> removeHighlight({
    required String userId,
    required String book,
    required int chapter,
    required int verse,
  }) async {
    await _client
        .from('highlights')
        .delete()
        .eq('user_id', userId)
        .eq('book', book)
        .eq('chapter', chapter)
        .eq('verse', verse);
  }
}

final highlightsService = HighlightsService();
