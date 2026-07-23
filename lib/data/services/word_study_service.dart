import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WordStudyResult {
  final String word;
  final String originalLanguage;
  final String transliteration;
  final String originalScript;
  final String strongsNumber;
  final String rootMeaning;
  final String fullDefinition;
  final String theologicalSignificance;
  final List<String> keyUsages;
  final List<String> relatedWords;
  final String preachersInsight;

  const WordStudyResult({
    required this.word,
    required this.originalLanguage,
    required this.transliteration,
    required this.originalScript,
    required this.strongsNumber,
    required this.rootMeaning,
    required this.fullDefinition,
    required this.theologicalSignificance,
    required this.keyUsages,
    required this.relatedWords,
    required this.preachersInsight,
  });

  factory WordStudyResult.fromJson(Map<String, dynamic> json) {
    return WordStudyResult(
      word: json['word'] as String? ?? '',
      originalLanguage: json['original_language'] as String? ?? '',
      transliteration: json['transliteration'] as String? ?? '',
      originalScript: json['original_script'] as String? ?? '',
      strongsNumber: json['strongs_number'] as String? ?? '',
      rootMeaning: json['root_meaning'] as String? ?? '',
      fullDefinition: json['full_definition'] as String? ?? '',
      theologicalSignificance:
          json['theological_significance'] as String? ?? '',
      keyUsages: List<String>.from(json['key_usages'] as List? ?? []),
      relatedWords: List<String>.from(json['related_words'] as List? ?? []),
      preachersInsight: json['preachers_insight'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'original_language': originalLanguage,
    'transliteration': transliteration,
    'original_script': originalScript,
    'strongs_number': strongsNumber,
    'root_meaning': rootMeaning,
    'full_definition': fullDefinition,
    'theological_significance': theologicalSignificance,
    'key_usages': keyUsages,
    'related_words': relatedWords,
    'preachers_insight': preachersInsight,
  };
}

class WordStudyService {
  // A pastor mid-sermon looking up a word they (or someone else) already
  // looked up before — "grace", "faith", "agape" — should get an instant
  // answer, not another multi-second round trip to the LLM. Every
  // successful study is cached to disk keyed by the normalized query, and
  // checked first. Only a genuinely new word/phrase pays the network cost.
  static const _kCachePrefix = 'pf_word_study_';

  String _cacheKey(String wordOrPhrase) =>
      '$_kCachePrefix${wordOrPhrase.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

  Future<WordStudyResult?> _loadCached(String wordOrPhrase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(wordOrPhrase));
      if (raw == null) return null;
      return WordStudyResult.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCached(String wordOrPhrase, WordStudyResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(wordOrPhrase),
        jsonEncode(result.toJson()),
      );
    } catch (_) {}
  }

  Future<WordStudyResult> study(String wordOrPhrase) async {
    final cached = await _loadCached(wordOrPhrase);
    if (cached != null) return cached;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'word-study',
        body: {'word': wordOrPhrase.trim()},
      );

      final data = response.data as Map<String, dynamic>?;

      if (data == null) {
        throw Exception('No response from server. Please try again.');
      }

      if (data.containsKey('error')) {
        throw Exception(data['error'] as String);
      }

      final result = WordStudyResult.fromJson(data);
      await _saveCached(wordOrPhrase, result);
      return result;
    } catch (e, st) {
      if (kDebugMode) debugPrint('WordStudyService error: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('Could not complete word study. Please try again.');
    }
  }
}

final wordStudyService = WordStudyService();
