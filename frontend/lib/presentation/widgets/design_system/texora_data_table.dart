import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

class TexoraColumnDef {
  final String title;
  final double? width;
  final int flex;
  final TextAlign alignment;

  const TexoraColumnDef({
    required this.title,
    this.width,
    this.flex = 1,
    this.alignment = TextAlign.left,
  });
}

/// Reusable High-Density Data Table matching reference_13_screens.png
class TexoraDataTable extends StatelessWidget {
  final List<TexoraColumnDef> columns;
  final List<List<Widget>> rows;
  final double minWidth;
  final Function(int rowIndex)? onRowTap;
  final Widget? emptyState;

  const TexoraDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 700,
    this.onRowTap,
    this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && emptyState != null) {
      return emptyState!;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: minWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  bottom: BorderSide(color: TexoraColors.cardBorder, width: 1),
                ),
              ),
              child: Row(
                children: columns.map((col) {
                  Widget headerCell = Text(
                    col.title.toUpperCase(),
                    style: TexoraTypography.tableHeader,
                    textAlign: col.alignment,
                    overflow: TextOverflow.ellipsis,
                  );
                  if (col.width != null) {
                    return SizedBox(width: col.width, child: headerCell);
                  }
                  return Expanded(flex: col.flex, child: headerCell);
                }).toList(),
              ),
            ),

            // Table Rows
            ...rows.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final rowCells = entry.value;

              return InkWell(
                onTap: onRowTap != null ? () => onRowTap!(rowIndex) : null,
                hoverColor: const Color(0xFFF1F5F9),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                    ),
                  ),
                  child: Row(
                    children: rowCells.asMap().entries.map((cellEntry) {
                      final cellIndex = cellEntry.key;
                      final cell = cellEntry.value;
                      final col = cellIndex < columns.length ? columns[cellIndex] : null;

                      if (col?.width != null) {
                        return SizedBox(width: col!.width, child: cell);
                      }
                      return Expanded(flex: col?.flex ?? 1, child: cell);
                    }).toList(),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
