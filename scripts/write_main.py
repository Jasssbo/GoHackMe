#!/usr/bin/env python3
"""Writes main.dart and creates placeholder asset directories."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def write(path, content):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(content)
    print(f"  wrote {path}")


write(
    "app/lib/main.dart",
    """\
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/cyberpunk_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: GoHackMeApp()));
}

class GoHackMeApp extends StatelessWidget {
  const GoHackMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GoHackMe',
      debugShowCheckedModeBanner: false,
      theme: CyberpunkTheme.dark,
      routerConfig: appRouter,
    );
  }
}
""",
)

# Create placeholder asset directories (git-tracked via .gitkeep)
for d in [
    "app/assets/shaders",
    "app/assets/fonts",
    "app/assets/images",
]:
    full = os.path.join(ROOT, d)
    os.makedirs(full, exist_ok=True)
    with open(os.path.join(full, ".gitkeep"), "w") as f:
        pass

print("  asset directories created")
print("Done.")
