import 'dart:async';

import 'package:flutter/material.dart';

import 'studio_brand.dart';

/// Decorative, one-shot startup animation. Keep this widget mounted around the
/// viewport: an empty catalog is NOT a request to replay the presentation.
/// It never waits for DATA, graphics initialization or image decoding.
class StudioStartupPresentation extends StatefulWidget {
  static const duration = Duration(milliseconds: 1440);
  final Widget child;
  final bool enabled;
  final Widget? artwork;

  const StudioStartupPresentation({
    super.key,
    required this.child,
    this.enabled = true,
    this.artwork,
  });

  @override
  State<StudioStartupPresentation> createState() => _StartupPresentationState();
}

class _StartupPresentationState extends State<StudioStartupPresentation>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> logoOpacity;
  late final Animation<double> coverOpacity;
  Timer? watchdog;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: StudioStartupPresentation.duration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) finish();
      });
    logoOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 45),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
    ]).animate(controller);
    coverOpacity = Tween(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: controller,
      curve: const Interval(.65, 1, curve: Curves.easeInOutCubic),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || finished) return;
      if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) {
        finish();
        return;
      }
      controller.forward();
      // An offstage route or a disabled ticker must not leave a permanent logo.
      watchdog = Timer(
        StudioStartupPresentation.duration + const Duration(milliseconds: 160),
        finish,
      );
    });
  }

  void finish() {
    if (!mounted || finished) return;
    watchdog?.cancel();
    controller.stop();
    setState(() => finished = true);
  }

  @override
  void didUpdateWidget(covariant StudioStartupPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && !finished) finish();
  }

  @override
  void dispose() {
    watchdog?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = !finished && widget.enabled &&
        !MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: show ? (_) => finish() : null,
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        if (show)
          Positioned.fill(
            child: IgnorePointer(
              key: const ValueKey('startup-presentation'),
              child: ExcludeSemantics(
                child: ClipRect(
                  child: RepaintBoundary(
                    child: Stack(fit: StackFit.expand, children: [
                      FadeTransition(
                        opacity: coverOpacity,
                        child: const ColoredBox(color: Color(0xff10151d)),
                      ),
                      Center(
                        child: LayoutBuilder(builder: (context, constraints) {
                          final width = (constraints.maxWidth - 48)
                              .clamp(0.0, 390.0);
                          return SizedBox(
                            width: width,
                            height: (width * 2 / 3)
                                .clamp(0.0, constraints.maxHeight),
                            child: FadeTransition(
                              key: const ValueKey('startup-logo-fade'),
                              opacity: logoOpacity,
                              child: widget.artwork ??
                                  StudioBrand(full: true, size: width),
                            ),
                          );
                        }),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
