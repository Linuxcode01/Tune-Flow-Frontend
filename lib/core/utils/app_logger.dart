import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Thin logging facade.
///
/// `print` is banned by the lint rules and by common sense: it is stripped in release builds,
/// carries no context and cannot be silenced. Everything goes through here instead, and nothing is
/// emitted once [kReleaseMode] is on.
class AppLogger {
  const AppLogger._();

  static const String _name = 'TuneFlow';

  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    if (kReleaseMode) {
      return;
    }
    developer.log(message, name: _name, error: error, stackTrace: stackTrace, level: 500);
  }

  static void info(String message) {
    if (kReleaseMode) {
      return;
    }
    developer.log(message, name: _name, level: 800);
  }

  static void warn(String message, {Object? error}) {
    developer.log(message, name: _name, error: error, level: 900);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: _name, error: error, stackTrace: stackTrace, level: 1000);
  }
}
