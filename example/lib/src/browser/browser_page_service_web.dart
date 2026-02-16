import 'dart:async';

import 'package:http/http.dart' as http;

import 'browser_page_service_base.dart';

BrowserPageServiceBase createPlatformPageService() =>
    BrowserPageServiceWeb();

class BrowserPageServiceWeb extends BrowserPageServiceBase
    with BrowserPageServiceMixin {
  BrowserPageServiceWeb();

  static const int _maxFetchAttempts = 4;
  static const Duration _loadTimeout = Duration(seconds: 25);

  final Map<String, _CachedPageData> _cache = <String, _CachedPageData>{};
  final http.Client _client = http.Client();

  @override
  void dispose() {
    _client.close();
  }

  @override
  Future<BrowserPageLoadResult> load(Uri uri) async {
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
    return BrowserPageLoadResult(
      uri: uri,
      html: expandedHtml,
      linkedCss: linkedCss,
    );
  }

  @override
  Future<void> clearCache(Uri uri) async {
    _cache.remove(uri.toString());
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
        return await _fetchViaHttp(uri, referer: referer)
            .timeout(_loadTimeout);
      } on http.ClientException catch (error) {
        lastError = error;
        if (attempt == _maxFetchAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } on _HttpStatusException catch (error) {
        lastError = error;
        final retryable =
            error.statusCode == 429 ||
            (error.statusCode >= 500 && error.statusCode <= 599);
        if (!retryable || attempt == _maxFetchAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(seconds: attempt));
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
    throw Exception('Failed to load $uri: ${lastError ?? 'Request failed'}');
  }

  Future<String> _fetchViaHttp(Uri uri, {Uri? referer}) async {
    await waitForRequestSlot();

    final headers = <String, String>{
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    if (referer != null) {
      headers['Referer'] = referer.toString();
    }

    final response = await _client.get(uri, headers: headers);
    if (response.statusCode >= 400) {
      throw _HttpStatusException(response.statusCode);
    }
    final body = response.body.trim();
    if (body.isEmpty) {
      throw Exception('Empty response body from $uri');
    }
    return body;
  }
}

class _HttpStatusException implements Exception {
  const _HttpStatusException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode';
}

class _CachedPageData {
  const _CachedPageData({required this.html, required this.linkedCss});

  final String html;
  final Map<String, String> linkedCss;
}
