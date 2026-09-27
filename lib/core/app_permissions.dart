import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Phone permissions SkorX asks for, with the player's answer.
enum AppPermission { location, notifications }

enum PermissionAnswer {
  /// Not asked yet, or asked and turned down but can be asked again.
  notAsked,
  granted,

  /// Turned down for good: only the phone's Settings can change it.
  blocked,
}

/// Asking the phone for permissions. Behind an interface so widget tests
/// (which have no platform) and later platforms can swap it.
abstract class AppPermissions {
  Future<PermissionAnswer> status(AppPermission permission);

  /// Shows the system prompt; returns the answer.
  Future<PermissionAnswer> request(AppPermission permission);

  /// Opens this app's page in the phone's Settings.
  Future<void> openSettings();
}

class DeviceAppPermissions implements AppPermissions {
  const DeviceAppPermissions();

  Permission _of(AppPermission p) => switch (p) {
        AppPermission.location => Permission.locationWhenInUse,
        AppPermission.notifications => Permission.notification,
      };

  PermissionAnswer _answer(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) return PermissionAnswer.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermissionAnswer.blocked;
    return PermissionAnswer.notAsked;
  }

  @override
  Future<PermissionAnswer> status(AppPermission permission) async {
    try {
      return _answer(await _of(permission).status);
    } catch (_) {
      return PermissionAnswer.notAsked;
    }
  }

  @override
  Future<PermissionAnswer> request(AppPermission permission) async {
    try {
      return _answer(await _of(permission).request());
    } catch (_) {
      return PermissionAnswer.notAsked;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {
      // Nothing more to do; the screen still lets the player carry on.
    }
  }
}

final appPermissionsProvider = Provider<AppPermissions>((ref) => const DeviceAppPermissions());
