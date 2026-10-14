import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

/// Loading indicator state matching Texora industrial clean aesthetic
class TexoraLoadingState extends StatelessWidget {
  final String message;
  final double height;

  const TexoraLoadingState({
    super.key,
    this.message = 'Loading factory data...',
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(TexoraColors.primaryBlue),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TexoraTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state container with icon and title
class TexoraEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  final double height;

  const TexoraEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: TexoraColors.neutralBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: TexoraColors.textMuted, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TexoraColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TexoraTypography.caption,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 14),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state container with error icon and retry button
class TexoraErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final double height;

  const TexoraErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TexoraColors.criticalBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: TexoraColors.criticalText, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                'Telemetry Connection Error',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: TexoraColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  color: TexoraColors.criticalText,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Retry Connection', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TexoraColors.primaryDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
