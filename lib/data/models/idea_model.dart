import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum IdeaTag { sermon, illustration, scripture, story, quote, outline, other }

class SermonIdea {
  final String id;
  final String content;
  final IdeaTag tag;
  final DateTime createdAt;
  final bool isPinned;

  SermonIdea({
    String? id,
    required this.content,
    this.tag = IdeaTag.sermon,
    DateTime? createdAt,
    this.isPinned = false,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'tag': tag.name,
        'createdAt': createdAt.toIso8601String(),
        'isPinned': isPinned,
      };

  factory SermonIdea.fromJson(Map<String, dynamic> json) => SermonIdea(
        id: json['id'] as String,
        content: json['content'] as String,
        tag: IdeaTag.values.byName(
          (json['tag'] as String?) ?? 'sermon',
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isPinned: (json['isPinned'] as bool?) ?? false,
      );

  SermonIdea copyWith({
    String? content,
    IdeaTag? tag,
    bool? isPinned,
  }) =>
      SermonIdea(
        id: id,
        content: content ?? this.content,
        tag: tag ?? this.tag,
        createdAt: createdAt,
        isPinned: isPinned ?? this.isPinned,
      );
}
