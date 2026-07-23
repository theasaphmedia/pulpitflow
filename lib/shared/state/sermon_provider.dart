import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/sermon_storage.dart';
import '../../data/models/sermon_model.dart';
import '../../data/services/sermon_sync_service.dart';
import 'auth_provider.dart';

const _kMigratedPrefix = 'pf_cloud_migrated_';

class SermonNotifier extends AsyncNotifier<List<Sermon>> {
  @override
  Future<List<Sermon>> build() async {
    // Re-run whenever the signed-in user changes (sign-in / sign-out).
    final user = ref.watch(currentUserProvider);

    // 1. Load from local storage immediately — no network, no spinner.
    final localSermons = await sermonStorage.loadSermons();

    // 2. No user → stay local only.
    if (user == null) return localSermons;

    // 3. Try cloud sync.
    try {
      final cloudSermons = await sermonSyncService.fetchSermons(user.id);
      final prefs = await SharedPreferences.getInstance();
      final migratedKey = '$_kMigratedPrefix${user.id}';
      final alreadyMigrated = prefs.getBool(migratedKey) ?? false;

      // Only treat "cloud empty" as "first-time connection" once per user —
      // otherwise a user who deletes every sermon (from this or another
      // device) gets them silently resurrected from the stale local cache
      // on every subsequent launch.
      if (cloudSermons.isEmpty && localSermons.isNotEmpty && !alreadyMigrated) {
        if (kDebugMode) {
          debugPrint(
            'SermonNotifier: migrating ${localSermons.length} local sermon(s) to cloud',
          );
        }
        for (final s in localSermons) {
          await sermonSyncService.upsertSermon(s, user.id);
        }
        await prefs.setBool(migratedKey, true);
        // No local write needed here — localSermons came straight from
        // sermonStorage.loadSermons() above, so it's already what's on
        // disk. Writing it back would just be a no-op full rewrite.
        return localSermons;
      }

      await prefs.setBool(migratedKey, true);

      // Cloud has data (or is intentionally empty) → cloud is source of
      // truth; refresh local cache.
      await sermonStorage.saveSermons(cloudSermons);
      return cloudSermons;
    } catch (e, st) {
      // Network error, RLS rejection, etc. → fall back to local silently.
      if (kDebugMode) {
        debugPrint('SermonNotifier: cloud sync failed — using local\n$e\n$st');
      }
      return localSermons;
    }
  }

  // ── Mutations ─────────────────────────────────────────────────────────────
  // Pattern: update state + local cache immediately, then fire background
  // Supabase upsert so the UI never waits on the network.

  Future<Sermon> addSermon(
    String title,
    String translation, {
    String? series,
    List<SermonBlock>? blocks,
  }) async {
    final trimmedSeries =
        (series?.trim().isEmpty ?? true) ? null : series!.trim();
    final sermon = Sermon(
      title: title,
      defaultTranslation: translation,
      series: trimmedSeries,
      blocks: blocks,
    );
    final updated = <Sermon>[sermon, ...state.value ?? <Sermon>[]];
    state = AsyncData(updated);
    // O(1): writes just this one record instead of re-serializing the
    // whole library on every save.
    await sermonStorage.saveSermon(sermon);
    _bgUpsert(sermon);
    return sermon;
  }

  Future<void> updateSermon(Sermon sermon) async {
    final updated = (state.value ?? <Sermon>[])
        .map<Sermon>((s) => s.id == sermon.id ? sermon : s)
        .toList();
    state = AsyncData(updated);
    await sermonStorage.saveSermon(sermon);
    _bgUpsert(sermon);
  }

  Future<void> deleteSermon(String id) async {
    final updated = (state.value ?? <Sermon>[])
        .where((s) => s.id != id)
        .toList();
    state = AsyncData(updated);
    await sermonStorage.deleteSermonById(id);
    _bgDelete(id);
  }

  Future<void> duplicateSermon(Sermon original) async {
    final duplicate = Sermon(
      title: '${original.title} (Copy)',
      blocks: original.blocks
          .map(
            (b) => SermonBlock(
              type: b.type,
              content: b.content,
              scriptureRef: b.scriptureRef,
              translation: b.translation,
            ),
          )
          .toList(),
      defaultTranslation: original.defaultTranslation,
      series: original.series,
      tags: List<String>.from(original.tags),
    );
    final updated = <Sermon>[duplicate, ...state.value ?? <Sermon>[]];
    state = AsyncData(updated);
    await sermonStorage.saveSermon(duplicate);
    _bgUpsert(duplicate);
  }

  /// Merges [incoming] sermons into the library, skipping any whose id
  /// already exists. Returns the count of actually-added sermons.
  Future<int> importSermons(List<Sermon> incoming) async {
    final existing = state.value ?? <Sermon>[];
    final existingIds = existing.map((s) => s.id).toSet();
    final toAdd = incoming.where((s) => !existingIds.contains(s.id)).toList();
    if (toAdd.isEmpty) return 0;
    final updated = <Sermon>[...toAdd, ...existing];
    state = AsyncData(updated);
    // Only write the new records — existing ones are untouched on disk.
    for (final s in toAdd) {
      await sermonStorage.saveSermon(s);
      _bgUpsert(s);
    }
    return toAdd.length;
  }

  Sermon? getSermonById(String id) {
    final sermons = state.value;
    if (sermons == null) return null;
    for (final s in sermons) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ── Background Supabase helpers ───────────────────────────────────────────

  void _bgUpsert(Sermon sermon) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    sermonSyncService.upsertSermon(sermon, user.id).catchError((Object e) {
      if (kDebugMode) debugPrint('SermonNotifier._bgUpsert failed: $e');
    });
  }

  void _bgDelete(String id) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    sermonSyncService.deleteSermon(id).catchError((Object e) {
      if (kDebugMode) debugPrint('SermonNotifier._bgDelete failed: $e');
    });
  }

  /// Re-runs the full build() logic (local load + cloud sync).
  /// Safe to call from pull-to-refresh.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final sermonProvider = AsyncNotifierProvider<SermonNotifier, List<Sermon>>(
  SermonNotifier.new,
);

/// Derives a single sermon by id from the main provider — no extra fetch.
final singleSermonProvider = Provider.family<Sermon?, String>((ref, id) {
  final sermons = ref.watch(sermonProvider).value;
  if (sermons == null) return null;
  try {
    return sermons.firstWhere((s) => s.id == id);
  } catch (_) {
    return null;
  }
});
