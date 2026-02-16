import 'package:flutter/material.dart';

import '../../model/html_nodes.dart';
import '../../model/html_table_nodes.dart';

class HtmlSemanticTableBlock extends StatelessWidget {
  const HtmlSemanticTableBlock({
    super.key,
    required this.node,
    required this.baseStyle,
  });

  final HtmlTableBlockNode node;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final table = node.tableModel;
    if (table == null || table.rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final sections = <HtmlTableSectionNode>[
      if (table.head.rows.isNotEmpty) table.head,
      ...table.bodies,
      if (table.foot.rows.isNotEmpty) table.foot,
    ];
    final flattenedRows = sections
        .expand((section) => section.rows.map((row) => (section, row)))
        .toList(growable: false);
    final borderColor = Theme.of(context).dividerColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (table.caption != null && table.caption!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              table.caption!,
              style: node.style.applyToTextStyle(
                baseStyle.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: borderColor)),
          child: Column(
            children: List<Widget>.generate(flattenedRows.length, (rowIndex) {
              final entry = flattenedRows[rowIndex];
              return _buildRow(
                context,
                entry.$2,
                entry.$1,
                rowIndex: rowIndex,
                totalRows: flattenedRows.length,
                borderColor: borderColor,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    HtmlTableRowNode row,
    HtmlTableSectionNode section, {
    required int rowIndex,
    required int totalRows,
    required Color borderColor,
  }) {
    final isHeader =
        section.kind == HtmlTableSectionKind.head ||
        row.cells.any((cell) => cell.isHeader);
    final isLastRow = rowIndex == totalRows - 1;
    return IntrinsicHeight(
      child: ColoredBox(
        color: isHeader
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List<Widget>.generate(row.cells.length, (cellIndex) {
            final cell = row.cells[cellIndex];
            final isLastCell = cellIndex == row.cells.length - 1;
            return Expanded(
              flex: cell.colSpan,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: borderColor),
                    top: BorderSide(color: borderColor),
                    right: isLastCell
                        ? BorderSide(color: borderColor)
                        : BorderSide.none,
                    bottom: isLastRow
                        ? BorderSide(color: borderColor)
                        : BorderSide.none,
                  ),
                ),
                child: Text(
                  cell.text,
                  style: node.style
                      .applyToTextStyle(baseStyle)
                      .copyWith(fontWeight: isHeader ? FontWeight.w700 : null),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
