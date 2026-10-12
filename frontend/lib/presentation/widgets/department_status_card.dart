import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class DepartmentStatusCard extends StatelessWidget {
  final String departmentCode;
  final String departmentName;
  final String floorLocation;
  final int totalMachines;
  final Map<String, dynamic> stateCounts;
  final double ratedCapacity;
  final String unit;
  final int activeIncidentsCount;
  final double targetEfficiencyPct;
  final VoidCallback? onTap;

  const DepartmentStatusCard({
    super.key,
    required this.departmentCode,
    required this.departmentName,
    required this.floorLocation,
    required this.totalMachines,
    required this.stateCounts,
    required this.ratedCapacity,
    required this.unit,
    required this.activeIncidentsCount,
    this.targetEfficiencyPct = 85.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    int running = (stateCounts['RUNNING'] as num?)?.toInt() ?? 0;
    int warning = (stateCounts['WARNING'] as num?)?.toInt() ?? 0;
    int critical = (stateCounts['CRITICAL'] as num?)?.toInt() ?? 0;
    int maintenance = (stateCounts['UNDER_MAINTENANCE'] as num?)?.toInt() ?? 0;
    int unknown = (stateCounts['UNKNOWN'] as num?)?.toInt() ?? 0;

    Color deptAccent = const Color(0xFF38BDF8);
    if (departmentCode == 'SPN') deptAccent = const Color(0xFF38BDF8);
    if (departmentCode == 'WEV') deptAccent = const Color(0xFF34D399);
    if (departmentCode == 'KNT') deptAccent = const Color(0xFFFBBF24);
    if (departmentCode == 'DYE') deptAccent = const Color(0xFFA855F7);
    if (departmentCode == 'FIN') deptAccent = const Color(0xFFF472B6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Department Code Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: deptAccent.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: deptAccent.withAlpha(100)),
                        ),
                        child: Text(
                          departmentCode,
                          style: TextStyle(color: deptAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          departmentName,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (activeIncidentsCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.errorRed.withAlpha(100)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.errorRed, size: 10),
                        const SizedBox(width: 4),
                        Text(
                          '$activeIncidentsCount Incident${activeIncidentsCount > 1 ? 's' : ''}',
                          style: const TextStyle(color: AppColors.errorRed, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              floorLocation,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
            ),
            const SizedBox(height: 12),

            // Capacity and Machines Stats Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RATED CAPACITY',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${ratedCapacity.toStringAsFixed(1)} $unit',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'ASSET FLEET',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$totalMachines Units',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Visual Status Distribution Segment Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: totalMachines == 0
                    ? Container(color: const Color(0xFF1E293B))
                    : Row(
                        children: [
                          if (running > 0)
                            Expanded(
                              flex: running,
                              child: Container(color: AppColors.successGreen),
                            ),
                          if (warning > 0)
                            Expanded(
                              flex: warning,
                              child: Container(color: AppColors.warningOrange),
                            ),
                          if (critical > 0)
                            Expanded(
                              flex: critical,
                              child: Container(color: AppColors.errorRed),
                            ),
                          if (maintenance > 0)
                            Expanded(
                              flex: maintenance,
                              child: Container(color: const Color(0xFF38BDF8)),
                            ),
                          if (unknown > 0)
                            Expanded(
                              flex: unknown,
                              child: Container(color: const Color(0xFF475569)),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),

            // Machine Counts Legend Row
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildStatusDot('$running Running', AppColors.successGreen),
                if (warning > 0) _buildStatusDot('$warning Warning', AppColors.warningOrange),
                if (critical > 0) _buildStatusDot('$critical Critical', AppColors.errorRed),
                if (maintenance > 0) _buildStatusDot('$maintenance Maint', const Color(0xFF38BDF8)),
                if (unknown > 0) _buildStatusDot('$unknown Stale/Idle', const Color(0xFF64748B)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
        ),
      ],
    );
  }
}
