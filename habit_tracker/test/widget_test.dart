import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:habit_tracker/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider so HabitRepository can read/write in tests
  const MethodChannel pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    pathProviderChannel.setMockMethodCallHandler((MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        final tmp = await Directory.systemTemp.createTemp('habit_test_');
        return tmp.path;
      }
      // You can add more methods if you use them
      return null;
    });
  });

  tearDownAll(() {
    pathProviderChannel.setMockMethodCallHandler(null);
  });

  testWidgets('smoke: app builds and shows title', (tester) async {
    final repo = await HabitRepository.create();
    final theme = ThemeController();
    await theme.load();

    await tester.pumpWidget(
      HabitApp(repository: repo, theme: theme),
    );

    await tester.pumpAndSettle();
    expect(find.text('Habit Tracker'), findsOneWidget);
  });

  testWidgets('home screen builds directly', (tester) async {
    final repo = await HabitRepository.create();
    final theme = ThemeController();
    await theme.load();

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(repository: repo, theme: theme)),
    );

    await tester.pumpAndSettle();
    // Empty state text when no habits
    expect(find.textContaining('Create your first habit'), findsOneWidget);
  });
}
