import '../models/scripture_model.dart';
import 'bible_api_service.dart';

export 'bible_api_service.dart' show BibleApiService, scriptureService;

// ScriptureService is now a thin wrapper around BibleApiService
class ScriptureService {
  Future<ScripturePassage?> getPassage(String ref, String translation) =>
      scriptureService.getPassage(ref, translation);

  Future<List<ScriptureVerse>> getChapter(
    String book,
    int chapter,
    String translation,
  ) => scriptureService.getChapter(book, chapter, translation);

  Future<ScripturePassage?> getVerseOfTheDay() =>
      scriptureService.getVerseOfTheDay();

  Future<void> clearOfflineCache() => scriptureService.clearOfflineCache();
}
