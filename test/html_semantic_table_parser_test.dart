import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html_column_viewer/flutter_html_column_viewer.dart';

void main() {
  group('Html semantic table parsing', () {
    test('preserves table sections caption and cell spans', () {
      final parser = HtmlContentParser();
      final blocks = parser.parse('''
        <table>
          <caption>Scores</caption>
          <thead><tr><th scope="col">Name</th><th scope="col">Score</th></tr></thead>
          <tbody>
            <tr><td rowspan="2">Alice</td><td>10</td></tr>
            <tr><td colspan="1">11</td></tr>
          </tbody>
          <tfoot><tr><td colspan="2">Total</td></tr></tfoot>
        </table>
      ''');

      final table = blocks.whereType<HtmlTableBlockNode>().single;
      final model = table.tableModel;
      expect(model, isNotNull);
      expect(model!.caption, 'Scores');
      expect(model.head.rows, hasLength(1));
      expect(model.bodies, hasLength(1));
      expect(model.bodies.first.rows, hasLength(2));
      expect(model.foot.rows, hasLength(1));
      expect(model.bodies.first.rows.first.cells.first.rowSpan, 2);
      expect(model.foot.rows.first.cells.first.colSpan, 2);
    });
  });
}
