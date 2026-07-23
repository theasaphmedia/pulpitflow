class ScriptureVerse {
  final int verseNumber;
  final String text;

  const ScriptureVerse({required this.verseNumber, required this.text});

  Map<String, dynamic> toJson() => {'verseNumber': verseNumber, 'text': text};

  factory ScriptureVerse.fromJson(Map<String, dynamic> json) {
    return ScriptureVerse(verseNumber: json['verseNumber'], text: json['text']);
  }
}

class ScripturePassage {
  final String reference;
  final String translation;
  final String book;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final List<ScriptureVerse> verses;

  const ScripturePassage({
    required this.reference,
    required this.translation,
    required this.book,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.verses,
  });

  String get fullText => verses.map((v) => v.text).join(' ');

  String get displayText =>
      verses.map((v) => '${v.verseNumber} ${v.text}').join('\n');

  Map<String, dynamic> toJson() => {
    'reference': reference,
    'translation': translation,
    'book': book,
    'chapter': chapter,
    'verseStart': verseStart,
    'verseEnd': verseEnd,
    'verses': verses.map((v) => v.toJson()).toList(),
  };

  factory ScripturePassage.fromJson(Map<String, dynamic> json) {
    return ScripturePassage(
      reference: json['reference'],
      translation: json['translation'],
      book: json['book'],
      chapter: json['chapter'],
      verseStart: json['verseStart'],
      verseEnd: json['verseEnd'],
      verses: (json['verses'] as List)
          .map((v) => ScriptureVerse.fromJson(v))
          .toList(),
    );
  }
}

/// A single verse hit from a full-text word/phrase search against a Bible
/// translation (API.Bible's `/bibles/{id}/search` endpoint). Distinct from
/// [ScriptureVerse] because search results carry their own reference string
/// and are not scoped to one chapter the caller already knows about.
class ScriptureSearchHit {
  final String reference;
  final String text;
  final String translation;

  const ScriptureSearchHit({
    required this.reference,
    required this.text,
    required this.translation,
  });
}

class Translation {
  final String code;
  final String name;
  final String shortName;

  const Translation({
    required this.code,
    required this.name,
    required this.shortName,
  });
}
