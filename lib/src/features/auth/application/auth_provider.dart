import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import '../../../services/api_service.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.read(apiServiceProvider)),
);

enum AuthStatus { unknown, needsSetup, locked, authenticated }

class AuthState {
  final AuthStatus status;
  final bool biometricEnabled;
  final bool biometricAvailable;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.biometricEnabled = false,
    this.biometricAvailable = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    bool? biometricEnabled,
    bool? biometricAvailable,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api) : super(const AuthState()) {
    _init();
  }

  final ApiService _api;
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  static const _pinKey = 'user_pin_hash';
  static const _saltKey = 'user_pin_salt';
  static const _biometricKey = 'biometric_enabled';
  static const _defaultPin = '3456';

  Future<void> _init() async {
    final hasPin = await _storage.read(key: _pinKey);
    final biometricEnabled = await _storage.read(key: _biometricKey);

    bool biometricAvailable = false;
    try {
      biometricAvailable =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {}

    // Auto-setup default PIN on first launch
    if (hasPin == null) {
      final salt = _generateSalt();
      final hash = _hashPin(_defaultPin, salt);
      await _storage.write(key: _saltKey, value: salt);
      await _storage.write(key: _pinKey, value: hash);
      // Also setup PIN on backend
      _setupBackendPin(_defaultPin);
    }

    state = state.copyWith(
      status: AuthStatus.locked,
      biometricEnabled: (biometricEnabled == 'true'),
      biometricAvailable: biometricAvailable,
    );
  }

  /// Try to setup or verify PIN on backend to get JWT token.
  /// Failures are silently ignored — backend may be unreachable.
  Future<void> _setupBackendPin(String pin) async {
    try {
      final result = await _api.setupPin(pin);
      final token = result['token'] as String?;
      if (token != null) {
        await _api.setToken(token);
      }
    } catch (_) {
      // Backend not reachable — will retry on verify
    }
  }

  Future<void> _fetchBackendToken(String pin) async {
    try {
      // Try verify first, if PIN not set up on backend, try setup
      try {
        final result = await _api.verifyPin(pin);
        final token = result['token'] as String?;
        if (token != null) {
          await _api.setToken(token);
        }
      } catch (_) {
        // Maybe PIN not set on backend yet, try setup
        final result = await _api.setupPin(pin);
        final token = result['token'] as String?;
        if (token != null) {
          await _api.setToken(token);
        }
      }
    } catch (_) {
      // Backend not reachable — uploads won't work but app still functions
    }
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return crypto.sha256.convert(bytes).toString();
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  Future<bool> setupPin(String pin) async {
    try {
      final salt = _generateSalt();
      final hash = _hashPin(pin, salt);
      await _storage.write(key: _saltKey, value: salt);
      await _storage.write(key: _pinKey, value: hash);
      state = state.copyWith(status: AuthStatus.authenticated, error: null);
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to setup PIN');
      return false;
    }
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final storedHash = await _storage.read(key: _pinKey);
      final salt = await _storage.read(key: _saltKey);
      if (storedHash == null || salt == null) return false;

      final hash = _hashPin(pin, salt);
      if (hash == storedHash) {
        state = state.copyWith(status: AuthStatus.authenticated, error: null);
        // Get JWT token from backend in background
        _fetchBackendToken(pin);
        return true;
      } else {
        state = state.copyWith(error: 'Wrong PIN');
        return false;
      }
    } catch (e) {
      state = state.copyWith(error: 'Verification failed');
      return false;
    }
  }

  Future<bool> authenticateWithBiometric() async {
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Unlock Dilgram with biometrics',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (didAuthenticate) {
        state = state.copyWith(status: AuthStatus.authenticated, error: null);
        // Try to get JWT using the default PIN for biometric unlock
        _fetchBackendToken(_defaultPin);
      }
      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  Future<void> toggleBiometric(bool enabled) async {
    await _storage.write(key: _biometricKey, value: enabled.toString());
    state = state.copyWith(biometricEnabled: enabled);
  }

  Future<bool> changePin(String oldPin, String newPin) async {
    final verified = await _verifyPinOnly(oldPin);
    if (!verified) {
      state = state.copyWith(error: 'Current PIN is incorrect');
      return false;
    }

    final salt = _generateSalt();
    final hash = _hashPin(newPin, salt);
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _pinKey, value: hash);
    state = state.copyWith(error: null);
    return true;
  }

  Future<bool> _verifyPinOnly(String pin) async {
    final storedHash = await _storage.read(key: _pinKey);
    final salt = await _storage.read(key: _saltKey);
    if (storedHash == null || salt == null) return false;
    return _hashPin(pin, salt) == storedHash;
  }

  void lock() {
    state = state.copyWith(status: AuthStatus.locked, error: null);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> clearAllData() async {
    await _storage.deleteAll();
    state = const AuthState(status: AuthStatus.needsSetup);
  }
}
