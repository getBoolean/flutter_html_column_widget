import 'css_selector_engine.dart';

class CssDeclaration {
  const CssDeclaration({
    required this.property,
    required this.value,
    this.important = false,
  });

  final String property;
  final String value;
  final bool important;
}

class CssParsedRule {
  const CssParsedRule({
    required this.selector,
    required this.selectorText,
    required this.declarations,
    required this.sourceOrder,
  });

  final CssSelector selector;
  final String selectorText;
  final List<CssDeclaration> declarations;
  final int sourceOrder;

  int get specificity => selector.specificity;
}

class CssCascadeEngine {
  const CssCascadeEngine();

  List<CssDeclaration> resolveDeclarations(List<CssParsedRule> matchingRules) {
    final weighted = <String, _WeightedDeclaration>{};
    for (final rule in matchingRules) {
      for (final declaration in rule.declarations) {
        final candidate = _WeightedDeclaration(
          declaration: declaration,
          sourceOrder: rule.sourceOrder,
          specificity: rule.specificity,
        );
        final existing = weighted[declaration.property];
        if (existing == null || candidate.compareTo(existing) > 0) {
          weighted[declaration.property] = candidate;
        }
      }
    }
    final ordered = weighted.values.toList(growable: false)
      ..sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));
    return ordered.map((entry) => entry.declaration).toList(growable: false);
  }
}

class _WeightedDeclaration {
  const _WeightedDeclaration({
    required this.declaration,
    required this.sourceOrder,
    required this.specificity,
  });

  final CssDeclaration declaration;
  final int sourceOrder;
  final int specificity;

  int compareTo(_WeightedDeclaration other) {
    final importantCompare = _asInt(
      declaration.important,
    ).compareTo(_asInt(other.declaration.important));
    if (importantCompare != 0) {
      return importantCompare;
    }
    final specificityCompare = specificity.compareTo(other.specificity);
    if (specificityCompare != 0) {
      return specificityCompare;
    }
    return sourceOrder.compareTo(other.sourceOrder);
  }

  int _asInt(bool value) => value ? 1 : 0;
}
