import 'package:flutter/foundation.dart';

import 'html_css_warning.dart';

typedef HtmlCssWarningCallback = void Function(HtmlCssWarning warning);

class HtmlCssDiagnostics {
  const HtmlCssDiagnostics({this.onWarning});

  final HtmlCssWarningCallback? onWarning;

  void warn(HtmlCssWarning warning) {
    assert(() {
      debugPrint(warning.toString());
      onWarning?.call(warning);
      return true;
    }());
  }
}
