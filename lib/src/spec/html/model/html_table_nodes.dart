import 'package:flutter/foundation.dart';

enum HtmlTableSectionKind { head, body, foot }

@immutable
class HtmlTableCellNode {
  const HtmlTableCellNode({
    required this.text,
    this.html = '',
    this.isHeader = false,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.scope,
  });

  final String text;
  final String html;
  final bool isHeader;
  final int colSpan;
  final int rowSpan;
  final String? scope;
}

@immutable
class HtmlTableRowNode {
  const HtmlTableRowNode({required this.cells});

  final List<HtmlTableCellNode> cells;
}

@immutable
class HtmlTableSectionNode {
  const HtmlTableSectionNode({required this.kind, required this.rows});

  final HtmlTableSectionKind kind;
  final List<HtmlTableRowNode> rows;
}

@immutable
class HtmlTableModel {
  const HtmlTableModel({
    this.caption,
    this.head = const HtmlTableSectionNode(
      kind: HtmlTableSectionKind.head,
      rows: <HtmlTableRowNode>[],
    ),
    this.bodies = const <HtmlTableSectionNode>[],
    this.foot = const HtmlTableSectionNode(
      kind: HtmlTableSectionKind.foot,
      rows: <HtmlTableRowNode>[],
    ),
  });

  final String? caption;
  final HtmlTableSectionNode head;
  final List<HtmlTableSectionNode> bodies;
  final HtmlTableSectionNode foot;

  List<HtmlTableRowNode> get rows {
    final out = <HtmlTableRowNode>[];
    out.addAll(head.rows);
    for (final body in bodies) {
      out.addAll(body.rows);
    }
    out.addAll(foot.rows);
    return out;
  }
}
