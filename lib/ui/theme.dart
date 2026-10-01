import 'package:flutter/material.dart';

const Color kSeedColor = Color(0xFF3F6AE0);

ThemeData buildTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kSeedColor, brightness: brightness),
    );

/// Material 3 wrapper used as the root of every window (follows system light/dark).
class WindowApp extends StatelessWidget {
  const WindowApp({super.key, required this.home, this.title = 'Display Controller'});

  final Widget home;
  final String title;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: title,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: home,
      );
}
