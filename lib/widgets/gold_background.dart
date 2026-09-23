import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GoldBackground extends StatelessWidget {
  const GoldBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.35),
          radius: 1.25,
          colors: [
            Color(0xFF2B2113),
            AppColors.bg2,
            AppColors.bg,
          ],
          stops: [0, .45, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _GoldMistPainter()),
          child,
        ],
      ),
    );
  }
}

class _GoldMistPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..shader = RadialGradient(
        colors: [AppColors.gold.withOpacity(.16), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(size.width * .52, size.height * .34), radius: size.width * .55));
    canvas.drawCircle(Offset(size.width * .52, size.height * .34), size.width * .55, p);
    final line = Paint()
      ..color = AppColors.gold.withOpacity(.05)
      ..strokeWidth = 1;
    for (int i = 0; i < 9; i++) {
      final y = size.height * (.18 + i * .08);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - size.width * .12), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
