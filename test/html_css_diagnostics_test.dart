import 'package:flutter_html_column_viewer/flutter_html_column_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logs unsupported css in debug callback pipeline', () {
    final warnings = <HtmlCssWarning>[];
    final diagnostics = HtmlCssDiagnostics(onWarning: warnings.add);
    final parser = HtmlContentParser(
      styleParser: CssStyleParser(diagnostics: diagnostics),
    );

    parser.parse('''
      <style>
        p { unsupported-prop: 1; color: #112233; }
      </style>
      <p>Hello</p>
    ''');

    expect(warnings, isNotEmpty);
    expect(warnings.any((w) => w.code == 'unsupported-property'), isTrue);
  });
}
