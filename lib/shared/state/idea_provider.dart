import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/idea_model.dart';
import 'auth_provider.dart';

// Legacy global key from before ideas were scoped per-user.
const _kLegacyIdeasKey = 'sermon_ideas_v1';

class IdeaNotifier extends Notifier<List<SermonIdea>> {
  String? _userId;

  /// Guards mutators against the load race: without this, an idea added
  /// while `_load()` is still resolving from disk got silently wiped out
  /// the moment `_load()` finished and clobbered `state` with the stale
  /// (pre-add) saved list.
  Future<void>? _loadFuture;

  @override
  List<SermonIdea> build() {
    // Re-run whenever the signed-in user changes, so ideas are scoped per
    // account instead of a single global key shared by every user on the
    // device (previously idea A's ideas would show up for user B on a
    // shared/reused device after switching accounts).
    final user = ref.watch(currentUserProvider);
    _userId = user?.id;
    _loadFuture = _load();
    return [];
  }

  String get _key =>
      _userId == null ? _kLegacyIdeasKey : '${_kLegacyIdeasKey}_$_userId';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_key);

    // One-time migration: a signed-in user who already had ideas saved
    // under the old global key (pre-account-scoping) shouldn't see them
    // vanish — copy them into the new per-user key the first time we see
    // an empty scoped list but data under the legacy key.
    if (raw == null && _userId != null) {
      final legacy = prefs.getString(_kLegacyIdeasKey);
      if (legacy != null) {
        await prefs.setString(_key, legacy);
        raw = legacy;
      }
    }

    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => SermonIdea.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(state.map((i) => i.toJson()).toList()),
    );
  }

  Future<void> _ensureLoaded() async {
    final future = _loadFuture;
    if (future != null) await future;
  }

  Future<void> addIdea(String content, IdeaTag tag) async {
    await _ensureLoaded();
    final idea = SermonIdea(content: content, tag: tag);
    state = [idea, ...state];
    await _persist();
  }

  Future<void> updateIdea(SermonIdea updated) async {
    await _ensureLoaded();
    state = [
      for (final i in state)
        if (i.id == updated.id) updated else i,
    ];
    await _persist();
  }

  Future<void> togglePin(String id) async {
    await _ensureLoaded();
    state = [
      for (final i in state)
        if (i.id == id) i.copyWith(isPinned: !i.isPinned) else i,
    ];
    await _persist();
  }

  Future<void> deleteIdea(String id) async {
    await _ensureLoaded();
    state = state.where((i) => i.id != id).toList();
    await _persist();
  }
}

final ideaProvider =
    NotifierProvider<IdeaNotifier, List<SermonIdea>>(IdeaNotifier.new);
