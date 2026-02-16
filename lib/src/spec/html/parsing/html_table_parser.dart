import 'package:html/dom.dart' as dom;

import '../model/html_table_nodes.dart';

class HtmlTableParser {
  const HtmlTableParser();

  HtmlTableModel parse(dom.Element tableElement) {
    final caption = tableElement.children
        .where((element) => _tag(element) == 'caption')
        .map((element) => _normalize(element.text))
        .where((text) => text.isNotEmpty)
        .cast<String?>()
        .firstWhere((value) => value != null, orElse: () => null);

    final head = _parseSection(
      tableElement.children.where((element) => _tag(element) == 'thead'),
      HtmlTableSectionKind.head,
    );
    final bodies = tableElement.children
        .where((element) => _tag(element) == 'tbody')
        .map((tbody) => _rowsFromContainer(tbody, HtmlTableSectionKind.body))
        .where((section) => section.rows.isNotEmpty)
        .toList(growable: false);
    final foot = _parseSection(
      tableElement.children.where((element) => _tag(element) == 'tfoot'),
      HtmlTableSectionKind.foot,
    );

    final implicitRows = tableElement.children
        .where((element) => _tag(element) == 'tr')
        .toList(growable: false);
    final normalizedBodies = bodies.isNotEmpty
        ? bodies
        : implicitRows.isNotEmpty
        ? <HtmlTableSectionNode>[
            HtmlTableSectionNode(
              kind: HtmlTableSectionKind.body,
              rows: implicitRows.map(_parseRow).toList(growable: false),
            ),
          ]
        : const <HtmlTableSectionNode>[];

    return HtmlTableModel(
      caption: caption,
      head: head,
      bodies: normalizedBodies,
      foot: foot,
    );
  }

  HtmlTableSectionNode _parseSection(
    Iterable<dom.Element> nodes,
    HtmlTableSectionKind kind,
  ) {
    final rows = <HtmlTableRowNode>[];
    for (final section in nodes) {
      rows.addAll(
        section.children
            .where((element) => _tag(element) == 'tr')
            .map(_parseRow),
      );
    }
    return HtmlTableSectionNode(kind: kind, rows: rows);
  }

  HtmlTableSectionNode _rowsFromContainer(
    dom.Element container,
    HtmlTableSectionKind kind,
  ) {
    return HtmlTableSectionNode(
      kind: kind,
      rows: container.children
          .where((element) => _tag(element) == 'tr')
          .map(_parseRow)
          .toList(growable: false),
    );
  }

  HtmlTableRowNode _parseRow(dom.Element rowElement) {
    final cells = rowElement.children
        .where((element) => _tag(element) == 'td' || _tag(element) == 'th')
        .map((cell) {
          final colSpan = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
          final rowSpan = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
          return HtmlTableCellNode(
            text: _normalize(cell.text),
            isHeader: _tag(cell) == 'th',
            colSpan: colSpan.clamp(1, 1000),
            rowSpan: rowSpan.clamp(1, 1000),
            scope: cell.attributes['scope'],
          );
        })
        .toList(growable: false);
    return HtmlTableRowNode(cells: cells);
  }

  String _tag(dom.Element element) => element.localName?.toLowerCase() ?? '';

  String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
