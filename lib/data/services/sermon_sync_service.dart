import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sermon_model.dart';

/// Thin wrapper around the Supabase `sermons` table.
///
/// All methods throw on network error — callers are responsible for catching.
class SermonSyncService {
  final _client = Supabase.instance.client;

  /// Fetch all sermons for [userId], newest first.
  Future<List<Sermon>> fetchSermons(String userId) async {
    final rows = await _client
        .from('sermons')
        .select()
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => Sermon.fromSupabase(r as Map<String, dynamic>))
        .toList();
  }

  /// Insert or update a sermon (conflict target: `id`).
  Future<void> upsertSermon(Sermon sermon, String userId) async {
    await _client.from('sermons').upsert(
      sermon.toSupabase(userId),
      onConflict: 'id',
    );
  }

  /// Hard-delete a sermon by id.
  Future<void> deleteSermon(String id) async {
    await _client.from('sermons').delete().eq('id', id);
  }
}

final sermonSyncService = SermonSyncService();
