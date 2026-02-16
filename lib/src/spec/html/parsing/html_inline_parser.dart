import 'package:html/dom.dart' as dom;

import '../model/html_nodes.dart';

class HtmlInlineParser {
  const HtmlInlineParser();

  List<HtmlInlineSegment> parseCodeLike(
    dom.Element node,
    HtmlStyleData style, {
    required bool isCode,
  }) {
    final segments = <HtmlInlineSegment>[];
    for (final child in node.nodes) {
      if (child is dom.Text) {
        if (child.text.isEmpty) {
          continue;
        }
        segments.add(
          HtmlInlineSegment(text: child.text, style: style, isCode: isCode),
        );
        continue;
      }
      if (child is dom.Element) {
        final text = child.text;
        if (text.isEmpty) {
          continue;
        }
        segments.add(
          HtmlInlineSegment(text: text, style: style, isCode: isCode),
        );
      }
    }
    return segments;
  }
}
