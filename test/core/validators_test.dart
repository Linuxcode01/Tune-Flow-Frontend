import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/utils/validators.dart';

/// The client validators must mirror the backend's Bean Validation rules, otherwise a user fills in a
/// valid-looking form and still gets a 400. These tests pin that contract.
void main() {
  group('Validators.email', () {
    test('accepts an ordinary address', () {
      expect(Validators.email('listener@tuneflow.dev'), isNull);
      expect(Validators.email('first.last+tag@sub.domain.co.in'), isNull);
    });

    test('rejects empty and malformed addresses', () {
      expect(Validators.email(''), 'Email is required');
      expect(Validators.email(null), 'Email is required');
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('missing@tld'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('accepts a password with a letter and a digit', () {
      expect(Validators.password('Password123'), isNull);
    });

    test('rejects short passwords', () {
      expect(Validators.password('Ab1'), 'Password must be at least 8 characters');
    });

    test('rejects letters-only and digits-only passwords', () {
      expect(
        Validators.password('passwordonly'),
        'Password must contain at least one letter and one digit',
      );
      expect(
        Validators.password('1234567890'),
        'Password must contain at least one letter and one digit',
      );
    });
  });

  group('Validators.confirmPassword', () {
    test('requires a match', () {
      expect(Validators.confirmPassword('Password123', 'Password123'), isNull);
      expect(Validators.confirmPassword('Password124', 'Password123'), 'Passwords do not match');
      expect(Validators.confirmPassword('', 'Password123'), 'Confirm your password');
    });
  });

  group('Validators.name and playlistName', () {
    test('enforces the API length bounds', () {
      expect(Validators.name('Aria'), isNull);
      expect(Validators.name('A'), 'Name must be at least 2 characters');
      expect(Validators.name('  '), 'Name is required');
      expect(Validators.playlistName('Late Night Drive'), isNull);
      expect(Validators.playlistName(''), 'Playlist name is required');
    });
  });
}
