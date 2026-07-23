import 'package:flutter/material.dart';

/// Highlight color swatches offered from the Bible reader's verse menu and
/// shown in the "My Highlights" list. Keys match what's stored in the
/// `highlights.color` column; values are what's actually painted. Kept
/// small and on-brand rather than a full color wheel.
///
/// Lives here (not in bible_reader_screen.dart) specifically so both
/// bible_reader_screen.dart and highlights_screen.dart can import it without
/// creating a circular import between the two screens.
const Map<String, Color> kHighlightColors = {
  'amber': Color(0xFFF5B400),
  'rose': Color(0xFFF43F5E),
  'blue': Color(0xFF3B82F6),
  'green': Color(0xFF22C55E),
  'purple': Color(0xFFA855F7),
};
