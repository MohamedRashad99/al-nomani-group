import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';

class StartupSplashView extends StatefulWidget {
  const StartupSplashView({super.key});

  static const displayDuration = Duration(seconds: 2);
  static const backgroundColor = AppColors.darkGreen;

  @override
  State<StartupSplashView> createState() => _StartupSplashViewState();
}

class _StartupSplashViewState extends State<StartupSplashView>
    with TickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StartupSplashView.backgroundColor,
      body: AnimatedBuilder(
        animation: Listenable.merge([_drift, _pulse]),
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                key: const Key('splash-seeds'),
                painter: SeedFieldPainter(t: _drift.value),
              ),
              Center(
                child: FadeTransition(
                  opacity: Tween<double>(begin: 0.72, end: 1).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 108,
                          height: 108,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFD4B483,
                                ).withValues(alpha: 0.35),
                                blurRadius: 28,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/al_nomani_logo.png',
                            semanticLabel: S.appName,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          S.appName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: AppColors.sand,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SeedFieldPainter extends CustomPainter {
  const SeedFieldPainter({required this.t});

  final double t;

  static const _seeds = <({double x, double delay, double size, int tone})>[
    (x: 0.08, delay: 0.00, size: 11, tone: 0),
    (x: 0.18, delay: 0.22, size: 8, tone: 1),
    (x: 0.27, delay: 0.41, size: 13, tone: 2),
    (x: 0.36, delay: 0.08, size: 7, tone: 0),
    (x: 0.47, delay: 0.63, size: 10, tone: 1),
    (x: 0.58, delay: 0.17, size: 12, tone: 2),
    (x: 0.69, delay: 0.52, size: 8, tone: 0),
    (x: 0.78, delay: 0.31, size: 14, tone: 1),
    (x: 0.88, delay: 0.74, size: 9, tone: 2),
    (x: 0.12, delay: 0.88, size: 10, tone: 1),
    (x: 0.42, delay: 0.35, size: 6, tone: 0),
    (x: 0.93, delay: 0.11, size: 11, tone: 2),
    (x: 0.05, delay: 0.57, size: 7, tone: 0),
    (x: 0.63, delay: 0.81, size: 9, tone: 1),
    (x: 0.83, delay: 0.44, size: 8, tone: 2),
    (x: 0.23, delay: 0.69, size: 12, tone: 0),
  ];

  static const _tones = [
    Color(0xFFD4B483),
    Color(0xFFA5D6A7),
    Color(0xFFFFCC80),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2E7D32).withValues(alpha: 0.55),
          AppColors.darkGreen.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: size.shortestSide * 0.55,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    for (final seed in _seeds) {
      final progress = (t + seed.delay) % 1;
      final x =
          seed.x * size.width +
          math.sin((t + seed.delay) * math.pi * 2) * 10;
      final y = size.height * (1.08 - progress * 1.16);
      final paint = Paint()
        ..color = _tones[seed.tone].withValues(alpha: 0.22 + 0.45 * progress);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.7 + progress * 0.5);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: seed.size * 0.62,
          height: seed.size,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant SeedFieldPainter oldDelegate) =>
      oldDelegate.t != t;
}
