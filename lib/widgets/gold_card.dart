import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GoldCard extends StatelessWidget {
  const GoldCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: box);
  }
}
