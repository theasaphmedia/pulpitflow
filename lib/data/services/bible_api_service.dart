import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/scripture_data.dart';
import '../models/scripture_model.dart';

class BibleApiService {
  static const Map<String, String> _bibleIds = {
    'KJV': 'de4e12af7f28f599-02',
    'NIV': '78a9f6124f344018-01',
    'AMP': '7142879509583d59-04',
    'ESV': '01b29f4b342acc35-01',
    'NLT': '65eec8e0b60e656b-01',
    'NKJV': 'de4e12af7f28f599-01',
  };

  static const String _persistentCachePrefix = 'pf_verse_';
  static const String _chapterCachePrefix = 'pf_chapter_';
  static const String _votdCacheKey = 'pf_votd';

  final Dio _dio;
  final Logger _logger = Logger();

  // In-memory cache — verse ref:translation → passage
  final Map<String, ScripturePassage> _cache = {};
  final Map<String, List<ScriptureVerse>> _chapterCache = {};

  BibleApiService()
    : _dio = Dio(
        BaseOptions(
          baseUrl:
              dotenv.env['BIBLE_API_URL'] ??
              'https://api.scripture.api.bible/v1',
          headers: {
            'api-key': dotenv.env['BIBLE_API_KEY'] ?? '',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  // ── Get a single verse or passage ──────────
  Future<ScripturePassage?> getPassage(String ref, String translation) async {
    final cacheKey = '$ref:$translation';

    // 1. In-memory cache
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    // 2. Persistent Hive/SharedPreferences cache (offline support)
    final persisted = await _loadFromDisk(cacheKey);
    if (persisted != null) {
      _cache[cacheKey] = persisted;
      return persisted;
    }

    // 3. Mock data fallback
    final mockPassage = lookupScripture(ref, translation);
    if (mockPassage != null) {
      _cache[cacheKey] = mockPassage;
      return mockPassage;
    }

    // 4. Live API call
    final bibleId = _bibleIds[translation] ?? _bibleIds['KJV']!;
    try {
      final verseId = _refToApiId(ref);
      if (verseId == null) return null;

      final isRange = ref.contains('-') && ref.contains(':');
      ScripturePassage? passage;

      if (isRange) {
        passage = await _fetchPassage(ref, verseId, bibleId, translation);
      } else {
        passage = await _fetchVerse(ref, verseId, bibleId, translation);
      }

      if (passage != null) {
        _cache[cacheKey] = passage;
        await _saveToDisk(cacheKey, passage);
      }
      return passage;
    } catch (e) {
      _logger.e('Bible API error for $ref: $e');
      return null;
    }
  }

  // ── Fetch full chapter ──────────────────────
  Future<List<ScriptureVerse>> getChapter(
    String book,
    int chapter,
    String translation,
  ) async {
    final cacheKey = 'chapter:$book:$chapter:$translation';
    final bibleId = _bibleIds[translation] ?? _bibleIds['KJV']!;

    // 1. In-memory
    if (_chapterCache.containsKey(cacheKey)) {
      return _chapterCache[cacheKey]!;
    }

    // 2. Disk cache
    final persisted = await _loadChapterFromDisk(cacheKey);
    if (persisted != null && persisted.isNotEmpty) {
      _chapterCache[cacheKey] = persisted;
      return persisted;
    }

    // 3. Live API
    try {
      final chapterId = '${_bookToUsfm(book)}.$chapter';
      final response = await _dio.get(
        '/bibles/$bibleId/chapters/$chapterId',
        queryParameters: {
          'content-type': 'text',
          'include-notes': 'false',
          'include-titles': 'false',
          'include-chapter-numbers': 'false',
          'include-verse-numbers': 'true',
          'include-verse-spans': 'false',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        final content = data['content'] ?? '';
        final verses = _parseChapterContent(content);
        _chapterCache[cacheKey] = verses;
        await _saveChapterToDisk(cacheKey, verses);
        return verses;
      }
    } catch (e) {
      _logger.e('Fetch chapter error: $e');
    }
    return [];
  }

  // ── Full-text word/phrase search ───────────
  // Uses API.Bible's native search endpoint rather than fetching every
  // chapter client-side and scanning it — the app never holds a full local
  // copy of Bible text, so a real client-side "search the whole Bible"
  // feature isn't possible any other way. Not cached; searches are cheap
  // and results should reflect the query fresh each time.
  Future<List<ScriptureSearchHit>> searchScripture(
    String query,
    String translation, {
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final bibleId = _bibleIds[translation] ?? _bibleIds['KJV']!;
    try {
      final response = await _dio.get(
        '/bibles/$bibleId/search',
        queryParameters: {
          'query': trimmed,
          'limit': limit,
          'sort': 'relevance',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        final verses = (data?['verses'] as List?) ?? [];
        return verses
            .map(
              (v) => ScriptureSearchHit(
                reference: (v['reference'] ?? '').toString(),
                text: _cleanText((v['text'] ?? '').toString()),
                translation: translation,
              ),
            )
            .where((h) => h.reference.isNotEmpty && h.text.isNotEmpty)
            .toList();
      }
    } catch (e) {
      _logger.e('Scripture search error for "$trimmed": $e');
    }
    return [];
  }

  // ── Verse of the Day ───────────────────────
  Future<ScripturePassage?> getVerseOfTheDay() async {
    // Check if we have today's VOTD cached
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_votdCacheKey);
      if (cached != null) {
        final data = jsonDecode(cached);
        final date = data['date'] as String?;
        final today = DateTime.now().toIso8601String().substring(0, 10);
        if (date == today && data['passage'] != null) {
          return ScripturePassage.fromJson(
            data['passage'] as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {}

    // Rotate through curated VOTD list based on day of year
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays;
    final refs = _votdRefs;
    final ref = refs[dayOfYear % refs.length];

    final passage = await getPassage(ref, 'KJV');
    if (passage != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final today = DateTime.now().toIso8601String().substring(0, 10);
        await prefs.setString(
          _votdCacheKey,
          jsonEncode({'date': today, 'passage': passage.toJson()}),
        );
      } catch (_) {}
    }
    return passage;
  }

  // ── Disk persistence for offline support ───
  // Uses the sanitized cache key string itself (not `key.hashCode`) as the
  // SharedPreferences key. `String.hashCode` is a 32-bit hash with no
  // uniqueness guarantee across Dart/AOT versions — two different verse
  // refs could collide and silently serve each other's cached passage, and
  // the whole persistent cache would go stale-looking after an app update
  // changed the hash. A sanitized literal key has neither problem.
  String _diskKey(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

  Future<ScripturePassage?> _loadFromDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_persistentCachePrefix${_diskKey(key)}');
      if (raw == null) return null;
      return ScripturePassage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToDisk(String key, ScripturePassage passage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_persistentCachePrefix${_diskKey(key)}',
        jsonEncode(passage.toJson()),
      );
    } catch (_) {}
  }

  Future<List<ScriptureVerse>?> _loadChapterFromDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chapterCachePrefix${_diskKey(key)}');
      if (raw == null) return null;
      final list = jsonDecode(raw) as List;
      return list
          .map((v) => ScriptureVerse.fromJson(v as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveChapterToDisk(
    String key,
    List<ScriptureVerse> verses,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_chapterCachePrefix${_diskKey(key)}',
        jsonEncode(verses.map((v) => v.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ── Fetch single verse ──────────────────────
  Future<ScripturePassage?> _fetchVerse(
    String ref,
    String verseId,
    String bibleId,
    String translation,
  ) async {
    try {
      final response = await _dio.get(
        '/bibles/$bibleId/verses/$verseId',
        queryParameters: {
          'content-type': 'text',
          'include-notes': 'false',
          'include-titles': 'false',
          'include-chapter-numbers': 'false',
          'include-verse-numbers': 'true',
          'include-verse-spans': 'false',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        final text = _cleanText(data['content'] ?? '');
        final parts = _parseRef(ref);
        if (parts == null) return null;

        return ScripturePassage(
          reference: ref,
          translation: translation,
          book: parts['book']!,
          chapter: int.parse(parts['chapter']!),
          verseStart: int.parse(parts['verseStart']!),
          verseEnd: int.parse(parts['verseEnd']!),
          verses: [
            ScriptureVerse(
              verseNumber: int.parse(parts['verseStart']!),
              text: text,
            ),
          ],
        );
      }
    } catch (e) {
      _logger.e('Fetch verse error: $e');
    }
    return null;
  }

  // ── Fetch passage range ─────────────────────
  Future<ScripturePassage?> _fetchPassage(
    String ref,
    String passageId,
    String bibleId,
    String translation,
  ) async {
    try {
      final response = await _dio.get(
        '/bibles/$bibleId/passages/$passageId',
        queryParameters: {
          'content-type': 'text',
          'include-notes': 'false',
          'include-titles': 'false',
          'include-chapter-numbers': 'false',
          'include-verse-numbers': 'true',
          'include-verse-spans': 'false',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        final rawContent = data['content'] ?? '';
        final parts = _parseRef(ref);
        if (parts == null) return null;

        final verses = _parseVerseContent(
          rawContent,
          int.parse(parts['verseStart']!),
          int.parse(parts['verseEnd']!),
        );

        return ScripturePassage(
          reference: ref,
          translation: translation,
          book: parts['book']!,
          chapter: int.parse(parts['chapter']!),
          verseStart: int.parse(parts['verseStart']!),
          verseEnd: int.parse(parts['verseEnd']!),
          verses: verses,
        );
      }
    } catch (e) {
      _logger.e('Fetch passage error: $e');
    }
    return null;
  }

  // ── Convert ref to API.Bible verse ID ──────
  String? _refToApiId(String ref) {
    try {
      final parts = _parseRef(ref);
      if (parts == null) return null;

      final usfm = _bookToUsfm(parts['book']!);
      final chapter = parts['chapter']!;
      final verseStart = parts['verseStart']!;
      final verseEnd = parts['verseEnd']!;

      if (verseStart == verseEnd) {
        return '$usfm.$chapter.$verseStart';
      } else {
        return '$usfm.$chapter.$verseStart-$usfm.$chapter.$verseEnd';
      }
    } catch (e) {
      return null;
    }
  }

  // ── Parse ref string ────────────────────────
  Map<String, String>? _parseRef(String ref) {
    try {
      final colonIdx = ref.lastIndexOf(':');
      if (colonIdx == -1) return null;

      final bookChapter = ref.substring(0, colonIdx).trim();
      final versesPart = ref.substring(colonIdx + 1).trim();

      final lastSpace = bookChapter.lastIndexOf(' ');
      if (lastSpace == -1) return null;

      final book = bookChapter.substring(0, lastSpace).trim();
      final chapter = bookChapter.substring(lastSpace + 1).trim();

      int verseStart;
      int verseEnd;

      if (versesPart.contains('-')) {
        final verseParts = versesPart.split('-');
        verseStart = int.parse(verseParts[0].trim());
        verseEnd = int.parse(verseParts[1].trim());
      } else {
        verseStart = int.parse(versesPart);
        verseEnd = verseStart;
      }

      return {
        'book': book,
        'chapter': chapter,
        'verseStart': verseStart.toString(),
        'verseEnd': verseEnd.toString(),
      };
    } catch (e) {
      return null;
    }
  }

  // ── Clean API text ──────────────────────────
  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\[(\d+)\]'), '')
        .replaceAll(RegExp(r'\u00b6'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── Parse verse content from passage ───────
  List<ScriptureVerse> _parseVerseContent(
    String content,
    int startVerse,
    int endVerse,
  ) {
    final verses = <ScriptureVerse>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final cleaned = _cleanText(line);
      if (cleaned.isEmpty) continue;

      final match = RegExp(r'^(\d+)\s+(.+)').firstMatch(cleaned);
      if (match != null) {
        final verseNum = int.tryParse(match.group(1) ?? '');
        final verseText = match.group(2) ?? '';
        if (verseNum != null &&
            verseNum >= startVerse &&
            verseNum <= endVerse) {
          verses.add(ScriptureVerse(verseNumber: verseNum, text: verseText));
        }
      }
    }

    if (verses.isEmpty && content.isNotEmpty) {
      verses.add(
        ScriptureVerse(verseNumber: startVerse, text: _cleanText(content)),
      );
    }

    return verses;
  }

  // ── Parse full chapter content ──────────────
  List<ScriptureVerse> _parseChapterContent(String content) {
    final verses = <ScriptureVerse>[];
    final bracketRegex = RegExp(r'\[(\d+)\]\s*([^\[]+)');
    final matches = bracketRegex.allMatches(content);

    for (final match in matches) {
      final verseNum = int.tryParse(match.group(1) ?? '');
      final verseText = match.group(2)?.trim() ?? '';
      if (verseNum != null && verseText.isNotEmpty) {
        verses.add(ScriptureVerse(verseNumber: verseNum, text: verseText));
      }
    }

    if (verses.isEmpty) {
      final lines = content.split('\n');
      int verseNum = 1;
      for (final line in lines) {
        final cleaned = _cleanText(line);
        if (cleaned.isNotEmpty) {
          verses.add(ScriptureVerse(verseNumber: verseNum++, text: cleaned));
        }
      }
    }

    return verses;
  }

  // ── Book name to USFM ───────────────────────
  String _bookToUsfm(String book) {
    const map = {
      'Genesis': 'GEN',
      'Exodus': 'EXO',
      'Leviticus': 'LEV',
      'Numbers': 'NUM',
      'Deuteronomy': 'DEU',
      'Joshua': 'JOS',
      'Judges': 'JDG',
      'Ruth': 'RUT',
      '1 Samuel': '1SA',
      '2 Samuel': '2SA',
      '1 Kings': '1KI',
      '2 Kings': '2KI',
      '1 Chronicles': '1CH',
      '2 Chronicles': '2CH',
      'Ezra': 'EZR',
      'Nehemiah': 'NEH',
      'Esther': 'EST',
      'Job': 'JOB',
      'Psalms': 'PSA',
      'Psalm': 'PSA',
      'Proverbs': 'PRO',
      'Ecclesiastes': 'ECC',
      'Song of Solomon': 'SNG',
      'Isaiah': 'ISA',
      'Jeremiah': 'JER',
      'Lamentations': 'LAM',
      'Ezekiel': 'EZK',
      'Daniel': 'DAN',
      'Hosea': 'HOS',
      'Joel': 'JOL',
      'Amos': 'AMO',
      'Obadiah': 'OBA',
      'Jonah': 'JON',
      'Micah': 'MIC',
      'Nahum': 'NAH',
      'Habakkuk': 'HAB',
      'Zephaniah': 'ZEP',
      'Haggai': 'HAG',
      'Zechariah': 'ZEC',
      'Malachi': 'MAL',
      'Matthew': 'MAT',
      'Mark': 'MRK',
      'Luke': 'LUK',
      'John': 'JHN',
      'Acts': 'ACT',
      'Romans': 'ROM',
      '1 Corinthians': '1CO',
      '2 Corinthians': '2CO',
      'Galatians': 'GAL',
      'Ephesians': 'EPH',
      'Philippians': 'PHP',
      'Colossians': 'COL',
      '1 Thessalonians': '1TH',
      '2 Thessalonians': '2TH',
      '1 Timothy': '1TI',
      '2 Timothy': '2TI',
      'Titus': 'TIT',
      'Philemon': 'PHM',
      'Hebrews': 'HEB',
      'James': 'JAS',
      '1 Peter': '1PE',
      '2 Peter': '2PE',
      '1 John': '1JN',
      '2 John': '2JN',
      '3 John': '3JN',
      'Jude': 'JUD',
      'Revelation': 'REV',
    };
    return map[book] ?? book.toUpperCase().substring(0, 3);
  }

  // ── Curated VOTD list ───────────────────────
  static const List<String> _votdRefs = [
    'John 3:16',
    'Romans 8:28',
    'Philippians 4:13',
    'Jeremiah 29:11',
    'Isaiah 40:31',
    'Psalm 23:1',
    'Proverbs 3:5-6',
    'Romans 5:1',
    'Ephesians 2:8',
    'Hebrews 11:1',
    'Matthew 6:33',
    'Joshua 1:9',
    'Romans 8:38-39',
    'Psalm 46:1',
    '2 Timothy 1:7',
    'Galatians 2:20',
    'John 14:6',
    'Philippians 4:7',
    'Isaiah 41:10',
    'Psalm 119:105',
    'Romans 12:2',
    'Colossians 3:23',
    '1 Corinthians 10:13',
    'Matthew 11:28',
    'John 15:5',
    '2 Corinthians 5:17',
    'Psalm 27:1',
    'Romans 1:16',
    'Ephesians 6:10',
    'James 1:5',
    'Lamentations 3:23',
    'Micah 6:8',
    'Zephaniah 3:17',
    '1 John 4:19',
    'Revelation 21:4',
    'Psalm 37:4',
    'Matthew 5:16',
    'Colossians 1:17',
    'Acts 1:8',
    'John 10:10',
    'Romans 6:23',
    '1 Peter 5:7',
    'Psalm 139:14',
    'Deuteronomy 31:6',
    'Genesis 1:1',
  ];

  // ── Clear all offline cache ─────────────────
  Future<void> clearOfflineCache() async {
    _cache.clear();
    _chapterCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where(
            (k) =>
                k.startsWith(_persistentCachePrefix) ||
                k.startsWith(_chapterCachePrefix),
          )
          .toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}

final scriptureService = BibleApiService();
