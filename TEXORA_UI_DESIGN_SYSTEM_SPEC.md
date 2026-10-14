# Texora AI — UI Design System Specification & Token Architecture

**Reference Specification**: [reference_13_screens.png](file:///c:/Users/projects/texora-ai/reference_13_screens.png)  
**Date**: October 14, 2026  
**Auditor & Designer**: Principal Flutter Web Architect & UI/UX Designer  

---

## 1. Visual Analysis of Reference Image (Visual Measurements & Estimates)

All measurements below are engineering estimates extracted from careful analysis of the 13-screen composite specification:

| UI Attribute | Visual Observation from Reference | Engineering Specification (Estimated) |
|---|---|---|
| **Sidebar Width (Desktop)** | Fixed left rail with dark background | `240px` (standard), collapsible to `72px` on tablet/mobile |
| **Sidebar Background** | Deep navy with slight blue tint | `#0B132B` (surface), border right `1px solid #1E293B` |
| **Active Nav Item** | Solid royal blue rounded rectangle | Background: `#1D4ED8` or `#2563EB`, text: `#FFFFFF`, icon: `#FFFFFF`, radius: `8px`, horizontal padding: `12px`, vertical padding: `10px` |
| **Inactive Nav Item** | Low-contrast text with muted icon | Background: transparent, text: `#94A3B8`, icon: `#64748B`, hover bg: `#1E293B` |
| **Header Height** | Clean horizontal banner with bottom border | `60px` to `64px`, white background (`#FFFFFF`), border bottom: `1px solid #E2E8F0` |
| **Header Elements** | Screen title on left; actions on right | Left: 20px semi-bold title. Right: search icon, notification bell with red badge, user avatar (32px circle) + "Factory Manager ▼" |
| **Main Workspace Background**| High-contrast, clean, soft neutral surface | `#F8FAFC` (pale blue-gray canvas) |
| **Cards & Surfaces** | Crisp white floating tiles | `#FFFFFF`, border: `1px solid #E2E8F0`, corner radius: `10px`, shadow: `0 1px 3px rgba(0,0,0,0.05), 0 1px 2px rgba(0,0,0,0.03)` |
| **KPI Card Dimensions** | Compact 4-column cards | Height: `~100px - 110px`, padding: `16px`, title: `12px #64748B`, value: `24px - 28px #0F172A bold`, subtitle: `11px green/red` |
| **Data Tables** | High-density enterprise layout | Header: `38px` height, `#F8FAFC` bg, text: `11px #64748B uppercase`. Rows: `46px` height, alternating/white, text: `13px #1E293B` |
| **Filter Tabs** | Rounded pill buttons | Inactive: white/transparent with `#64748B`. Active: royal blue `#2563EB` or light blue pill `#EFF6FF` with `#1D4ED8` |
| **Status Badges** | Soft tinted capsules with colored text | Height: `22px`, radius: `12px`, padding: `3px 8px`, font size: `11px semi-bold` |
| **Primary Buttons** | Dark navy or royal blue filled buttons | Background: `#0F172A` (or `#2563EB`), text: `#FFFFFF`, radius: `6px`, padding: `8px 16px` |
| **Secondary Buttons** | White outline buttons | Background: `#FFFFFF`, border: `1px solid #CBD5E1`, text: `#1E293B`, radius: `6px` |
| **Charts** | Minimalist area/line/bar charts | Line width: `2px`, soft gradient fill (`#2563EB` at 10% opacity), minimal horizontal grid lines (`#F1F5F9`), no clutter |

---

## 2. Reusable Design System Tokens (`TexoraDesignSystem`)

### A. Color Palette (`TexoraColors`)

```dart
class TexoraColors {
  // Sidebar & Dark Chrome
  static const Color sidebarBg = Color(0xFF0B132B);
  static const Color sidebarBorder = Color(0xFF1E293B);
  static const Color sidebarTextActive = Colors.white;
  static const Color sidebarTextInactive = Color(0xFF94A3B8);
  static const Color sidebarActivePill = Color(0xFF2563EB); // Royal Blue

  // Main Workspace & Surfaces
  static const Color workspaceBg = Color(0xFFF8FAFC); // Pale blue-gray
  static const Color cardBg = Colors.white;
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color headerBg = Colors.white;
  static const Color headerBorder = Color(0xFFE2E8F0);

  // Typography
  static const Color textPrimary = Color(0xFF0F172A); // Dark Slate
  static const Color textSecondary = Color(0xFF475569); // Muted Slate
  static const Color textMuted = Color(0xFF64748B); // Slate Gray
  static const Color textPlaceholder = Color(0xFF94A3B8);

  // Primary Actions
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryBlueHover = Color(0xFF1D4ED8);
  static const Color primaryBlueLight = Color(0xFFEFF6FF); // Soft tint
  static const Color primaryDark = Color(0xFF0F172A); // Dark navy button

  // Status & Semantic Colors
  // Green / Success / Running
  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color successText = Color(0xFF047857);
  static const Color successBorder = Color(0xFFA7F3D0);

  // Amber / Warning / Attention
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningText = Color(0xFFB45309);
  static const Color warningBorder = Color(0xFFFDE68A);

  // Red / Critical / Delayed / Off-Spec
  static const Color critical = Color(0xFFEF4444);
  static const Color criticalBg = Color(0xFFFEF2F2);
  static const Color criticalText = Color(0xFFB91C1C);
  static const Color criticalBorder = Color(0xFFFECACA);

  // Blue / In Progress / Scheduled
  static const Color info = Color(0xFF3B82F6);
  static const Color infoBg = Color(0xFFEFF6FF);
  static const Color infoText = Color(0xFF1D4ED8);
  static const Color infoBorder = Color(0xFFBFDBFE);

  // Neutral / Gray / Idle
  static const Color neutral = Color(0xFF64748B);
  static const Color neutralBg = Color(0xFFF1F5F9);
  static const Color neutralText = Color(0xFF334155);
}
```

---

### B. Typography Hierarchy (`TexoraTypography`)

```dart
class TexoraTypography {
  static const String fontFamily = 'Inter';

  // Screen Title (Header)
  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: TexoraColors.textPrimary,
    letterSpacing: -0.3,
  );

  // Section / Card Title
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: TexoraColors.textPrimary,
    letterSpacing: -0.2,
  );

  // KPI Value
  static const TextStyle kpiValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: TexoraColors.textPrimary,
    letterSpacing: -0.5,
  );

  // KPI Label / Caption
  static const TextStyle kpiLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: TexoraColors.textMuted,
  );

  // Table Header
  static const TextStyle tableHeader = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: TexoraColors.textMuted,
    letterSpacing: 0.3,
  );

  // Table Body Cell
  static const TextStyle tableBody = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: TexoraColors.textPrimary,
  );

  // Status Badge Label
  static const TextStyle badgeLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  // Body Regular
  static const TextStyle bodyRegular = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: TexoraColors.textSecondary,
    height: 1.4,
  );
}
```

---

### C. Standard Spacing & Radii (`TexoraSpacing`)

```dart
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
  static const double radiusXl = 12.0;
  static const double radiusPill = 20.0;

  // Box Shadows
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A000000), // 4% black
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];
}
```

---

## 3. Core Component Library Specifications

### 1. `TexoraCard`
- **Purpose**: Base container for all dashboard panels, tables, and overview cards.
- **Visuals**: Background `#FFFFFF`, border `1px solid #E2E8F0`, corner radius `10px`, padding `16px`.
- **Options**: Optional header with title and action widget, optional footer.

### 2. `TexoraKpiCard`
- **Purpose**: Renders the 4 standard top KPI metrics (e.g. Total Machines: 120, Production Today: 12,450 kg).
- **Structure**:
  - Top row: Metric title (`12px #64748B`) + optional icon.
  - Middle: Value (`26px #0F172A Bold`).
  - Bottom row: Trend indicator (green capsule or text: `↑ +8% vs yesterday`).

### 3. `TexoraStatusBadge`
- **Purpose**: Renders pill capsules for statuses:
  - `Running` / `Active` / `Passed`: green `#ECFDF5` background, `#047857` text.
  - `Attention` / `Medium`: amber `#FFFBEB` background, `#B45309` text.
  - `Critical` / `Delayed`: red `#FEF2F2` background, `#B91C1C` text.
  - `In Progress` / `Assigned`: blue `#EFF6FF` background, `#1D4ED8` text.
  - `Open`: outline blue pill.
  - `Completed`: soft emerald pill.

### 4. `TexoraDataTable`
- **Purpose**: Clean, high-density data table matching Screens 3, 6, 7, 9, 13.
- **Specifications**:
  - Horizontal scrolling support on narrow viewports.
  - Subtle `#F8FAFC` header with `#E2E8F0` divider.
  - Alternating row hovers (`#F8FAFC`).
  - Formatted cell alignments (numbers right-aligned, badges centered, text left-aligned).

### 5. `TexoraAgentCard`
- **Purpose**: Displays the 6 agent specializations in Screen 2.
- **Specifications**:
  - White container with top-right green `Active` capsule.
  - Top-left agent icon with soft colored background (green shield for Machine Health, blue chart for Production, orange tools for Maintenance, etc.).
  - Title (`15px bold`) and subtitle (`12px muted`).

### 6. `TexoraActivityTimeline`
- **Purpose**: Renders the "Live AI Activity" feed on the Dashboard (Screen 1).
- **Structure**:
  - Timestamp column (`10:24`, `10:25`) in `#64748B`.
  - Colored status dot (red for anomaly, green for ticket created, blue for impact calculation, amber for approval).
  - Event description in `#1E293B`.

### 7. `TexoraFilterTabs`
- **Purpose**: Category filter chips (e.g. `All (120)`, `Spinning (28)`, `Weaving (24)`).
- **Structure**: Horizontal row of rounded pills; active tab has royal blue `#2563EB` fill or `#EFF6FF` tint with `#1D4ED8` text.

### 8. `TexoraActionButton`
- **Purpose**: Primary filled and secondary outline buttons.
- **Specs**:
  - Primary: `#0F172A` or `#2563EB` background with white text, 8px radius.
  - Outline: white background with `#CBD5E1` border and `#1E293B` text.

---

## 4. Layout Architecture: Shell & Header

```
+---------------------------------------------------------------------------------------+
|  TEXORA AI (Sidebar)  |  HEADER: [Screen Title]       [Search] [Bell(3)] [Manager v]  |
|  Dark Navy (#0B132B)  +---------------------------------------------------------------+
|                       |  MAIN WORKSPACE CANVAS (#F8FAFC)                              |
|  [x] Dashboard        |                                                               |
|  [ ] AI Agents        |  [KPI Card 1]  [KPI Card 2]  [KPI Card 3]  [KPI Card 4]       |
|  [ ] Machines         |                                                               |
|  [ ] Production       |  +-------------------------------+ +-----------------------+  |
|  [ ] Quality          |  | Left Main Card (70%)          | | Right Card (30%)      |  |
|  [ ] Maintenance      |  |                               | |                       |  |
|  [ ] Inventory        |  |                               | |                       |  |
|  [ ] Energy           |  |                               | |                       |  |
|  [ ] Reports          |  +-------------------------------+ +-----------------------+  |
+---------------------------------------------------------------------------------------+
```

This layout directly reproduces the visual hierarchy and design elegance of the 13 reference screens while establishing a reusable component foundation in Flutter.
