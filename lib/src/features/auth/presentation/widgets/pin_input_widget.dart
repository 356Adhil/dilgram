import 'package:flutter/material.dart';

class PinInputWidget extends StatelessWidget {
  final int pinLength;
  final int filledCount;
  final Color? filledColor;
  final Color? emptyColor;

  const PinInputWidget({
    super.key,
    this.pinLength = 4,
    required this.filledCount,
    this.filledColor,
    this.emptyColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = filledColor ?? theme.colorScheme.primary;
    final empty =
        emptyColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.3);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pinLength, (index) {
        final isFilled = index < filledCount;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          width: isFilled ? 18 : 14,
          height: isFilled ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? filled : Colors.transparent,
            border: Border.all(color: isFilled ? filled : empty, width: 2),
          ),
        );
      }),
    );
  }
}
