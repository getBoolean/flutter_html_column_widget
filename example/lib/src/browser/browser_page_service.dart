import 'browser_page_service_base.dart';
import 'browser_page_service_stub.dart'
    if (dart.library.io) 'browser_page_service_native.dart'
    if (dart.library.js_interop) 'browser_page_service_web.dart';

export 'browser_page_service_base.dart'
    show BrowserPageLoadResult, BrowserPageServiceBase;

BrowserPageServiceBase createBrowserPageService() =>
    createPlatformPageService();
