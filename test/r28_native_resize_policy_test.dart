import 'package:flutter_angle/flutter_angle.dart' show AngleOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/render/native_view.dart';

void main() {
  test(
    'the already-created first frame never requests a redundant native resize',
    () {
      final initial = AngleOptions(width: 444, height: 576, dpr: 1);
      expect(
        NativeView.sameBackingPixels(
          initial,
          AngleOptions(width: 444, height: 576, dpr: 1),
        ),
        isTrue,
      );
      expect(
        NativeView.sameBackingPixels(
          initial,
          AngleOptions(width: 443, height: 576, dpr: 1),
        ),
        isFalse,
      );
      expect(
        NativeView.sameBackingPixels(
          initial,
          AngleOptions(width: 444, height: 575, dpr: 1),
        ),
        isFalse,
      );
    },
  );

  test(
    'physical equality, not logical dimensions, controls the platform request',
    () {
      final initial = AngleOptions(width: 400, height: 600, dpr: 1);
      expect(
        NativeView.sameBackingPixels(
          initial,
          AngleOptions(width: 200, height: 300, dpr: 2),
        ),
        isTrue,
      );
      expect(
        NativeView.sameBackingPixels(
          initial,
          AngleOptions(width: 400, height: 600, dpr: 1.25),
        ),
        isFalse,
      );
    },
  );

  test('rounding follows the same integer pixel calculation as the plugin', () {
    final initial = AngleOptions(width: 101, height: 101, dpr: 1.25);
    expect(
      NativeView.sameBackingPixels(
        initial,
        AngleOptions(width: 126, height: 126, dpr: 1),
      ),
      isTrue,
    );
    expect(
      NativeView.sameBackingPixels(
        initial,
        AngleOptions(width: 127, height: 126, dpr: 1),
      ),
      isFalse,
    );
  });
}
