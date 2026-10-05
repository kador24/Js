import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamal_phone_manager/theme/app_theme.dart';

void main() {
  test('application theme builds', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
  });
}
