import 'package:flutter/material.dart';

/// Central Design Tokens for the Texora AI Reference UI
/// Matches reference_13_screens.png visual specification
class TexoraColors {
  // Light Sidebar (#FFFFFF) & Borders (#E2E8F0)
  static const Color sidebarBg = Color(0xFFFFFFFF); // Pure White Sidebar
  static const Color sidebarBorder = Color(0xFFE2E8F0);
  static const Color sidebarTextActive = Color(0xFF2563EB); // Royal Blue Active
  static const Color sidebarTextInactive = Color(0xFF475569); // Slate Body (#475569)
  static const Color sidebarActivePill = Color(0xFFEFF6FF); // Soft Blue Active Tint
  static const Color sidebarHover = Color(0xFFF1F5F9); // Light Hover

  // Main Workspace Canvas & Surfaces
  static const Color workspaceBg = Color(0xFFF8FAFC); // Pale Slate-50 (#F8FAFC)
  static const Color cardBg = Color(0xFFFFFFFF); // White Surface (#FFFFFF)
  static const Color cardBorder = Color(0xFFE2E8F0); // Subtle Border (#E2E8F0)
  static const Color headerBg = Color(0xFFFFFFFF);
  static const Color headerBorder = Color(0xFFE2E8F0);
  static const Color inputBg = Color(0xFFF1F5F9); // Light Gray-100 Input Surface

  // Typography
  static const Color textPrimary = Color(0xFF0F172A); // Heading Slate-900 (#0F172A)
  static const Color textSecondary = Color(0xFF475569); // Body Slate-600 (#475569)
  static const Color textMuted = Color(0xFF64748B); // Muted Slate-500 (#64748B)
  static const Color textPlaceholder = Color(0xFF94A3B8);

  // Brand & Action Colors
  static const Color primaryBlue = Color(0xFF2563EB); // Primary Royal Blue (#2563EB)
  static const Color primaryBlueHover = Color(0xFF1D4ED8);
  static const Color primaryBlueLight = Color(0xFFEFF6FF); // Soft blue tint
  static const Color primaryDark = Color(0xFF0F172A); // Dark navy button fill

  // Semantic Status Badges & Accents
  // Green / Running / Active / Passed / In Stock (#16A34A)
  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFF0FDF4);
  static const Color successText = Color(0xFF16A34A);
  static const Color successBorder = Color(0xFFBBF7D0);

  // Amber / Warning / Attention / Medium (#D97706)
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningText = Color(0xFFD97706);
  static const Color warningBorder = Color(0xFFFDE68A);

  // Red / Critical / High / Delayed / Low Stock (#DC2626)
  static const Color critical = Color(0xFFDC2626);
  static const Color criticalBg = Color(0xFFFEF2F2);
  static const Color criticalText = Color(0xFFDC2626);
  static const Color criticalBorder = Color(0xFFFECACA);

  // Blue / In Progress / Scheduled
  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFEFF6FF);
  static const Color infoText = Color(0xFF1D4ED8);
  static const Color infoBorder = Color(0xFFBFDBFE);

  // Neutral / Idle / Offline
  static const Color neutral = Color(0xFF64748B);
  static const Color neutralBg = Color(0xFFF1F5F9);
  static const Color neutralText = Color(0xFF334155);

  // Additional tokens
  static const Color borderDefault = cardBorder;
  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleBg = Color(0xFFFAF5FF);

  // Standardized Aliases & Semantic Names
  static const Color primary = primaryBlue;
  static const Color primaryLight = primaryBlueLight;
  static const Color primaryLightBorder = infoBorder;
  static const Color tableHeaderBg = inputBg;
  static const Color badgeSuccessBg = successBg;
  static const Color badgeSuccessText = successText;
  static const Color badgeWarningBg = warningBg;
  static const Color badgeWarningText = warningText;
  static const Color badgeDangerBg = criticalBg;
  static const Color badgeDangerText = criticalText;
  static const Color badgeInfoBg = infoBg;
  static const Color badgeInfoText = infoText;
}

class TexoraTypography {
  // Screen Title (Header)
  static const TextStyle screenTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: TexoraColors.textPrimary,
    letterSpacing: -0.3,
  );

  // Section / Card Title
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: TexoraColors.textPrimary,
    letterSpacing: -0.2,
  );

  // Card Subtitle / Caption
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: TexoraColors.textMuted,
  );

  // KPI Value
  static const TextStyle kpiValue = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: TexoraColors.textPrimary,
    letterSpacing: -0.5,
  );

  // Table Column Header
  static const TextStyle tableHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: TexoraColors.textMuted,
    letterSpacing: 0.3,
  );

  // Table Body Cell
  static const TextStyle tableCell = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: TexoraColors.textPrimary,
  );

  // Badge Label
  static const TextStyle badgeLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  // Body Regular
  static const TextStyle bodyRegular = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: TexoraColors.textSecondary,
    height: 1.4,
  );
}

class TexoraSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;

  // Corner Radii
  static const double radiusSm = 6.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 10.0;
  static const double radiusCard = 10.0;
  static const double radiusXl = 12.0;
  static const double radiusPill = 20.0;

  // Standard Box Shadow for Cards
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A000000), // 4% black
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];
}
