import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// Sentinel used by Sermon.copyWith to distinguish "not supplied" from null.
const _unset = Object();

enum BlockType { text, scripture }

enum SermonStatus { draft, ready, preached }

class SermonBlock {
  final String id;
  final BlockType type;
  final String content;
  final String? scriptureRef;
  final String? translation;
  final String? note; // pastor's private margin note / annotation

  SermonBlock({
    String? id,
    required this.type,
    required this.content,
    this.scriptureRef,
    this.translation,
    this.note,
  }) : id = id ?? _uuid.v4();

  factory SermonBlock.text(String content) {
    return SermonBlock(type: BlockType.text, content: content);
  }

  factory SermonBlock.scripture(String ref, {String? translation}) {
    return SermonBlock(
      type: BlockType.scripture,
      content: ref,
      scriptureRef: ref,
      translation: translation ?? 'KJV',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'scriptureRef': scriptureRef,
    'translation': translation,
    if (note != null) 'note': note,
  };

  factory SermonBlock.fromJson(Map<String, dynamic> json) {
    return SermonBlock(
      id: json['id'],
      type: BlockType.values.byName(json['type']),
      content: json['content'],
      scriptureRef: json['scriptureRef'],
      translation: json['translation'],
      note: json['note'] as String?,
    );
  }

  SermonBlock copyWith({
    String? content,
    String? scriptureRef,
    String? translation,
    Object? note = _unset,
  }) {
    return SermonBlock(
      id: id,
      type: type,
      content: content ?? this.content,
      scriptureRef: scriptureRef ?? this.scriptureRef,
      translation: translation ?? this.translation,
      note: note == _unset ? this.note : note as String?,
    );
  }
}

class Sermon {
  final String id;
  final String title;
  final List<SermonBlock> blocks;
  final String defaultTranslation;
  final SermonStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? series;
  final List<String> tags;
  final String? notes; // post-sermon reflection notes
  final DateTime? scheduledDate; // when the pastor plans to preach this sermon

  Sermon({
    String? id,
    required this.title,
    List<SermonBlock>? blocks,
    this.defaultTranslation = 'KJV',
    this.status = SermonStatus.draft,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.series,
    List<String>? tags,
    this.notes,
    this.scheduledDate,
  }) : id = id ?? _uuid.v4(),
       blocks = blocks ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       tags = tags ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'defaultTranslation': defaultTranslation,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'series': series,
    'tags': tags,
    if (notes != null) 'notes': notes,
    if (scheduledDate != null) 'scheduledDate': scheduledDate!.toIso8601String(),
  };

  factory Sermon.fromJson(Map<String, dynamic> json) {
    return Sermon(
      id: json['id'],
      title: json['title'],
      blocks: (json['blocks'] as List)
          .map((b) => SermonBlock.fromJson(b))
          .toList(),
      defaultTranslation: json['defaultTranslation'] ?? 'KJV',
      status: SermonStatus.values.byName(json['status'] ?? 'draft'),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      series: json['series'],
      tags: List<String>.from(json['tags'] ?? []),
      notes: json['notes'] as String?,
      scheduledDate: json['scheduledDate'] != null
          ? DateTime.parse(json['scheduledDate'] as String)
          : null,
    );
  }

  /// Serialize for Supabase (snake_case columns, user_id included).
  Map<String, dynamic> toSupabase(String userId) => {
    'id': id,
    'user_id': userId,
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'default_translation': defaultTranslation,
    'status': status.name,
    'series': series,
    'tags': tags,
    'notes': notes,
    'scheduled_date': scheduledDate?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Deserialize a row returned by Supabase (snake_case columns).
  factory Sermon.fromSupabase(Map<String, dynamic> row) {
    final blocksList = (row['blocks'] as List? ?? []);
    return Sermon(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      blocks: blocksList
          .map((b) => SermonBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      defaultTranslation: row['default_translation'] as String? ?? 'KJV',
      status: SermonStatus.values.byName(
        row['status'] as String? ?? 'draft',
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      series: row['series'] as String?,
      tags: List<String>.from(row['tags'] as List? ?? []),
      notes: row['notes'] as String?,
      scheduledDate: row['scheduled_date'] != null
          ? DateTime.parse(row['scheduled_date'] as String)
          : null,
    );
  }

  /// Pass [series] or [notes] to update; pass `null` explicitly to clear them.
  /// Omit entirely to keep the existing value.
  Sermon copyWith({
    String? title,
    List<SermonBlock>? blocks,
    String? defaultTranslation,
    SermonStatus? status,
    Object? series = _unset,
    List<String>? tags,
    Object? notes = _unset,
    Object? scheduledDate = _unset,
  }) {
    return Sermon(
      id: id,
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      defaultTranslation: defaultTranslation ?? this.defaultTranslation,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      series: series == _unset ? this.series : series as String?,
      tags: tags ?? this.tags,
      notes: notes == _unset ? this.notes : notes as String?,
      scheduledDate: scheduledDate == _unset
          ? this.scheduledDate
          : scheduledDate as DateTime?,
    );
  }

  int get scriptureCount =>
      blocks.where((b) => b.type == BlockType.scripture).length;

  List<String> get scriptureRefs => blocks
      .where((b) => b.type == BlockType.scripture)
      .map((b) => b.scriptureRef!)
      .toList();

  /// Total word count across all text blocks.
  int get wordCount {
    var count = 0;
    for (final b in blocks) {
      if (b.type == BlockType.text) {
        final trimmed = b.content.trim();
        if (trimmed.isNotEmpty) {
          count +=
              trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        }
      }
    }
    return count;
  }

  /// Estimated speaking time at 130 wpm. Returns empty string if < 50 words.
  String get speakingTimeLabel {
    final wc = wordCount;
    if (wc < 50) return '';
    final minutes = (wc / 130).ceil();
    return '~$minutes min';
  }
}
