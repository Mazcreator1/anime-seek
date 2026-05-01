import 'dart:async';

class FeedBus {
  static final _ctrl = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get onNewPost => _ctrl.stream;
  static void emit(Map<String, dynamic> post) => _ctrl.add(post);
}
