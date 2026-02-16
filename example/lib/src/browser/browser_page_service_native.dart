import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_page_service_base.dart';

BrowserPageServiceBase createPlatformPageService() =>
    BrowserPageServiceNative();

class BrowserPageServiceNative extends BrowserPageServiceBase
    with BrowserPageServiceMixin {
  BrowserPageServiceNative();

  static const int _cacheSchemaVersion = 4;
  static const int _maxFetchAttempts = 4;
  static const Duration _loadTimeout = Duration(seconds: 25);

  bool _cacheLoaded = false;
  final Map<String, _CachedPageData> _cache = <String, _CachedPageData>{};

  @override
  void dispose() {}

  @override
  Future<BrowserPageLoadResult> load(Uri uri) async {
    await _ensureCacheLoaded();
    final cacheKey = uri.toString();
    final cached = _cache[cacheKey];
    if (cached != null) {
      final expandedCachedHtml = await inlineEmbeddedHtmlDocuments(
        cached.html,
        pageUri: uri,
        depth: 0,
        activeChain: <Uri>{uri},
      );
      if (expandedCachedHtml != cached.html) {
        final linkedCss = await loadLinkedCss(uri, expandedCachedHtml);
        _cache[cacheKey] = _CachedPageData(
          html: expandedCachedHtml,
          linkedCss: linkedCss,
        );
        await _persistCache();
        return BrowserPageLoadResult(
          uri: uri,
          html: expandedCachedHtml,
          linkedCss: linkedCss,
        );
      }
      return BrowserPageLoadResult(
        uri: uri,
        html: cached.html,
        linkedCss: cached.linkedCss,
      );
    }

    final rawHtml = await fetchText(uri);
    final expandedHtml = await inlineEmbeddedHtmlDocuments(
      rawHtml,
      pageUri: uri,
      depth: 0,
      activeChain: <Uri>{uri},
    );
    final linkedCss = await loadLinkedCss(uri, expandedHtml);
    _cache[cacheKey] = _CachedPageData(
      html: expandedHtml,
      linkedCss: linkedCss,
    );
    await _persistCache();
    return BrowserPageLoadResult(
      uri: uri,
      html: expandedHtml,
      linkedCss: linkedCss,
    );
  }

  @override
  Future<void> clearCache(Uri uri) async {
    await _ensureCacheLoaded();
    _cache.remove(uri.toString());
    await _persistCache();
  }

  @override
  Future<String> fetchText(
    Uri uri, {
    Uri? referer,
    bool expectPlainText = false,
  }) async {
    Exception? lastError;
    for (var attempt = 1; attempt <= _maxFetchAttempts; attempt++) {
      try {
        return await _fetchViaHeadlessWebView(
          uri,
          referer: referer,
          expectPlainText: expectPlainText,
        );
      } on _BrowserFetchHttpException catch (error) {
        lastError = error;
        final retryable =
            error.statusCode == 429 ||
            (error.statusCode >= 500 && error.statusCode <= 599);
        if (!retryable || attempt == _maxFetchAttempts) {
          break;
        }
        await Future<void>.delayed(
          error.retryAfter ?? Duration(seconds: attempt),
        );
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == _maxFetchAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } on Exception catch (error) {
        lastError = error;
        if (attempt == _maxFetchAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    if (lastError case final _BrowserFetchHttpException httpError) {
      throw HttpException('HTTP ${httpError.statusCode}', uri: uri);
    }
    throw HttpException('${lastError ?? 'Request failed'}', uri: uri);
  }

  Duration? _parseRetryAfterValue(String? rawValue) {
    final raw = rawValue?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(raw);
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    DateTime retryDate;
    try {
      retryDate = HttpDate.parse(raw);
    } on FormatException {
      return null;
    }
    final delta = retryDate.difference(DateTime.now().toUtc());
    if (delta.isNegative) {
      return Duration.zero;
    }
    return delta;
  }

  Future<String> _fetchViaHeadlessWebView(
    Uri uri, {
    Uri? referer,
    required bool expectPlainText,
  }) async {
    await waitForRequestSlot();
    final completer = Completer<String>();
    _BrowserFetchHttpException? httpException;

    final headers = <String, String>{
      'User-Agent': BrowserPageServiceMixin.browserLikeUserAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
          'image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Upgrade-Insecure-Requests': '1',
    };
    if (referer != null) {
      headers['Referer'] = referer.toString();
    }

    final webView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: BrowserPageServiceMixin.browserLikeUserAgent,
      ),
      initialUrlRequest: URLRequest(url: WebUri.uri(uri), headers: headers),
      onReceivedHttpError: (controller, request, response) async {
        final status = response.statusCode;
        if (status != null && status >= 400) {
          httpException = _BrowserFetchHttpException(
            status,
            retryAfter: _parseRetryAfterValue(
              _findHeaderIgnoreCase(response.headers, 'retry-after'),
            ),
          );
        }
      },
      onReceivedError: (controller, request, error) async {
        if (completer.isCompleted) {
          return;
        }
        completer.completeError(
          HttpException(
            'WebView load error (${error.type.name}): ${error.description}',
            uri: uri,
          ),
        );
      },
      onLoadStop: (controller, _) async {
        if (completer.isCompleted) {
          return;
        }
        if (httpException != null) {
          completer.completeError(httpException!);
          return;
        }

        try {
          final result = expectPlainText
              ? await controller.evaluateJavascript(
                  source:
                      'document.body ? document.body.innerText : document.documentElement.outerHTML;',
                )
              : await controller.getHtml();
          final text = '${result ?? ''}'.trim();
          if (text.isEmpty) {
            completer.completeError(
              HttpException('Empty response body', uri: uri),
            );
            return;
          }
          completer.complete(text);
        } catch (error) {
          completer.completeError(
            HttpException('Unable to extract content: $error', uri: uri),
          );
        }
      },
    );

    await webView.run();
    try {
      return await completer.future.timeout(_loadTimeout);
    } finally {
      await webView.dispose();
    }
  }

  String? _findHeaderIgnoreCase(Map<String, String>? headers, String key) {
    if (headers == null || headers.isEmpty) {
      return null;
    }
    final target = key.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value;
      }
    }
    return null;
  }

  Future<void> _ensureCacheLoaded() async {
    if (_cacheLoaded) {
      return;
    }
    _cacheLoaded = true;
    try {
      final file = await _cacheFile();
      if (!await file.exists()) {
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final version = decoded['version'];
      final pagesRaw = decoded['pages'];
      if (version != _cacheSchemaVersion ||
          pagesRaw is! Map<String, dynamic>) {
        return;
      }
      for (final entry in pagesRaw.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }
        final html = value['html'];
        final linkedCssRaw = value['linkedCss'];
        if (html is! String || linkedCssRaw is! Map) {
          continue;
        }
        final linkedCss = <String, String>{};
        for (final cssEntry in linkedCssRaw.entries) {
          final key = '${cssEntry.key}';
          final css = cssEntry.value;
          if (css is String) {
            linkedCss[key] = css;
          }
        }
        _cache[entry.key] = _CachedPageData(html: html, linkedCss: linkedCss);
      }
    } catch (_) {
      _cache.clear();
    }
  }

  Future<void> _persistCache() async {
    final file = await _cacheFile();
    final encoded = <String, Object?>{
      'version': _cacheSchemaVersion,
      'pages': <String, Object?>{
        for (final entry in _cache.entries)
          entry.key: <String, Object?>{
            'html': entry.value.html,
            'linkedCss': entry.value.linkedCss,
          },
      },
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(encoded), flush: true);
  }

  Future<File> _cacheFile() async {
    final root = Directory(
      '${Directory.systemTemp.path}/flutter_html_browser_cache',
    );
    return File('${root.path}/page_cache.json');
  }
}

class _BrowserFetchHttpException implements Exception {
  const _BrowserFetchHttpException(this.statusCode, {this.retryAfter});

  final int statusCode;
  final Duration? retryAfter;
}

class _CachedPageData {
  const _CachedPageData({required this.html, required this.linkedCss});

  final String html;
  final Map<String, String> linkedCss;
}
