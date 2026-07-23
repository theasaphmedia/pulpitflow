// Tests for the Hive-backed SermonStorage introduced to replace the old
// single-blob SharedPreferences store. Covers exactly the behavior that
// changed: per-record writes/deletes, stale-record reconciliation, a
// corrupt record no longer nuking the whole library, and the one-time
// legacy migration path.
//
// NOTE: written but not run in this environment (no Flutter/Dart
// toolchain available) — run `flutter test` locally before trusting it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulpitflow/data/local/sermon_storage.dart';
import 'package:pulpitflow/data/models/sermon_model.dart';

const _boxName = 'pf_sermons_v1';
const _legacyKey = 'pulpitflow_sermons';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulpitflow_hive_test');
    Hive.init(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saveSermon then loadSermons round-trips a single record', () async {
    final storage = SermonStorage();
    final sermon = Sermon(title: 'Test Sermon');

    await storage.saveSermon(sermon);
    final loaded = await storage.loadSermons();

    expect(loaded.length, 1);
    expect(loaded.first.id, sermon.id);
    expect(loaded.first.title, 'Test Sermon');
  });

  test('deleteSermonById removes only that one record', () async {
    final storage = SermonStorage();
    final a = Sermon(title: 'A');
    final b = Sermon(title: 'B');
    await storage.saveSermon(a);
    await storage.saveSermon(b);

    await storage.deleteSermonById(a.id);
    final loaded = await storage.loadSermons();

    expect(loaded.length, 1);
    expect(loaded.first.id, b.id);
  });

  test('saveSermons reconciles — removes records not in the new list', () async {
    final storage = SermonStorage();
    final a = Sermon(title: 'A');
    final b = Sermon(title: 'B');
    await storage.saveSermon(a);
    await storage.saveSermon(b);

    // Simulates the cloud-is-source-of-truth path: B was deleted on
    // another device, so it must not survive a saveSermons([a]) call.
    await storage.saveSermons([a]);
    final loaded = await storage.loadSermons();

    expect(loaded.length, 1);
    expect(loaded.first.id, a.id);
  });

  test('a corrupt record is skipped, not the whole library', () async {
    final storage = SermonStorage();
    final good = Sermon(title: 'Good');
    await storage.saveSermon(good);

    // Inject a corrupt record directly, bypassing the storage API — this
    // is exactly the old single-blob failure mode that used to wipe every
    // sermon back to the bundled demo set.
    final box = await Hive.openBox<String>(_boxName);
    await box.put('corrupt-id', 'not valid json {{{');

    final loaded = await storage.loadSermons();

    expect(loaded.length, 1);
    expect(loaded.first.title, 'Good');
  });

  test('migrates a legacy SharedPreferences blob on first load', () async {
    final legacySermon = Sermon(title: 'From The Old Days');
    SharedPreferences.setMockInitialValues({
      _legacyKey: jsonEncode([legacySermon.toJson()]),
    });

    final storage = SermonStorage();
    final loaded = await storage.loadSermons();

    expect(loaded.length, 1);
    expect(loaded.first.title, 'From The Old Days');

    // Confirms it's now actually persisted in Hive, not just returned once.
    final loadedAgain = await storage.loadSermons();
    expect(loadedAgain.length, 1);
    expect(loadedAgain.first.title, 'From The Old Days');
  });

  test('fresh install with no Hive data and no legacy data seeds demo sermons', () async {
    final storage = SermonStorage();
    final loaded = await storage.loadSermons();

    expect(loaded, isNotEmpty);
  });
}
