import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/profile_model.dart';
import '../../data/services/profile_service.dart';
import 'auth_provider.dart';

class ProfileNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    // Re-run whenever auth state changes.
    final user = ref.watch(currentUserProvider);
    if (user == null) return null;

    try {
      var profile = await profileService.fetchProfile(user.id);

      // First sign-in — no row yet. Auto-create from auth metadata.
      if (profile == null) {
        final name =
            user.userMetadata?['full_name'] as String? ??
            user.userMetadata?['name'] as String?;
        profile = await profileService.createProfile(
          userId: user.id,
          fullName: name,
        );
      }
      return profile;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ProfileNotifier: failed to load profile\n$e\n$st');
      }
      return null;
    }
  }

  /// Returns true if the update was actually persisted to Supabase, false if
  /// it only landed optimistically in local state. Callers should surface a
  /// warning to the user on false — previously this failure was swallowed
  /// entirely (debug-log only), so a save that silently failed looked
  /// identical in the UI to one that succeeded.
  Future<bool> updateProfile(UserProfile updated) async {
    // Optimistic update.
    state = AsyncData(updated);
    try {
      final saved = await profileService.upsertProfile(updated);
      state = AsyncData(saved);
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ProfileNotifier.updateProfile failed: $e\n$st');
      }
      // Don't revert — local is still the best truth we have.
      return false;
    }
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfile?>(
  ProfileNotifier.new,
);
