import 'package:flutter/material.dart';

Color? parseHexColor(String? s) {
  if (s == null) return null;
  final v = s.trim();
  if (!RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$').hasMatch(v)) return null;
  if (v.length == 7) {
    final rgb = int.parse(v.substring(1), radix: 16);
    return Color(0xFF000000 | rgb); // add opaque alpha
  }
  final argb = int.parse(v.substring(1), radix: 16); // #AARRGGBB
  return Color(argb);
}

String colorToHex(Color c, {bool includeAlpha = false}) {
  final a = c.alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
  final r = c.red.toRadixString(16).padLeft(2, '0').toUpperCase();
  final g = c.green.toRadixString(16).padLeft(2, '0').toUpperCase();
  final b = c.blue.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${includeAlpha ? a : ''}$r$g$b';
}
