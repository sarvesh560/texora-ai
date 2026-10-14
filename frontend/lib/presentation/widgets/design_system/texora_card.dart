import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

/// Reusable Card component matching reference_13_screens.png
/// White surface (#FFFFFF), 1px solid border (#E2E8F0), 10px corner radius, subtle shadow
class TexoraCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const TexoraCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;

    Widget cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null || trailingWidget != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: TexoraTypography.sectionTitle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TexoraTypography.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailingWidget,
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: TexoraColors.cardBorder),
          const SizedBox(height: 12),
        ],
        child,
      ],
    );

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusLg),
        border: Border.all(color: TexoraColors.cardBorder, width: 1),
        boxShadow: TexoraSpacing.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TexoraSpacing.radiusLg),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(TexoraSpacing.lg),
            child: cardContent,
          ),
        ),
      ),
    );
  }
}
