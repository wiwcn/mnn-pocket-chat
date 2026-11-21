import 'package:flutter_test/flutter_test.dart';
import 'package:mnn_pocket_chat/core/format.dart';

void main() {
  test('formatBytes uses binary units', () {
    expect(formatBytes(174149042), '166.1 MB');
    expect(formatBytes(512), '512 B');
  });

  test('shorten collapses newlines', () {
    expect(shorten('hello\nworld', 20), 'hello world');
  });
}
