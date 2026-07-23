import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/sermon_model.dart';

/// Distinguishes *why* a backup failed to parse — previously `parseBackup`
/// returned an empty list for both "corrupt file" and "newer backup
/// version than this app supports," which look identical to a caller and
/// were both reported to the user as the same misleading "no valid
/// sermons found" message.
enum BackupParseStatus { ok, unsupportedVersion, corrupt }

class BackupParseResult {
  final BackupParseStatus status;
  final List<Sermon> sermons;
  const BackupParseResult._(this.status, this.sermons);

  factory BackupParseResult.ok(List<Sermon> sermons) =>
      BackupParseResult._(BackupParseStatus.ok, sermons);
  factory BackupParseResult.unsupportedVersion() =>
      const BackupParseResult._(BackupParseStatus.unsupportedVersion, []);
  factory BackupParseResult.corrupt() =>
      const BackupParseResult._(BackupParseStatus.corrupt, []);
}

/// Serialises all sermons to a JSON backup file and shares it via the OS share sheet.
class SermonBackupService {
  SermonBackupService._();

  static const _kVersion = 1;

  /// Exports [sermons] as a `.pulpitflow` JSON file and opens the share sheet.
  static Future<void> exportBackup(List<Sermon> sermons) async {
    final payload = {
      'version': _kVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'sermon_count': sermons.length,
      'sermons': sermons.map((s) => s.toJson()).toList(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

    // Write to a temp file
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File('${dir.path}/pulpitflow_backup_$stamp.json');
    await file.writeAsString(jsonStr, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'PulpitFlow Backup — $stamp',
      text:
          'PulpitFlow sermon backup · ${sermons.length} sermon${sermons.length == 1 ? '' : 's'} · $stamp',
    );
  }

  /// Parses a backup JSON string back into a list of sermons. The caller
  /// can distinguish "genuinely empty backup" from "failed to parse" (and,
  /// among failures, "corrupt file" from "made with a newer app version")
  /// via [BackupParseResult.status] instead of getting an empty list for
  /// every failure mode.
  static BackupParseResult parseBackup(String jsonStr) {
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return BackupParseResult.corrupt();
    }

    final version = map['version'] as int? ?? 0;
    if (version > _kVersion) return BackupParseResult.unsupportedVersion();

    try {
      final list = map['sermons'] as List<dynamic>? ?? [];
      final sermons = list
          .map((e) => Sermon.fromJson(e as Map<String, dynamic>))
          .toList();
      return BackupParseResult.ok(sermons);
    } catch (_) {
      return BackupParseResult.corrupt();
    }
  }
}
