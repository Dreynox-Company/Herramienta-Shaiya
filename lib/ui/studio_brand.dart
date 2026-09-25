import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Provided artwork, never generated or pulled from DATA. Runtime originals are
/// shipped beside the executable; the exact embedded emblem is a safe fallback.
class StudioBrand extends StatelessWidget {
  final bool full;
  final double size;
  const StudioBrand({super.key, this.full = false, this.size = 28});

  static File? artwork(bool full) {
    final name = full ? 'shstudio-logo.png' : 'shstudio-emblem.png';
    for (final root in [
      p.dirname(Platform.resolvedExecutable),
      Directory.current.path,
    ]) {
      final f = File(p.join(root, 'Extras', 'Branding', name));
      if (f.existsSync()) return f;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final original = artwork(full);
    final fallback = Image.asset(
      'assets/branding/shstudio-emblem.png',
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Icon(Icons.auto_awesome, size: 24),
    );
    return Semantics(
      label: 'ShStudio · Shaiya Asset and World Studio',
      image: true,
      child: SizedBox(
        width: size,
        height: full ? size * 2 / 3 : size,
        child: original == null
            ? fallback
            : Image.file(
                original,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
