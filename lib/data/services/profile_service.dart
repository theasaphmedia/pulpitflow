import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';

class ProfileService {
  final _client = Supabase.instance.client;

  /// Fetch the profile for [userId]. Returns null if no row exists yet.
  Future<UserProfile?> fetchProfile(String userId) async {
    final rows = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .limit(1);

    if (rows.isEmpty) return null;
    return UserProfile.fromSupabase(rows.first);
  }

  /// Insert or update a profile row.
  Future<UserProfile> upsertProfile(UserProfile profile) async {
    final rows = await _client
        .from('profiles')
        .upsert(profile.toSupabase(), onConflict: 'id')
        .select();

    if ((rows as List).isEmpty) {
      // RLS silently rejected the write (or a transient response returned
      // no rows) — surface this instead of crashing on `.first`, so the
      // caller's catch block can tell "actually failed" apart from a
      // StateError with no useful message.
      throw StateError(
        'upsertProfile: write returned no rows (possible RLS rejection) for id=${profile.id}',
      );
    }

    return UserProfile.fromSupabase(rows.first as Map<String, dynamic>);
  }

  /// Create a brand-new profile for [userId] with optional seed data
  /// pulled from Supabase auth metadata (name from Google OAuth, etc.).
  Future<UserProfile> createProfile({
    required String userId,
    String? fullName,
  }) async {
    final now = DateTime.now().toIso8601String();
    final rows = await _client
        .from('profiles')
        .insert({
          'id': userId,
          'full_name': fullName,
          'ministry_title': 'Pastor',
          'default_translation': 'KJV',
          'created_at': now,
          'updated_at': now,
        })
        .select();

    if ((rows as List).isEmpty) {
      throw StateError(
        'createProfile: insert returned no rows (possible RLS rejection) for id=$userId',
      );
    }

    return UserProfile.fromSupabase(rows.first as Map<String, dynamic>);
  }
}

final profileService = ProfileService();
