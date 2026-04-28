import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Small token-aware spinner used in inline loading positions.
class LuminaLoadingIndicator extends StatelessWidget {
  const LuminaLoadingIndicator({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size / 12,
        color: color ?? t.colors.accentPrimary,
      ),
    );
  }
}
