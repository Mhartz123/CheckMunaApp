import 'package:flutter/material.dart';
import '../services/theme_controller.dart';

class AppColors {
  AppColors._();

  static bool get _dark => ThemeController.instance.isDark;

  static Color get bg => _dark ? _Dark.bg : _Light.bg;

  static Color bgFor({required bool dark}) => dark ? _Dark.bg : _Light.bg;
  static Color get surface => _dark ? _Dark.surface : _Light.surface;
  static Color get surfaceAlt => _dark ? _Dark.surfaceAlt : _Light.surfaceAlt;
  static Color get border => _dark ? _Dark.border : _Light.border;

  static Color get accent => _dark ? _Dark.accent : _Light.accent;
  static Color get accentLight =>
      _dark ? _Dark.accentLight : _Light.accentLight;

  static Color get text => _dark ? _Dark.text : _Light.text;
  static Color get muted => _dark ? _Dark.muted : _Light.muted;

  static Color get compliantBg => _dark ? _Dark.compliantBg : _Light.compliantBg;
  static Color get compliantText =>
      _dark ? _Dark.compliantText : _Light.compliantText;

  static Color get nonCompliantBg =>
      _dark ? _Dark.nonCompliantBg : _Light.nonCompliantBg;
  static Color get nonCompliantText =>
      _dark ? _Dark.nonCompliantText : _Light.nonCompliantText;

  static Color get bannedBg => _dark ? _Dark.bannedBg : _Light.bannedBg;
  static Color get bannedText => _dark ? _Dark.bannedText : _Light.bannedText;

  static Color get labelKind => accentLight;
  static Color get damageKind => _dark ? _Dark.damageKind : _Light.damageKind;
  static Color get inspection => _dark ? _Dark.inspection : _Light.inspection;

  static const Color cameraBg = Color(0xFF111111);
}

class _Light {
  static const bg = Color(0xFFF0F7F2);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFE8F5EC);
  static const border = Color(0xFFC8E0CE);

  static const accent = Color(0xFF2E7D32);
  static const accentLight = Color(0xFF4CAF50);

  static const text = Color(0xFF1A2E1C);
  static const muted = Color(0xFF6A8F6E);

  static const compliantBg = Color(0xFFE8F5E9);
  static const compliantText = Color(0xFF1B5E20);

  static const nonCompliantBg = Color(0xFFFFF8E1);
  static const nonCompliantText = Color(0xFFE65100);

  static const bannedBg = Color(0xFFFFEBEE);
  static const bannedText = Color(0xFFB71C1C);

  static const damageKind = Color(0xFF1E88E5);
  static const inspection = Color(0xFF8E24AA);
}

class _Dark {
  static const bg = Color(0xFF10160F);
  static const surface = Color(0xFF1A231A);
  static const surfaceAlt = Color(0xFF232F23);
  static const border = Color(0xFF31402F);

  static const accent = Color(0xFF66BB6A);
  static const accentLight = Color(0xFF81C784);

  static const text = Color(0xFFE9F2E7);
  static const muted = Color(0xFF93AC91);

  static const compliantBg = Color(0xFF1C3320);
  static const compliantText = Color(0xFF81C784);

  static const nonCompliantBg = Color(0xFF3A2E12);
  static const nonCompliantText = Color(0xFFFFB74D);

  static const bannedBg = Color(0xFF3B1B1D);
  static const bannedText = Color(0xFFEF9A9A);

  static const damageKind = Color(0xFF64B5F6);
  static const inspection = Color(0xFFCE93D8);
}
