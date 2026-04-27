import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../application/auth_provider.dart';
import '../../../constants/app_strings.dart';

class SetupPinScreen extends ConsumerStatefulWidget {
  const SetupPinScreen({super.key});

  @override
  ConsumerState<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends ConsumerState<SetupPinScreen> {
  String _pin = '';
  String? _firstPin;
  bool _isConfirming = false;
  String? _error;

  String get _title =>
      _isConfirming ? AppStrings.confirmPin : AppStrings.createPin;

  void _onDigitPressed(String digit) {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });

    if (_pin.length == 4) {
      _onPinComplete();
    }
  }

  void _onDeletePressed() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _onPinComplete() async {
    if (!_isConfirming) {
      // First entry
      setState(() {
        _firstPin = _pin;
        _pin = '';
        _isConfirming = true;
      });
    } else {
      // Confirming
      if (_pin == _firstPin) {
        HapticFeedback.lightImpact();
        final success = await ref.read(authProvider.notifier).setupPin(_pin);
        if (success && mounted) {
          // Ask about biometric
          final authState = ref.read(authProvider);
          if (authState.biometricAvailable) {
            final enableBiometric = await _showBiometricDialog();
            if (enableBiometric) {
              await ref.read(authProvider.notifier).toggleBiometric(true);
            }
          }
          if (mounted) context.go('/home');
        }
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = AppStrings.pinMismatch;
          _pin = '';
          _firstPin = null;
          _isConfirming = false;
        });
      }
    }
  }

  Future<bool> _showBiometricDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  ref.read(authProvider).hasFaceId
                      ? Icons.face_outlined
                      : Icons.fingerprint,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Text('Biometric Unlock'),
              ],
            ),
            content: const Text(
              'Would you like to enable fingerprint or Face ID to unlock Dilgram?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not Now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enable'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _title,
                key: ValueKey(_title),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isConfirming
                  ? 'Re-enter your 4-digit PIN'
                  : 'Choose a 4-digit PIN to secure your memories',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 40),
            // PIN Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final isFilled = index < _pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: isFilled ? 18 : 14,
                  height: isFilled ? 18 : 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isFilled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const Spacer(flex: 1),
            // Number Pad
            _buildNumberPad(theme, isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberPad(ThemeData theme, bool isDark) {
    final buttons = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: buttons.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((label) {
                if (label.isEmpty) {
                  return const SizedBox(width: 72, height: 72);
                }
                if (label == 'del') {
                  return SizedBox(
                    width: 72,
                    height: 72,
                    child: IconButton(
                      onPressed: _onDeletePressed,
                      icon: Icon(
                        Icons.backspace_outlined,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  );
                }
                return Material(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(36),
                  child: InkWell(
                    onTap: () => _onDigitPressed(label),
                    borderRadius: BorderRadius.circular(36),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Center(
                        child: Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
