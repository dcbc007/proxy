import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PowerButton extends StatefulWidget {
  const PowerButton({super.key, required this.connected, required this.onTap});
  final bool connected;
  final VoidCallback onTap;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(_c.value, widget.connected),
          child: SizedBox(
            width: 190,
            height: 190,
            child: Center(
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFF342A1B), Color(0xFF111315)]),
                  border: Border.all(color: AppColors.gold, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppColors.gold.withOpacity(.42), blurRadius: 28, spreadRadius: 1),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.power_settings_new_rounded, color: AppColors.goldBright, size: 48),
                    const SizedBox(height: 7),
                    Text(widget.connected ? '点击断开' : '点击连接', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.connected);
  final double t;
  final bool connected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.gold.withOpacity(.25);
    canvas.drawCircle(c, 84, base);
    canvas.drawCircle(c, 91, base..color = AppColors.gold.withOpacity(.10));

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        transform: GradientRotation(t * math.pi * 2),
        colors: [Colors.transparent, AppColors.goldBright, Colors.transparent],
      ).createShader(Rect.fromCircle(center: c, radius: 86));
    canvas.drawCircle(c, 86, glow);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.connected != connected;
}
