import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/admin/widgets/pagination_bar.dart';

void main() {
  test('pageCount', () {
    expect(PageWindow.pageCount(0), 1);
    expect(PageWindow.pageCount(15), 1);
    expect(PageWindow.pageCount(16), 2);
  });

  test('clamp pulls the page back when the list shrinks', () {
    expect(PageWindow.clamp(5, 20), 1);
    expect(PageWindow.clamp(-1, 20), 0);
  });

  test('slice returns the right window', () {
    final items = List.generate(20, (i) => i);
    expect(PageWindow.slice(items, 0), items.sublist(0, 15));
    expect(PageWindow.slice(items, 1), items.sublist(15));
    expect(PageWindow.slice(items, 3), isEmpty);
  });
}
