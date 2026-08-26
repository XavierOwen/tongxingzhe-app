import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/snapshot_focus_node_cache.dart';

void main() {
  test('nodeFor lazily creates one stable node per snapshot ID', () {
    final cache = SnapshotFocusNodeCache(debugLabelPrefix: 'test report');

    final first = cache.nodeFor('snapshot-a');
    final sameNode = cache.nodeFor('snapshot-a');
    final second = cache.nodeFor('snapshot-b');

    expect(sameNode, same(first));
    expect(second, isNot(same(first)));
    expect(cache.length, 2);
    expect(cache.contains('snapshot-a'), isTrue);
    expect(cache.contains('snapshot-b'), isTrue);
    expect(cache.contains('snapshot-missing'), isFalse);

    cache.dispose();
  });

  test('retain disposes nodes that are not in the current directory', () {
    final cache = SnapshotFocusNodeCache();
    final stale = cache.nodeFor('stale');
    final retained = cache.nodeFor('retained');

    cache.retain(['retained', 'retained']);

    expect(cache.length, 1);
    expect(cache.contains('stale'), isFalse);
    expect(cache.nodeFor('retained'), same(retained));
    expect(() => stale.addListener(() {}), throwsA(isA<FlutterError>()));

    cache.dispose();
  });

  test('clear disposes every node and is safe to repeat', () {
    final otherCache = SnapshotFocusNodeCache();
    final first = otherCache.nodeFor('first');
    final cache = SnapshotFocusNodeCache();
    final second = cache.nodeFor('second');
    final third = cache.nodeFor('third');

    cache.clear();
    cache.clear();

    expect(cache.length, 0);
    expect(cache.contains('second'), isFalse);
    expect(cache.contains('third'), isFalse);
    expect(() => second.addListener(() {}), throwsA(isA<FlutterError>()));
    expect(() => third.addListener(() {}), throwsA(isA<FlutterError>()));

    // A node owned by another cache remains usable until that cache is cleared.
    expect(() => first.addListener(() {}), returnsNormally);
    otherCache.dispose();
    cache.dispose();
  });

  test(
    'dispose releases nodes, is idempotent, and makes nodeFor fail fast',
    () {
      final cache = SnapshotFocusNodeCache();
      final node = cache.nodeFor('snapshot-a');

      cache.dispose();
      cache.dispose();
      cache.retain(['snapshot-a']);
      cache.clear();

      expect(cache.length, 0);
      expect(cache.contains('snapshot-a'), isFalse);
      expect(() => node.addListener(() {}), throwsA(isA<FlutterError>()));
      expect(() => cache.nodeFor('snapshot-b'), throwsA(isA<StateError>()));
    },
  );
}
