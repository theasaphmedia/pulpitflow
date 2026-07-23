import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight data class broadcast over the Realtime channel.
class PreachPayload {
  final String sermonId;
  final String sermonTitle;
  final String? seriesName;
  final int blockIndex;
  final int totalBlocks;
  final String blockText;        // text content (may be empty for scripture)
  final String? scriptureRef;    // non-null for scripture blocks
  final String? translation;
  final bool isScripture;
  final double fontSize;

  const PreachPayload({
    required this.sermonId,
    required this.sermonTitle,
    this.seriesName,
    required this.blockIndex,
    required this.totalBlocks,
    required this.blockText,
    this.scriptureRef,
    this.translation,
    required this.isScripture,
    required this.fontSize,
  });

  Map<String, dynamic> toJson() => {
        'sermon_id': sermonId,
        'sermon_title': sermonTitle,
        if (seriesName != null) 'series_name': seriesName,
        'block_index': blockIndex,
        'total_blocks': totalBlocks,
        'block_text': blockText,
        if (scriptureRef != null) 'scripture_ref': scriptureRef,
        if (translation != null) 'translation': translation,
        'is_scripture': isScripture,
        'font_size': fontSize,
      };

  factory PreachPayload.fromJson(Map<String, dynamic> j) => PreachPayload(
        sermonId: j['sermon_id'] as String? ?? '',
        sermonTitle: j['sermon_title'] as String? ?? '',
        seriesName: j['series_name'] as String?,
        blockIndex: (j['block_index'] as num?)?.toInt() ?? 0,
        totalBlocks: (j['total_blocks'] as num?)?.toInt() ?? 1,
        blockText: j['block_text'] as String? ?? '',
        scriptureRef: j['scripture_ref'] as String?,
        translation: j['translation'] as String?,
        isScripture: j['is_scripture'] as bool? ?? false,
        fontSize: (j['font_size'] as num?)?.toDouble() ?? 22.0,
      );
}

/// Manages a Supabase Realtime Broadcast channel for live sermon projection.
///
/// **Preacher flow:**
/// ```dart
/// final code = await preachSessionService.startSession();
/// // share `code` with the projectionist
/// preachSessionService.broadcast(payload);
/// await preachSessionService.stopSession();
/// ```
///
/// **Projectionist flow:**
/// ```dart
/// final channel = preachSessionService.joinSession(code, (p) {
///   setState(() => _payload = p);
/// });
/// // on dispose:
/// await Supabase.instance.client.removeChannel(channel);
/// ```
class PreachSessionService {
  static final PreachSessionService _instance = PreachSessionService._();
  factory PreachSessionService() => _instance;
  PreachSessionService._();

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _broadcastChannel;
  String? _activeCode;

  String? get activeCode => _activeCode;
  bool   get isActive    => _broadcastChannel != null;

  // ── Code generation ───────────────────────────────────────────────────────

  static String generateCode() {
    // 4 letters (no I/O) + 2 digits → e.g. "JOHN16", "PRCE42"
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const digits  = '0123456789';
    final rand = Random();
    final chars = [
      ...List.generate(4, (_) => letters[rand.nextInt(letters.length)]),
      ...List.generate(2, (_) => digits[rand.nextInt(digits.length)]),
    ]..shuffle(rand);
    return chars.join();
  }

  // ── Preacher API ──────────────────────────────────────────────────────────

  /// Creates a new session channel and returns the 6-char code to share.
  Future<String> startSession() async {
    await stopSession();
    _activeCode = generateCode();
    _broadcastChannel = _supabase.channel('preach:$_activeCode');
    _broadcastChannel!.subscribe();
    if (kDebugMode) debugPrint('PreachSessionService: started — code=$_activeCode');
    return _activeCode!;
  }

  /// Broadcasts the current sermon state to all projectionists.
  void broadcast(PreachPayload payload) {
    if (_broadcastChannel == null) return;
    _broadcastChannel!.sendBroadcastMessage(
      event: 'state',
      payload: payload.toJson(),
    );
  }

  /// Tears down the broadcast channel.
  Future<void> stopSession() async {
    if (_broadcastChannel != null) {
      await _supabase.removeChannel(_broadcastChannel!);
      _broadcastChannel = null;
    }
    _activeCode = null;
    if (kDebugMode) debugPrint('PreachSessionService: stopped');
  }

  // ── Projectionist API ─────────────────────────────────────────────────────

  /// Subscribes to [code] and fires [onUpdate] on every incoming state.
  /// Returns the channel so the caller can unsubscribe on dispose.
  RealtimeChannel joinSession(
    String code,
    void Function(PreachPayload) onUpdate,
  ) {
    final channel = _supabase.channel('preach:${code.toUpperCase().trim()}');
    channel
        .onBroadcast(
          event: 'state',
          callback: (payload) {
            try {
              onUpdate(
                PreachPayload.fromJson(Map<String, dynamic>.from(payload)),
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint('PreachSessionService.joinSession parse error: $e');
              }
            }
          },
        )
        .subscribe();
    if (kDebugMode) debugPrint('PreachSessionService: joined code=$code');
    return channel;
  }
}

final preachSessionService = PreachSessionService();
