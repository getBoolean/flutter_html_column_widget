import 'package:html/dom.dart' as dom;

enum CssCombinator { descendant, child, adjacentSibling, generalSibling }

class CssAttributeSelector {
  const CssAttributeSelector({required this.name, this.operator, this.value});

  final String name;
  final String? operator;
  final String? value;
}

class CssPseudoClass {
  const CssPseudoClass({required this.name, this.argument});

  final String name;
  final String? argument;
}

class CssCompoundSelector {
  const CssCompoundSelector({
    this.tag,
    this.id,
    this.classes = const <String>{},
    this.attributes = const <CssAttributeSelector>[],
    this.pseudoClasses = const <CssPseudoClass>[],
    this.universal = false,
  });

  final String? tag;
  final String? id;
  final Set<String> classes;
  final List<CssAttributeSelector> attributes;
  final List<CssPseudoClass> pseudoClasses;
  final bool universal;
}

class CssSelectorSegment {
  const CssSelectorSegment({required this.compound, this.combinatorToLeft});

  final CssCompoundSelector compound;
  final CssCombinator? combinatorToLeft;
}

class CssSelector {
  const CssSelector({required this.segments, required this.raw});

  final List<CssSelectorSegment> segments;
  final String raw;

  int get specificity {
    var a = 0;
    var b = 0;
    var c = 0;
    for (final segment in segments) {
      final compound = segment.compound;
      if (compound.id != null) {
        a += 1;
      }
      b += compound.classes.length;
      b += compound.attributes.length;
      b += compound.pseudoClasses.length;
      if (compound.tag != null && !compound.universal) {
        c += 1;
      }
    }
    return (a * 10000) + (b * 100) + c;
  }
}

class CssSelectorParser {
  const CssSelectorParser();

  CssSelector? parse(String selector) {
    final tokens = _tokenize(selector.trim());
    if (tokens.isEmpty) {
      return null;
    }
    final segments = <CssSelectorSegment>[];
    CssCombinator? pendingCombinator;
    for (final token in tokens) {
      if (_isCombinatorToken(token)) {
        pendingCombinator = _parseCombinator(token);
        continue;
      }
      final compound = _parseCompound(token);
      if (compound == null) {
        return null;
      }
      segments.add(
        CssSelectorSegment(
          compound: compound,
          combinatorToLeft: segments.isEmpty
              ? null
              : (pendingCombinator ?? CssCombinator.descendant),
        ),
      );
      pendingCombinator = null;
    }
    if (segments.isEmpty) {
      return null;
    }
    return CssSelector(segments: segments, raw: selector.trim());
  }

  bool _isCombinatorToken(String token) =>
      token == ' ' || token == '>' || token == '+' || token == '~';

  CssCombinator _parseCombinator(String token) {
    return switch (token) {
      '>' => CssCombinator.child,
      '+' => CssCombinator.adjacentSibling,
      '~' => CssCombinator.generalSibling,
      _ => CssCombinator.descendant,
    };
  }

  List<String> _tokenize(String input) {
    final out = <String>[];
    final buffer = StringBuffer();
    var inAttr = false;
    var depth = 0;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '[') {
        inAttr = true;
      } else if (char == ']') {
        inAttr = false;
      } else if (char == '(') {
        depth++;
      } else if (char == ')' && depth > 0) {
        depth--;
      }

      if (!inAttr &&
          depth == 0 &&
          (char == '>' || char == '+' || char == '~')) {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString().trim());
          buffer.clear();
        }
        out.add(char);
        continue;
      }
      if (!inAttr && depth == 0 && char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString().trim());
          buffer.clear();
        }
        if (out.isEmpty || out.last != ' ') {
          out.add(' ');
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) {
      out.add(buffer.toString().trim());
    }
    return out.where((token) => token.isNotEmpty).toList(growable: false);
  }

  CssCompoundSelector? _parseCompound(String token) {
    var source = token.trim();
    if (source.isEmpty) {
      return null;
    }

    String? tag;
    String? id;
    final classes = <String>{};
    final attributes = <CssAttributeSelector>[];
    final pseudoClasses = <CssPseudoClass>[];
    var universal = false;

    if (source.startsWith('*')) {
      universal = true;
      source = source.substring(1);
    }

    final tagMatch = RegExp(r'^[a-zA-Z][\w-]*').firstMatch(source);
    if (tagMatch != null) {
      tag = tagMatch.group(0)!.toLowerCase();
      source = source.substring(tag.length);
    }

    while (source.isNotEmpty) {
      if (source.startsWith('#')) {
        final m = RegExp(r'^#([\w-]+)').firstMatch(source);
        if (m == null || id != null) {
          return null;
        }
        id = m.group(1)!.toLowerCase();
        source = source.substring(m.group(0)!.length);
        continue;
      }
      if (source.startsWith('.')) {
        final m = RegExp(r'^\.([\w-]+)').firstMatch(source);
        if (m == null) {
          return null;
        }
        classes.add(m.group(1)!.toLowerCase());
        source = source.substring(m.group(0)!.length);
        continue;
      }
      if (source.startsWith('[')) {
        final close = source.indexOf(']');
        if (close == -1) {
          return null;
        }
        final raw = source.substring(1, close).trim();
        final attrMatch = RegExp(
          "^([\\w:-]+)\\s*(=|\\~=|\\|=|\\^=|\\\$=|\\*=)?\\s*(\"[^\"]*\"|'[^']*'|[^\"']+)?\$",
        ).firstMatch(raw);
        if (attrMatch == null) {
          return null;
        }
        final attrName = attrMatch.group(1)!.toLowerCase();
        final attrOperator = attrMatch.group(2);
        var attrValue = attrMatch.group(3);
        if (attrValue != null &&
            ((attrValue.startsWith('"') && attrValue.endsWith('"')) ||
                (attrValue.startsWith("'") && attrValue.endsWith("'")))) {
          attrValue = attrValue.substring(1, attrValue.length - 1);
        }
        attributes.add(
          CssAttributeSelector(
            name: attrName,
            operator: attrOperator,
            value: attrValue,
          ),
        );
        source = source.substring(close + 1);
        continue;
      }
      if (source.startsWith('::')) {
        return null;
      }
      if (source.startsWith(':')) {
        final m = RegExp(r'^:([\w-]+)(?:\(([^)]*)\))?').firstMatch(source);
        if (m == null) {
          return null;
        }
        final pseudoName = m.group(1)!.toLowerCase();
        pseudoClasses.add(
          CssPseudoClass(name: pseudoName, argument: m.group(2)?.trim()),
        );
        source = source.substring(m.group(0)!.length);
        continue;
      }
      return null;
    }

    if (!universal &&
        tag == null &&
        id == null &&
        classes.isEmpty &&
        attributes.isEmpty &&
        pseudoClasses.isEmpty) {
      return null;
    }
    return CssCompoundSelector(
      tag: tag,
      id: id,
      classes: classes,
      attributes: attributes,
      pseudoClasses: pseudoClasses,
      universal: universal,
    );
  }
}

class CssSelectorEngine {
  const CssSelectorEngine();

  bool matches(CssSelector selector, dom.Element node) {
    if (selector.segments.isEmpty) {
      return false;
    }
    return _matchesFromIndex(
      selector.segments.length - 1,
      node,
      selector.segments,
    );
  }

  bool _matchesFromIndex(
    int index,
    dom.Element node,
    List<CssSelectorSegment> segments,
  ) {
    final current = segments[index];
    if (!_matchesCompound(current.compound, node)) {
      return false;
    }
    if (index == 0) {
      return true;
    }
    final combinator = current.combinatorToLeft ?? CssCombinator.descendant;
    switch (combinator) {
      case CssCombinator.child:
        final parent = node.parent;
        return parent is dom.Element
            ? _matchesFromIndex(index - 1, parent, segments)
            : false;
      case CssCombinator.descendant:
        var parent = node.parent;
        while (parent is dom.Element) {
          if (_matchesFromIndex(index - 1, parent, segments)) {
            return true;
          }
          parent = parent.parent;
        }
        return false;
      case CssCombinator.adjacentSibling:
        final prev = _previousElementSibling(node);
        return prev != null
            ? _matchesFromIndex(index - 1, prev, segments)
            : false;
      case CssCombinator.generalSibling:
        var prev = _previousElementSibling(node);
        while (prev != null) {
          if (_matchesFromIndex(index - 1, prev, segments)) {
            return true;
          }
          prev = _previousElementSibling(prev);
        }
        return false;
    }
  }

  dom.Element? _previousElementSibling(dom.Element node) {
    final parent = node.parent;
    if (parent is! dom.Element) {
      return null;
    }
    dom.Element? previous;
    for (final child in parent.children) {
      if (identical(child, node)) {
        return previous;
      }
      previous = child;
    }
    return null;
  }

  bool _matchesCompound(CssCompoundSelector selector, dom.Element node) {
    final tagName = node.localName?.toLowerCase() ?? '';
    if (selector.tag != null && selector.tag != tagName) {
      return false;
    }
    if (selector.id != null) {
      final id = node.id.trim().toLowerCase();
      if (id != selector.id) {
        return false;
      }
    }
    if (selector.classes.isNotEmpty) {
      final classSet = node.classes.map((value) => value.toLowerCase()).toSet();
      if (!classSet.containsAll(selector.classes)) {
        return false;
      }
    }
    for (final attribute in selector.attributes) {
      final attrValue = node.attributes[attribute.name];
      if (attrValue == null) {
        return false;
      }
      final op = attribute.operator;
      final expected = attribute.value ?? '';
      if (op == null) {
        continue;
      }
      switch (op) {
        case '=':
          if (attrValue != expected) {
            return false;
          }
          break;
        case '~=':
          if (!attrValue.split(RegExp(r'\s+')).contains(expected)) {
            return false;
          }
          break;
        case '|=':
          if (!(attrValue == expected || attrValue.startsWith('$expected-'))) {
            return false;
          }
          break;
        case '^=':
          if (!attrValue.startsWith(expected)) {
            return false;
          }
          break;
        case r'$=':
          if (!attrValue.endsWith(expected)) {
            return false;
          }
          break;
        case '*=':
          if (!attrValue.contains(expected)) {
            return false;
          }
          break;
      }
    }
    for (final pseudo in selector.pseudoClasses) {
      if (!_matchesPseudo(node, pseudo)) {
        return false;
      }
    }
    return true;
  }

  bool _matchesPseudo(dom.Element node, CssPseudoClass pseudo) {
    switch (pseudo.name) {
      case 'first-child':
        final parent = node.parent;
        if (parent is! dom.Element || parent.children.isEmpty) {
          return false;
        }
        return identical(parent.children.first, node);
      case 'last-child':
        final parent = node.parent;
        if (parent is! dom.Element || parent.children.isEmpty) {
          return false;
        }
        return identical(parent.children.last, node);
      case 'nth-child':
        final index = int.tryParse(pseudo.argument ?? '');
        if (index == null || index < 1) {
          return false;
        }
        final parent = node.parent;
        if (parent is! dom.Element) {
          return false;
        }
        var pos = 0;
        for (final child in parent.children) {
          pos += 1;
          if (identical(child, node)) {
            return pos == index;
          }
        }
        return false;
      default:
        // Unsupported pseudo-classes must not match silently.
        return false;
    }
  }
}
