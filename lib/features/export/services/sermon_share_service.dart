import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/sermon_model.dart';

/// Formats a [Sermon] as a readable text outline and opens the system share sheet.
class SermonShareService {
  SermonShareService._();

  static final _dateFmt = DateFormat('MMMM d, y');

  /// Shares the sermon outline as plain text via the OS share sheet.
  static Future<void> shareOutline(Sermon sermon) async {
    final text = _buildOutlineText(sermon);
    await Share.share(text, subject: sermon.title);
  }

  /// Copies the sermon outline as plain text to the system clipboard.
  /// Returns the formatted text string for convenience (e.g. to show a snackbar).
  static Future<String> copyOutline(Sermon sermon) async {
    final text = _buildOutlineText(sermon);
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  /// Shared formatting logic used by [shareOutline] and [copyOutline].
  static String _buildOutlineText(Sermon sermon) {
    final buffer = StringBuffer();

    // ── Header ────────────────────────────────────────────────────────────────
    buffer.writeln('📖 ${sermon.title.toUpperCase()}');

    if (sermon.series != null && sermon.series!.isNotEmpty) {
      buffer.writeln('Series: ${sermon.series}');
    }

    if (sermon.tags.isNotEmpty) {
      buffer.writeln('Tags: ${sermon.tags.map((t) => '#$t').join(' ')}');
    }

    final statusLabel = switch (sermon.status) {
      SermonStatus.draft    => 'Draft',
      SermonStatus.ready    => 'Ready',
      SermonStatus.preached => 'Preached',
    };
    buffer.writeln(
      '$statusLabel  •  ${_dateFmt.format(sermon.updatedAt)}',
    );

    buffer.writeln();
    buffer.writeln('─' * 40);
    buffer.writeln();

    // ── Blocks ────────────────────────────────────────────────────────────────
    bool lastWasText = false;

    for (final block in sermon.blocks) {
      if (block.type == BlockType.text) {
        final text = block.content.trim();
        if (text.isEmpty) continue;
        if (lastWasText) buffer.writeln(); // blank line between paragraphs
        buffer.writeln(text);
        lastWasText = true;
      } else {
        // Scripture block
        final ref = block.scriptureRef ?? block.content;
        final translation = block.translation ?? sermon.defaultTranslation;
        buffer.writeln();
        buffer.writeln('📌 $ref ($translation)');
        buffer.writeln();
        lastWasText = false;
      }
    }

    buffer.writeln();
    buffer.writeln('─' * 40);
    buffer.writeln('Shared via PulpitFlow');

    return buffer.toString().trim();
  }

  /// Formats a short social-media style post for Instagram, X, WhatsApp, etc.
  /// Structure: Hook line, key scripture chip, brief excerpt, hashtags, branding.
  static Future<void> shareForSocial(Sermon sermon) async {
    final buffer = StringBuffer();

    // ── Hook: sermon title ────────────────────────────────────────────────────
    buffer.writeln('✨ "${sermon.title}"');
    buffer.writeln();

    // ── Key scripture (first scripture block) ─────────────────────────────────
    final scriptures = sermon.blocks
        .where((b) => b.type == BlockType.scripture)
        .toList();
    if (scriptures.isNotEmpty) {
      final first = scriptures.first;
      final ref = first.scriptureRef ?? first.content;
      final translation = first.translation ?? sermon.defaultTranslation;
      buffer.writeln('📖 $ref ($translation)');
      buffer.writeln();
    }

    // ── First non-empty text excerpt (≤ 160 chars) ────────────────────────────
    for (final block in sermon.blocks) {
      if (block.type == BlockType.text) {
        final text = block.content.trim();
        if (text.isEmpty) continue;
        // Strip any leading heading-style tokens
        final cleaned = text
            .replaceAll(RegExp(r'^\n+'), '')
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .take(2)
            .join(' ')
            .trim();
        if (cleaned.length > 10) {
          final excerpt = cleaned.length > 160
              ? '${cleaned.substring(0, 157)}...'
              : cleaned;
          buffer.writeln('"$excerpt"');
          buffer.writeln();
          break;
        }
      }
    }

    // ── Series ────────────────────────────────────────────────────────────────
    if (sermon.series != null && sermon.series!.isNotEmpty) {
      buffer.writeln('Series: ${sermon.series}');

      buffer.writeln();
    }

    // ── Hashtags (tags + defaults) ────────────────────────────────────────────
    final hashtags = <String>[
      ...sermon.tags.map((t) => '#${t.replaceAll(' ', '')}'),
      '#sermon',
      '#preaching',
      '#PulpitFlow',
    ];
    buffer.writeln(hashtags.join(' '));

    final text = buffer.toString().trim();

    await Share.share(
      text,
      subject: sermon.title,
    );
  }
}
