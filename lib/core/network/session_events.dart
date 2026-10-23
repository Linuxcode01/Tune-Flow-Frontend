import 'dart:async';

/// Signals raised by the network layer that the presentation layer must react to.
enum SessionEvent {
  /// The refresh token was rejected; the user has to sign in again.
  expired,

  /// The user signed out deliberately.
  signedOut,
}

/// A tiny broadcast bus between the Dio interceptor (infrastructure) and the auth controller
/// (presentation).
///
/// The interceptor cannot depend on Riverpod, and the auth controller must not poll the keystore,
/// so they meet here. Only two events exist, which is the entire reason a plain enum is enough.
class SessionEvents {
  final StreamController<SessionEvent> _controller =
      StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get stream => _controller.stream;

  void emit(SessionEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}
