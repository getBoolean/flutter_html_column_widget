import 'package:flutter/foundation.dart';

@immutable
class HtmlStyleProvenanceEntry {
  const HtmlStyleProvenanceEntry({
    required this.property,
    required this.value,
    required this.origin,
    this.selector,
    this.important = false,
    this.sourceOrder = 0,
  });

  final String property;
  final String value;
  final HtmlStyleOrigin origin;
  final String? selector;
  final bool important;
  final int sourceOrder;
}

enum HtmlStyleOrigin { inline, stylesheet, userAgent }

@immutable
class HtmlStyleProvenance {
  const HtmlStyleProvenance(this.byProperty);

  final Map<String, HtmlStyleProvenanceEntry> byProperty;

  static const HtmlStyleProvenance empty = HtmlStyleProvenance(
    <String, HtmlStyleProvenanceEntry>{},
  );

  HtmlStyleProvenance merge(HtmlStyleProvenance? other) {
    if (other == null || other.byProperty.isEmpty) {
      return this;
    }
    if (byProperty.isEmpty) {
      return other;
    }
    return HtmlStyleProvenance(<String, HtmlStyleProvenanceEntry>{
      ...byProperty,
      ...other.byProperty,
    });
  }
}
