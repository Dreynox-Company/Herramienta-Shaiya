import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/startup_presentation.dart';

Widget presentation({
  bool enabled = true,
  bool reduced = false,
  VoidCallback? onTap,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(
      body: StudioStartupPresentation(
        enabled: enabled,
        artwork: const SizedBox(key: ValueKey('test-artwork')),
        child: Center(
          child: TextButton(
            onPressed: onTap ?? () {},
            child: const Text('Conectar DATA'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('logo fades in, holds, fades out and is removed without DATA', (
    tester,
  ) async {
    await tester.pumpWidget(presentation());
    double opacity() => tester
        .widget<FadeTransition>(find.byKey(const ValueKey('startup-logo-fade')))
        .opacity
        .value;
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 144));
    expect(opacity(), greaterThan(0));
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacity(), 1);
    await tester.pump(const Duration(milliseconds: 550));
    expect(opacity(), greaterThan(0));
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('startup-presentation')), findsNothing);
    expect(find.text('Conectar DATA').hitTestable(), findsOneWidget);
    await tester.pumpWidget(presentation());
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('startup-presentation')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicks are never blocked and dismiss the decorative cover', (
    tester,
  ) async {
    var clicked = 0;
    await tester.pumpWidget(presentation(onTap: () => clicked++));
    await tester.tap(find.text('Conectar DATA'));
    await tester.pump();
    expect(clicked, 1);
    expect(find.byKey(const ValueKey('startup-presentation')), findsNothing);
  });

  testWidgets(
    'starting an import dismisses the logo and cancellation never replays it',
    (tester) async {
      await tester.pumpWidget(presentation());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(presentation(enabled: false));
      expect(find.byKey(const ValueKey('startup-presentation')), findsNothing);
      await tester.pumpWidget(presentation(enabled: true));
      expect(find.byKey(const ValueKey('startup-presentation')), findsNothing);
    },
  );

  testWidgets(
    'reduced motion shows the workspace without an animated overlay',
    (tester) async {
      await tester.pumpWidget(presentation(reduced: true));
      expect(find.byKey(const ValueKey('startup-presentation')), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a muted ticker cannot leave the logo stuck', (tester) async {
    await tester.pumpWidget(TickerMode(enabled: false, child: presentation()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('startup-presentation')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 250),
    const Size(960, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('presentation remains inside $size without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(presentation());
      await tester.pump(const Duration(milliseconds: 500));
      final bounds = tester.getRect(find.byKey(const ValueKey('test-artwork')));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(size.height));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  }
}
