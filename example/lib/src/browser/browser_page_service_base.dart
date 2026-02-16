import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class BrowserPageLoadResult {
  const BrowserPageLoadResult({
    required this.uri,
    required this.html,
    required this.linkedCss,
  });

  final Uri uri;
  final String html;
  final Map<String, String> linkedCss;
}

abstract class BrowserPageServiceBase {
  Uri normalizeAddress(String input, {Uri? base});
  Future<BrowserPageLoadResult> load(Uri uri);
  Future<void> clearCache(Uri uri);
  void dispose();
}

class PendingCssRequest {
  const PendingCssRequest({required this.href, required this.baseUri});

  final String href;
  final Uri baseUri;
}

mixin BrowserPageServiceMixin on BrowserPageServiceBase {
  static const int maxEmbeddedDocumentDepth = 2;
  static const Duration minRequestInterval = Duration(milliseconds: 350);
  static const String browserLikeUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

  DateTime? lastRequestAt;

  @override
  Uri normalizeAddress(String input, {Uri? base}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Address is empty');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      throw FormatException('Invalid address: $input');
    }
    if (parsed.hasScheme) {
      return parsed;
    }
    if (base != null) {
      return base.resolveUri(parsed);
    }
    return Uri.parse('https://$trimmed');
  }

  Future<String> fetchText(
    Uri uri, {
    Uri? referer,
    bool expectPlainText = false,
  });

  Future<String> inlineEmbeddedHtmlDocuments(
    String html, {
    required Uri pageUri,
    required int depth,
    required Set<Uri> activeChain,
  }) async {
    if (depth >= maxEmbeddedDocumentDepth || html.trim().isEmpty) {
      return html;
    }
    final document = html_parser.parse(html);
    final objects = document.querySelectorAll('object');
    if (objects.isEmpty) {
      return html;
    }

    for (final object in objects) {
      final data = object.attributes['data']?.trim();
      if (data == null || data.isEmpty) {
        continue;
      }
      Uri nestedUri;
      try {
        nestedUri = normalizeAddress(data, base: pageUri);
      } on FormatException {
        continue;
      }
      if (!_isLikelyHtmlObject(object, nestedUri) ||
          activeChain.contains(nestedUri)) {
        continue;
      }
      try {
        final nestedHtml = await fetchText(nestedUri, referer: pageUri);
        final expandedNestedHtml = await inlineEmbeddedHtmlDocuments(
          nestedHtml,
          pageUri: nestedUri,
          depth: depth + 1,
          activeChain: <Uri>{...activeChain, nestedUri},
        );
        final nestedDocument = html_parser.parse(expandedNestedHtml);
        final bodyHtml = nestedDocument.body?.innerHtml;
        final replacementHtml = bodyHtml != null && bodyHtml.trim().isNotEmpty
            ? bodyHtml
            : expandedNestedHtml;
        final replacementNodes = html_parser
            .parseFragment(replacementHtml)
            .nodes
            .toList(growable: false);
        if (replacementNodes.isEmpty) {
          continue;
        }
        final parent = object.parentNode;
        if (parent == null) {
          continue;
        }
        for (final node in replacementNodes) {
          parent.insertBefore(node, object);
        }
        object.remove();
      } catch (_) {
        // Keep object fallback content when nested document cannot be loaded.
      }
    }
    return document.outerHtml;
  }

  bool _isLikelyHtmlObject(dom.Element object, Uri nestedUri) {
    final type = object.attributes['type']?.trim().toLowerCase();
    if (type != null &&
        (type.startsWith('text/html') ||
            type.startsWith('application/xhtml+xml'))) {
      return true;
    }
    final path = nestedUri.path.toLowerCase();
    return path.endsWith('.html') ||
        path.endsWith('.htm') ||
        path.endsWith('.xhtml') ||
        path.endsWith('.xht');
  }

  Future<Map<String, String>> loadLinkedCss(Uri pageUri, String html) async {
    final cssByHref = <String, String>{};
    final pending = <PendingCssRequest>[
      for (final href in extractStylesheetHrefs(html))
        PendingCssRequest(href: href, baseUri: pageUri),
      for (final href in extractInlineStyleImportHrefs(html))
        PendingCssRequest(href: href, baseUri: pageUri),
    ];
    final requested = <Uri>{};

    while (pending.isNotEmpty) {
      final request = pending.removeAt(0);
      final href = request.href;
      try {
        final cssUri = normalizeAddress(href, base: request.baseUri);
        if (!requested.add(cssUri)) {
          continue;
        }
        final css = await fetchText(
          cssUri,
          referer: request.baseUri,
          expectPlainText: true,
        );
        cssByHref[href] = css;
        cssByHref[cssUri.toString()] = css;
        for (final importedHref in extractLeadingImportHrefs(css)) {
          pending
              .add(PendingCssRequest(href: importedHref, baseUri: cssUri));
        }
      } catch (_) {
        // Keep rendering even when linked stylesheets fail to load.
      }
    }
    return cssByHref;
  }

  Set<String> extractStylesheetHrefs(String html) {
    final out = <String>{};
    final linkTagRegex = RegExp(r'<link\b[^>]*>', caseSensitive: false);
    for (final tagMatch in linkTagRegex.allMatches(html)) {
      final tag = tagMatch.group(0);
      if (tag == null) {
        continue;
      }
      final rel = extractAttribute(tag, 'rel');
      if (!isPreferredStylesheetRel(rel)) {
        continue;
      }
      final href = extractAttribute(tag, 'href')?.trim();
      if (href == null || href.isEmpty || href.startsWith('data:')) {
        continue;
      }
      out.add(href);
    }
    return out;
  }

  String? extractAttribute(String tag, String attribute) {
    final regex = RegExp(
      '$attribute\\s*=\\s*(["\'])(.*?)\\1',
      caseSensitive: false,
      dotAll: true,
    );
    final match = regex.firstMatch(tag);
    return match?.group(2);
  }

  bool isPreferredStylesheetRel(String? relRaw) {
    final rel = relRaw?.trim().toLowerCase();
    if (rel == null || rel.isEmpty) {
      return false;
    }
    final relTokens = rel.split(RegExp(r'\s+'));
    return relTokens.contains('stylesheet') &&
        !relTokens.contains('alternate');
  }

  Set<String> extractInlineStyleImportHrefs(String html) {
    final out = <String>{};
    final styleTagRegex = RegExp(
      r'<style\b[^>]*>(.*?)</style>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final styleMatch in styleTagRegex.allMatches(html)) {
      final css = styleMatch.group(1);
      if (css == null || css.trim().isEmpty) {
        continue;
      }
      out.addAll(extractLeadingImportHrefs(css));
    }
    return out;
  }

  Set<String> extractLeadingImportHrefs(String css) {
    final out = <String>{};
    var offset = 0;
    while (offset < css.length) {
      offset = skipCssWhitespaceAndComments(css, offset);
      if (offset >= css.length) {
        break;
      }
      if (startsWithIgnoreCase(css, offset, '@charset')) {
        final statementEnd = css.indexOf(';', offset);
        if (statementEnd < 0) {
          break;
        }
        offset = statementEnd + 1;
        continue;
      }
      if (!startsWithIgnoreCase(css, offset, '@import')) {
        break;
      }
      final statementEnd = css.indexOf(';', offset);
      if (statementEnd < 0) {
        break;
      }
      final statement = css.substring(offset, statementEnd + 1);
      final href = extractImportHref(statement);
      if (href != null && href.isNotEmpty) {
        out.add(href);
      }
      offset = statementEnd + 1;
    }
    return out;
  }

  int skipCssWhitespaceAndComments(String css, int start) {
    var offset = start;
    while (offset < css.length) {
      if (offset + 4 <= css.length &&
          css.substring(offset, offset + 4) == '<!--') {
        offset += 4;
        continue;
      }
      if (offset + 3 <= css.length &&
          css.substring(offset, offset + 3) == '-->') {
        offset += 3;
        continue;
      }
      final current = css.codeUnitAt(offset);
      if (current == 0x2f &&
          offset + 1 < css.length &&
          css.codeUnitAt(offset + 1) == 0x2a) {
        final commentEnd = css.indexOf('*/', offset + 2);
        if (commentEnd < 0) {
          return css.length;
        }
        offset = commentEnd + 2;
        continue;
      }
      if (current == 0x20 ||
          current == 0x09 ||
          current == 0x0a ||
          current == 0x0d ||
          current == 0x0c) {
        offset += 1;
        continue;
      }
      break;
    }
    return offset;
  }

  bool startsWithIgnoreCase(String text, int offset, String needle) {
    if (offset + needle.length > text.length) {
      return false;
    }
    final segment = text.substring(offset, offset + needle.length);
    return segment.toLowerCase() == needle.toLowerCase();
  }

  String? extractImportHref(String importStatement) {
    final urlMatch = RegExp(
      '@import\\s+url\\(\\s*(["\\\']?)([^)"\\\']+)\\1\\s*\\)',
      caseSensitive: false,
    ).firstMatch(importStatement);
    if (urlMatch != null) {
      return urlMatch.group(2)?.trim();
    }

    final quotedMatch = RegExp(
      '@import\\s+(["\\\'])([^"\\\']+)\\1',
      caseSensitive: false,
    ).firstMatch(importStatement);
    return quotedMatch?.group(2)?.trim();
  }

  Future<void> waitForRequestSlot() async {
    final last = lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < minRequestInterval) {
        await Future<void>.delayed(minRequestInterval - elapsed);
      }
    }
    lastRequestAt = DateTime.now();
  }
}
