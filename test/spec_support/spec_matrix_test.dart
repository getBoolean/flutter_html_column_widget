import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('spec support matrix', () {
    late YamlMap matrix;

    setUpAll(() {
      final file = File('test/spec_support/spec_matrix.yaml');
      final content = file.readAsStringSync();
      matrix = loadYaml(content) as YamlMap;
    });

    test('uses only valid status values', () {
      const allowed = <String>{
        'supported',
        'partial',
        'unsupported',
        'deferred',
      };
      void validateStatuses(Object? value) {
        if (value is YamlMap) {
          for (final entry in value.entries) {
            validateStatuses(entry.value);
          }
          return;
        }
        if (value is YamlList) {
          for (final item in value) {
            validateStatuses(item);
          }
          return;
        }
        if (value is String && value != '1') {
          expect(
            allowed.contains(value),
            isTrue,
            reason: 'Unknown status: $value',
          );
        }
      }

      validateStatuses(matrix);
    });

    test('critical semantic fidelity items are tracked as supported', () {
      final htmlTags = (matrix['html'] as YamlMap)['tags'] as YamlMap;
      final cssProps = (matrix['css'] as YamlMap)['properties'] as YamlMap;
      final diagnostics = (matrix['css'] as YamlMap)['diagnostics'] as YamlMap;

      expect(htmlTags['thead'], 'supported');
      expect(htmlTags['tbody'], 'supported');
      expect(htmlTags['tfoot'], 'supported');
      expect(cssProps['border_top'], 'supported');
      expect(cssProps['border_right'], 'supported');
      expect(cssProps['border_bottom'], 'supported');
      expect(diagnostics['unsupported_css_logging_debug_only'], 'supported');
    });
  });
}
