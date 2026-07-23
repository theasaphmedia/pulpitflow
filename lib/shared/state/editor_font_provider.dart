import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

// ── Editor font enum ──────────────────────────────────────────────────────────

enum EditorFont {
  cormorantGaramond,
  inter,
  lora,
  merriweather,
  playfairDisplay,
  literata,
}

extension EditorFontExtension on EditorFont {
  String get displayName {
    switch (this) {
      case EditorFont.cormorantGaramond:
        return 'Cormorant Garamond';
      case EditorFont.inter:
        return 'Inter';
      case EditorFont.lora:
        return 'Lora';
      case EditorFont.merriweather:
        return 'Merriweather';
      case EditorFont.playfairDisplay:
        return 'Playfair Display';
      case EditorFont.literata:
        return 'Literata';
    }
  }

  String get category {
    switch (this) {
      case EditorFont.inter:
        return 'Sans-serif';
      case EditorFont.cormorantGaramond:
      case EditorFont.lora:
      case EditorFont.merriweather:
      case EditorFont.playfairDisplay:
      case EditorFont.literata:
        return 'Serif';
    }
  }

  TextStyle bodyStyle({
    double fontSize = 16,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
  }) {
    switch (this) {
      case EditorFont.cormorantGaramond:
        return PulpitFonts.cormorantGaramond(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          height: height,
        );
      case EditorFont.inter:
        return PulpitFonts.inter(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          height: height,
        );
      case EditorFont.lora:
        return PulpitFonts.lora(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          height: height,
        );
      case EditorFont.merriweather:
        return PulpitFonts.merriweather(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          height: height,
        );
      case EditorFont.playfairDisplay:
        return PulpitFonts.playfairDisplay(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          height: height,
        );
      case EditorFont.literata:
        return PulpitFonts.literata(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          height: height,
        );
    }
  }

  String get sampleText => 'And the Word was made flesh, and dwelt among us.';
}

// ── Provider ──────────────────────────────────────────────────────────────────

class EditorFontNotifier extends Notifier<EditorFont> {
  static const _key = 'editor_font';

  @override
  EditorFont build() {
    _load();
    return EditorFont.cormorantGaramond;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      try {
        state = EditorFont.values.byName(saved);
      } catch (_) {}
    }
  }

  Future<void> setFont(EditorFont font) async {
    state = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, font.name);
  }
}

final editorFontProvider = NotifierProvider<EditorFontNotifier, EditorFont>(
  EditorFontNotifier.new,
);