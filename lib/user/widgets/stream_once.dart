import 'package:flutter/widgets.dart';

/// A [StreamBuilder] that creates its stream ONCE, not on every rebuild.
///
/// Writing `StreamBuilder(stream: Repo.watchX(), ...)` inside `build()`
/// opens a brand-new Firestore listener each time the screen rebuilds
/// (every keystroke in a search box, every carousel swipe, every scroll
/// threshold). Each new listener re-downloads the documents — including the
/// big base64 package photos — and flashes the UI back to "loading". That
/// is what made the customer app feel heavy.
///
/// [create] runs when the widget first appears. If the data the stream is
/// for changes (a different user, a different booking), pass it as
/// [identity] and the stream is recreated only then.
class StreamOnce<T> extends StatefulWidget {
  final Stream<T> Function() create;
  final AsyncWidgetBuilder<T> builder;
  final Object? identity;

  const StreamOnce({super.key, required this.create, required this.builder, this.identity});

  @override
  State<StreamOnce<T>> createState() => _StreamOnceState<T>();
}

class _StreamOnceState<T> extends State<StreamOnce<T>> {
  late Stream<T> _stream = widget.create();

  @override
  void didUpdateWidget(StreamOnce<T> old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity) _stream = widget.create();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(stream: _stream, builder: widget.builder);
}
