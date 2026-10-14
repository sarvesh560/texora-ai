import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

enum TexoraButtonVariant {
  primary,
  outline,
  royalBlue,
  danger,
}

/// Reusable action button matching reference_13_screens.png
class TexoraActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final TexoraButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final double? width;
  final double height;

  const TexoraActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = TexoraButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.width,
    this.height = 38,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    BorderSide border;

    switch (variant) {
      case TexoraButtonVariant.primary:
        bg = TexoraColors.primaryDark;
        textColor = Colors.white;
        border = BorderSide.none;
        break;
      case TexoraButtonVariant.royalBlue:
        bg = TexoraColors.primaryBlue;
        textColor = Colors.white;
        border = BorderSide.none;
        break;
      case TexoraButtonVariant.outline:
        bg = Colors.white;
        textColor = TexoraColors.textPrimary;
        border = const BorderSide(color: Color(0xFFCBD5E1), width: 1);
        break;
      case TexoraButtonVariant.danger:
        bg = TexoraColors.critical;
        textColor = Colors.white;
        border = BorderSide.none;
        break;
    }

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(textColor),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );

    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          elevation: 0,
          shadowColor: Colors.transparent,
          side: border,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
          ),
        ),
        child: content,
      ),
    );
  }
}
