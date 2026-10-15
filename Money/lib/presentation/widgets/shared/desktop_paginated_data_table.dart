import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:money/money.dart';

class DesktopPaginatedDataTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final int totalItems;
  final int currentPage;
  final int rowsPerPage;
  final ValueChanged<int> onPageChanged;
  final ScrollController verticalController;
  final ScrollController horizontalController;
  final double columnSpacing;
  final double minimumTableWidth;

  const DesktopPaginatedDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.totalItems,
    required this.currentPage,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.verticalController,
    required this.horizontalController,
    this.columnSpacing = 22,
    this.minimumTableWidth = 1020,
  });

  @override
  Widget build(BuildContext context) {
    final int pageCount = math.max(1, (totalItems / rowsPerPage).ceil());
    final int safePage = currentPage.clamp(0, pageCount - 1);
    final int firstItem = totalItems == 0 ? 0 : (safePage * rowsPerPage) + 1;
    final int lastItem = math.min(totalItems, firstItem + rows.length - 1);
    final Color rowDividerColor = context.colors.divider.withValues(
      alpha: context.isDark ? .45 : .32,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double tableWidth = math.max(
          constraints.maxWidth,
          minimumTableWidth,
        );

        return Material(
          color: context.colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.colors.divider),
          ),
          child: Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: horizontalController,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      height: constraints.maxHeight - 49,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DataTable(
                            showCheckboxColumn: false,
                            headingRowHeight: 40,
                            dataRowMinHeight: 0,
                            dataRowMaxHeight: 0,
                            horizontalMargin: 12,
                            columnSpacing: columnSpacing,
                            dividerThickness: 0,
                            headingRowColor: WidgetStatePropertyAll(
                              context.colors.primary.withValues(alpha: 0.08),
                            ),
                            headingTextStyle: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                            columns: columns,
                            rows: const [],
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: verticalController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: verticalController,
                                physics: const ClampingScrollPhysics(),
                                child: DividerTheme(
                                  data: DividerTheme.of(context).copyWith(
                                    color: rowDividerColor,
                                    thickness: .5,
                                  ),
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    headingRowHeight: 0,
                                    dataRowMinHeight: 43,
                                    dataRowMaxHeight: 47,
                                    horizontalMargin: 12,
                                    columnSpacing: columnSpacing,
                                    dividerThickness: .5,
                                    dataTextStyle: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 11.5,
                                    ),
                                    columns: columns,
                                    rows: rows,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: context.colors.divider),
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Text(
                        '$firstItem–$lastItem de $totalItems',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$rowsPerPage por página',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: safePage > 0
                            ? () => onPageChanged(safePage - 1)
                            : null,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Página anterior',
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text(
                        '${safePage + 1} de $pageCount',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: safePage + 1 < pageCount
                            ? () => onPageChanged(safePage + 1)
                            : null,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Próxima página',
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
