import '../../data/models/sermon_model.dart';

/// A sermon starter template.
class SermonTemplate {
  final String id;
  final String name;
  final String description;
  final String emoji;
  final List<SermonBlock> Function(String translation) buildBlocks;

  SermonTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.buildBlocks,
  });
}

/// All available sermon starter templates.
final sermonTemplates = <SermonTemplate>[
  SermonTemplate(
    id: 'blank',
    name: 'Blank',
    description: 'Start with a clean slate',
    emoji: '✦',
    buildBlocks: (_) => [SermonBlock.text('')],
  ),

  SermonTemplate(
    id: 'three_point',
    name: 'Three-Point',
    description: 'Introduction · 3 points · Conclusion',
    emoji: '①②③',
    buildBlocks: (translation) => [
      SermonBlock.text(
        'Introduction\n\nOpen with a hook — a story, question, or surprising fact that draws the congregation in.',
      ),
      SermonBlock.text('\nPoint 1: [Title]\n\nExpound your first main argument here.'),
      SermonBlock.text('\nPoint 2: [Title]\n\nBuild on Point 1 with your second key idea.'),
      SermonBlock.text('\nPoint 3: [Title]\n\nBring the three threads together with your climactic point.'),
      SermonBlock.text('\nConclusion\n\nSummarise the three points and issue a clear call to action or application.'),
    ],
  ),

  SermonTemplate(
    id: 'expository',
    name: 'Expository',
    description: 'Verse-by-verse through a passage',
    emoji: '📖',
    buildBlocks: (translation) => [
      SermonBlock.text(
        'Context\n\nIntroduce the book, author, and historical setting. '
        'Explain why this passage matters and what question it answers.',
      ),
      SermonBlock.text('\nObservation\n\nRead through the passage verse by verse. '
          'Note key words, repeated themes, and grammatical structures.'),
      SermonBlock.text('\nInterpretation\n\nWhat did the original author mean to communicate? '
          'Anchor your interpretation in the text.'),
      SermonBlock.text('\nApplication\n\nHow does this truth change how we think, feel, and live today? '
          'Give concrete, practical steps.'),
      SermonBlock.text('\nConclusion\n\nClose by pointing to Christ and issuing a personal call to respond.'),
    ],
  ),

  SermonTemplate(
    id: 'narrative',
    name: 'Narrative',
    description: 'Story-driven with tension & resolution',
    emoji: '✦',
    buildBlocks: (translation) => [
      SermonBlock.text(
        'Scene Setting\n\nPaint a vivid picture of the world the biblical story takes place in. '
        'Help the congregation feel present.',
      ),
      SermonBlock.text('\nTension\n\nIdentify the problem, conflict, or question that the passage raises. '
          'Make the congregation feel the weight of it.'),
      SermonBlock.text('\nComplications\n\nExplore how characters (and we) try and fail to solve the problem on our own terms.'),
      SermonBlock.text('\nClimax\n\nHow does God intervene or how is the tension resolved? '
          'This is the heart of the sermon.'),
      SermonBlock.text('\nResolution & Application\n\nHow does this story reframe our own story? '
          'What is the "So what?" for the congregation today?'),
    ],
  ),

  SermonTemplate(
    id: 'topical',
    name: 'Topical',
    description: 'Multiple scriptures on one theme',
    emoji: '🔍',
    buildBlocks: (translation) => [
      SermonBlock.text(
        'Introduction\n\nState the topic clearly. Why is this subject important right now? '
        'What question are you answering?',
      ),
      SermonBlock.text('\nScriptural Foundation\n\nPresent the key Bible passages that address this topic.'),
      SermonBlock.text('\nCommon Misconceptions\n\nAddress and gently correct common misunderstandings on this topic.'),
      SermonBlock.text('\nBiblical Truth\n\nDraw together what the whole Bible says about this theme. '
          'Use cross-references generously.'),
      SermonBlock.text('\nPractical Application\n\nGive 2–3 specific ways the congregation can live out this truth this week.'),
      SermonBlock.text('\nConclusion\n\nCall for a response. End with hope.'),
    ],
  ),
];
