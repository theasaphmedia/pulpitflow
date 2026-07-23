// Pure-Dart tests for Sermon/SermonBlock — no Flutter bindings or Supabase
// init required, so these run fast and can't be broken by unrelated app
// bootstrapping. Covers the exact logic that's been touched by recent
// fixes (copyWith's null-vs-omitted sentinel, JSON round trips) so a
// future refactor can't silently reintroduce the same bugs.

import 'package:flutter_test/flutter_test.dart';
import 'package:pulpitflow/data/models/sermon_model.dart';

void main() {
  group('SermonBlock JSON round trip', () {
    test('text block preserves content and id', () {
      final block = SermonBlock.text('In the beginning...');
      final decoded = SermonBlock.fromJson(block.toJson());

      expect(decoded.id, block.id);
      expect(decoded.type, BlockType.text);
      expect(decoded.content, 'In the beginning...');
      expect(decoded.scriptureRef, isNull);
      expect(decoded.note, isNull);
    });

    test('scripture block preserves ref and translation', () {
      final block = SermonBlock.scripture('John 3:16', translation: 'ESV');
      final decoded = SermonBlock.fromJson(block.toJson());

      expect(decoded.type, BlockType.scripture);
      expect(decoded.scriptureRef, 'John 3:16');
      expect(decoded.translation, 'ESV');
    });

    test('note round-trips when present, omitted key when absent', () {
      final withNote = SermonBlock.text('x').copyWith(note: 'ask the board');
      expect(withNote.toJson()['note'], 'ask the board');
      expect(SermonBlock.fromJson(withNote.toJson()).note, 'ask the board');

      final withoutNote = SermonBlock.text('x');
      expect(withoutNote.toJson().containsKey('note'), isFalse);
    });

    test('copyWith with explicit null note clears it; omitted keeps it', () {
      final block = SermonBlock.text('x').copyWith(note: 'keep me');
      final cleared = block.copyWith(note: null);
      final untouched = block.copyWith(content: 'y');

      expect(cleared.note, isNull);
      expect(untouched.note, 'keep me');
    });
  });

  group('Sermon JSON round trip (local storage format)', () {
    test('preserves all fields including optional ones', () {
      final sermon = Sermon(
        title: 'Grace Abounds',
        defaultTranslation: 'NIV',
        series: 'Romans',
        tags: ['grace', 'faith'],
        notes: 'went long on point 2',
        scheduledDate: DateTime.utc(2026, 8, 2),
        blocks: [
          SermonBlock.text('Opening thought.'),
          SermonBlock.scripture('Romans 5:1'),
        ],
      );

      final decoded = Sermon.fromJson(sermon.toJson());

      expect(decoded.id, sermon.id);
      expect(decoded.title, 'Grace Abounds');
      expect(decoded.defaultTranslation, 'NIV');
      expect(decoded.series, 'Romans');
      expect(decoded.tags, ['grace', 'faith']);
      expect(decoded.notes, 'went long on point 2');
      expect(decoded.scheduledDate, DateTime.utc(2026, 8, 2));
      expect(decoded.blocks.length, 2);
      expect(decoded.blocks[1].scriptureRef, 'Romans 5:1');
    });

    test('defaults series/notes/scheduledDate to null when absent', () {
      final sermon = Sermon(title: 'Bare Minimum');
      final decoded = Sermon.fromJson(sermon.toJson());

      expect(decoded.series, isNull);
      expect(decoded.notes, isNull);
      expect(decoded.scheduledDate, isNull);
    });
  });

  group('Sermon <-> Supabase row mapping', () {
    test('toSupabase/fromSupabase round trip preserves data', () {
      final sermon = Sermon(
        title: 'Held By Grace',
        series: 'Grace Series',
        status: SermonStatus.ready,
        blocks: [SermonBlock.text('body text')],
      );
      final userId = 'user-123';

      final row = sermon.toSupabase(userId);
      expect(row['user_id'], userId);
      expect(row['default_translation'], sermon.defaultTranslation);

      final decoded = Sermon.fromSupabase(row);
      expect(decoded.id, sermon.id);
      expect(decoded.title, 'Held By Grace');
      expect(decoded.series, 'Grace Series');
      expect(decoded.status, SermonStatus.ready);
      expect(decoded.blocks.single.content, 'body text');
    });

    test('fromSupabase tolerates missing optional columns', () {
      final now = DateTime.now().toIso8601String();
      final row = {
        'id': 'abc',
        'title': 'Minimal Row',
        'blocks': [],
        'created_at': now,
        'updated_at': now,
      };

      final sermon = Sermon.fromSupabase(row);
      expect(sermon.title, 'Minimal Row');
      expect(sermon.defaultTranslation, 'KJV');
      expect(sermon.status, SermonStatus.draft);
      expect(sermon.series, isNull);
      expect(sermon.scheduledDate, isNull);
    });
  });

  group('Sermon.copyWith null-vs-omitted sentinel', () {
    test('omitting series/notes/scheduledDate keeps existing values', () {
      final original = Sermon(
        title: 'Original',
        series: 'Keep Me',
        notes: 'keep this too',
        scheduledDate: DateTime.utc(2026, 9, 1),
      );

      final updated = original.copyWith(title: 'Renamed');

      expect(updated.series, 'Keep Me');
      expect(updated.notes, 'keep this too');
      expect(updated.scheduledDate, DateTime.utc(2026, 9, 1));
    });

    test('explicit null clears series/notes/scheduledDate', () {
      final original = Sermon(
        title: 'Original',
        series: 'Clear Me',
        notes: 'clear this too',
        scheduledDate: DateTime.utc(2026, 9, 1),
      );

      final cleared = original.copyWith(
        series: null,
        notes: null,
        scheduledDate: null,
      );

      expect(cleared.series, isNull);
      expect(cleared.notes, isNull);
      expect(cleared.scheduledDate, isNull);
    });

    test('id, createdAt never change; updatedAt always bumps', () async {
      final original = Sermon(title: 'Original');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final updated = original.copyWith(title: 'Changed');

      expect(updated.id, original.id);
      expect(updated.createdAt, original.createdAt);
      expect(updated.updatedAt.isAfter(original.updatedAt), isTrue);
    });
  });

  group('Sermon derived getters', () {
    test('wordCount counts only text blocks, ignores whitespace-only', () {
      final sermon = Sermon(
        title: 'Word Count Test',
        blocks: [
          SermonBlock.text('one two three'),
          SermonBlock.scripture('John 3:16'), // not counted
          SermonBlock.text('   '), // whitespace-only, not counted
          SermonBlock.text('four'),
        ],
      );

      expect(sermon.wordCount, 4);
    });

    test('speakingTimeLabel is empty under 50 words', () {
      final sermon = Sermon(
        title: 'Short',
        blocks: [SermonBlock.text('just a few words here')],
      );
      expect(sermon.speakingTimeLabel, '');
    });

    test('scriptureCount and scriptureRefs only include scripture blocks', () {
      final sermon = Sermon(
        title: 'Refs',
        blocks: [
          SermonBlock.text('intro'),
          SermonBlock.scripture('Romans 5:1'),
          SermonBlock.scripture('Ephesians 2:8-9'),
        ],
      );
      expect(sermon.scriptureCount, 2);
      expect(sermon.scriptureRefs, ['Romans 5:1', 'Ephesians 2:8-9']);
    });
  });
}
