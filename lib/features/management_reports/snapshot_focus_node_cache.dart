import 'package:flutter/widgets.dart';

/// Owns the focus nodes used by a snapshot directory.
///
/// A directory calls [retain] after each refresh so nodes for removed
/// snapshots are disposed promptly. The cache does not create nodes for IDs
/// passed to [retain]; callers create them only when a snapshot is rendered.
final class SnapshotFocusNodeCache {
  SnapshotFocusNodeCache({this.debugLabelPrefix = 'snapshot'});

  /// Prefix used for the nodes' debug labels.
  final String debugLabelPrefix;

  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  var _disposed = false;

  /// Number of focus nodes currently retained by this cache.
  int get length => _nodes.length;

  /// Whether a focus node for [snapshotId] is currently retained.
  bool contains(String snapshotId) => _nodes.containsKey(snapshotId);

  /// Returns the stable node for [snapshotId], creating it on first use.
  ///
  /// A disposed cache cannot be reused because its former nodes have already
  /// been handed to Flutter for disposal.
  FocusNode nodeFor(String snapshotId) {
    if (_disposed) {
      throw StateError('SnapshotFocusNodeCache has been disposed');
    }
    return _nodes.putIfAbsent(
      snapshotId,
      () => FocusNode(debugLabel: '$debugLabelPrefix $snapshotId'),
    );
  }

  /// Retains nodes whose IDs occur in [snapshotIds] and disposes all others.
  ///
  /// The input is copied before pruning so callers may safely pass a view of
  /// their current directory or any other lazy iterable.
  void retain(Iterable<String> snapshotIds) {
    if (_disposed) return;

    final retainedIds = snapshotIds.toSet();
    final staleIds = _nodes.keys
        .where((snapshotId) => !retainedIds.contains(snapshotId))
        .toList();
    for (final snapshotId in staleIds) {
      final node = _nodes.remove(snapshotId);
      node?.dispose();
    }
  }

  /// Disposes and removes every retained node.
  void clear() {
    if (_disposed) return;
    _disposeNodes();
  }

  /// Releases all nodes. Repeated calls are safe.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposeNodes();
  }

  void _disposeNodes() {
    final nodes = _nodes.values.toList();
    _nodes.clear();
    for (final node in nodes) {
      node.dispose();
    }
  }
}
