import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

enum TexoraTabStyle {
  pills,
  underlined,
}

/// Reusable filter tabs / category selector matching reference_13_screens.png
class TexoraFilterTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final Function(int) onTabSelected;
  final TexoraTabStyle style;

  const TexoraFilterTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    this.style = TexoraTabStyle.pills,
  });

  @override
  Widget build(BuildContext context) {
    if (style == TexoraTabStyle.underlined) {
      return Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: TexoraColors.cardBorder, width: 1),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: tabs.asMap().entries.map((entry) {
              final index = entry.key;
              final label = entry.value;
              final isSelected = selectedIndex == index;

              return InkWell(
                onTap: () => onTabSelected(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected ? TexoraColors.primaryBlue : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? TexoraColors.primaryBlue : TexoraColors.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    // Default: Pills Style
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isSelected = selectedIndex == index;

          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: InkWell(
              onTap: () => onTabSelected(index),
              borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? TexoraColors.primaryBlue : Colors.white,
                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                  border: Border.all(
                    color: isSelected ? TexoraColors.primaryBlue : TexoraColors.cardBorder,
                    width: 1,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : TexoraColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
