import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sermon_model.dart';

/// Sermon persistence, backed by Hive instead of a single SharedPreferences
/// string blob.
///
/// The previous implementation serialized the ENTIRE sermon list to one
/// JSON string on every single save — including the autosave that fires on
/// every keystroke in the editor. At a handful of sermons that's invisible;
/// at a few hundred it means every keystroke rewrites hundreds of records
/// to disk. Hive stores one record per sermon (keyed by id), so a single
/// edit is an O(1) write instead of an O(n) rewrite of the whole library.
///
/// A corrupt/undecodable individual record is now also skipped rather than
/// nuking the entire library back to the bundled demo sermons, which is
/// what the old single-blob-decode-failure path did.
class SermonStorage {
  static const String _boxName = 'pf_sermons_v1';

  // Legacy key from before this migrated off SharedPreferences — read once,
  // on first launch after the update, to carry existing local sermons over.
  static const String _legacyKey = 'pulpitflow_sermons';

  Box<String>? _box;

  Future<Box<String>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<String>(_boxName);
    _box = box;
    return box;
  }

  /// Load all sermons. On a genuinely fresh install (no Hive data and no
  /// legacy SharedPreferences data), seeds the bundled demo sermons.
  Future<List<Sermon>> loadSermons() async {
    final box = await _openBox();

    if (box.isEmpty) {
      final migrated = await _migrateFromLegacyStorage(box);
      if (migrated != null) return migrated;
      return _defaultSermons();
    }

    final sermons = <Sermon>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        sermons.add(Sermon.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Skip just this one corrupt record — don't discard the rest of
        // the pastor's sermon library over a single bad entry.
      }
    }
    return sermons;
  }

  /// One-time carry-over from the old single-blob SharedPreferences store.
  /// Returns the migrated list, or null if there was nothing to migrate
  /// (i.e. this really is a first run).
  Future<List<Sermon>?> _migrateFromLegacyStorage(Box<String> box) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw == null) return null;

      final List<dynamic> json = jsonDecode(raw);
      final sermons = <Sermon>[];
      for (final j in json) {
        try {
          sermons.add(Sermon.fromJson(j as Map<String, dynamic>));
        } catch (_) {
          // Skip a corrupt legacy record rather than aborting the migration.
        }
      }
      if (sermons.isEmpty) return null;

      for (final s in sermons) {
        await box.put(s.id, jsonEncode(s.toJson()));
      }
      return sermons;
    } catch (_) {
      return null;
    }
  }

  /// Bulk reconcile — writes every given sermon and removes any stored
  /// record not present in [sermons]. Used for the cases where the source
  /// of truth is being replaced wholesale (cloud sync down to local),
  /// where deletions made elsewhere need to propagate.
  Future<void> saveSermons(List<Sermon> sermons) async {
    final box = await _openBox();
    final incomingIds = sermons.map((s) => s.id).toSet();
    final staleKeys = box.keys.where((k) => !incomingIds.contains(k)).toList();
    for (final key in staleKeys) {
      await box.delete(key);
    }
    for (final s in sermons) {
      await box.put(s.id, jsonEncode(s.toJson()));
    }
  }

  /// Write a single sermon — O(1), does not touch any other record.
  Future<void> saveSermon(Sermon sermon) async {
    final box = await _openBox();
    await box.put(sermon.id, jsonEncode(sermon.toJson()));
  }

  /// Delete a single sermon by id — O(1).
  Future<void> deleteSermonById(String id) async {
    final box = await _openBox();
    await box.delete(id);
  }

  // Default demo sermons
  List<Sermon> _defaultSermons() {
    return [
      Sermon(
        title: 'Justified By Faith',
        defaultTranslation: 'KJV',
        blocks: [
          SermonBlock.text(
            'Today we explore what it means to be justified by faith. The Apostle Paul writes clearly in ',
          ),
          SermonBlock.scripture('Romans 5:1'),
          SermonBlock.text(
            ' that having been justified by faith, we have peace with God. This peace is not circumstantial — it is positional. ',
          ),
          SermonBlock.text(
            '\n\nWhen we understand grace, we understand that God\'s acceptance of us is not based on our performance. As Paul also writes in ',
          ),
          SermonBlock.scripture('Ephesians 2:8-9'),
          SermonBlock.text(
            ' — salvation is entirely the gift of God, not of works.\n\nThis truth should transform how we live. Because we are justified, we can approach God boldly. Because we have peace, we do not need to strive for acceptance.',
          ),
          SermonBlock.text('\n\nThe psalmist declared in '),
          SermonBlock.scripture('Psalm 23:1-6'),
          SermonBlock.text(
            ' that the LORD is our shepherd. A shepherd provides, protects, and guides. This is the God we serve — not a harsh judge, but a loving shepherd.',
          ),
        ],
      ),
      Sermon(
        title: 'The Power of Hope',
        defaultTranslation: 'NIV',
        blocks: [
          SermonBlock.text(
            'Hope is not wishful thinking. Biblical hope is a confident expectation of what God has promised. The prophet Isaiah declared in ',
          ),
          SermonBlock.scripture('Isaiah 40:31'),
          SermonBlock.text(
            ' that those who hope in the LORD shall renew their strength.\n\nGod\'s plans for us are established. He declared through Jeremiah in ',
          ),
          SermonBlock.scripture('Jeremiah 29:11'),
          SermonBlock.text(
            ' that His thoughts toward us are of peace and not evil.\n\nAnd the writer of Hebrews defines faith and hope together in ',
          ),
          SermonBlock.scripture('Hebrews 11:1'),
          SermonBlock.text(
            ' — faith is the substance of things hoped for. Hope and faith are inseparable in the life of a believer.',
          ),
        ],
      ),
      Sermon(
        title: 'God So Loved',
        defaultTranslation: 'ESV',
        blocks: [
          SermonBlock.text(
            'The most famous verse in all of scripture begins with four words that contain the entire gospel: ',
          ),
          SermonBlock.scripture('John 3:16-17'),
          SermonBlock.text(
            '\n\nGod LOVED. This is not past tense — it is the eternal disposition of God toward humanity. He gave His Son not to condemn but to save.\n\nThis love is the foundation of our faith. And it calls us to trust in ',
          ),
          SermonBlock.scripture('Proverbs 3:5-6'),
          SermonBlock.text(
            ' — to acknowledge Him in all our ways.\n\nThe result? He shall direct our paths. The same God who loved the world enough to give His Son will direct every step of your life.',
          ),
        ],
      ),
    ];
  }
}

final sermonStorage = SermonStorage();
