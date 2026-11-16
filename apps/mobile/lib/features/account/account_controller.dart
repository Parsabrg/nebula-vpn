import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/account/account_repository.dart';
import '../../core/app_info.dart';
import '../../core/network/error_copy.dart';
import '../../core/settings/locale_controller.dart';

enum AccountLoadStatus { loading, failed, loaded }

/// Account and devices together.
///
/// One controller for two screens because they are two views of one thing:
/// the account header says "3 of 5" and the device list is those three, and a
/// revoke has to move both. Splitting them would mean two loads that can
/// disagree, and the disagreement would show as a count that does not match
/// the rows under it.
class AccountState {
  const AccountState({
    required this.loadStatus,
    this.account,
    this.devices = const <AccountDevice>[],
    this.loadErrorMessage,
    this.revokingDeviceId,
    this.actionErrorMessage,
  });

  static const AccountState initial = AccountState(
    loadStatus: AccountLoadStatus.loading,
  );

  final AccountLoadStatus loadStatus;
  final AccountSummary? account;
  final List<AccountDevice> devices;
  final String? loadErrorMessage;

  /// The device a revoke is in flight for, so its row can show the work
  /// without disabling the rest of the list.
  final String? revokingDeviceId;

  final String? actionErrorMessage;

  AccountState copyWith({
    AccountLoadStatus? loadStatus,
    AccountSummary? Function()? account,
    List<AccountDevice>? devices,
    String? Function()? loadErrorMessage,
    String? Function()? revokingDeviceId,
    String? Function()? actionErrorMessage,
  }) {
    return AccountState(
      loadStatus: loadStatus ?? this.loadStatus,
      account: account != null ? account() : this.account,
      devices: devices ?? this.devices,
      loadErrorMessage: loadErrorMessage != null
          ? loadErrorMessage()
          : this.loadErrorMessage,
      revokingDeviceId: revokingDeviceId != null
          ? revokingDeviceId()
          : this.revokingDeviceId,
      actionErrorMessage: actionErrorMessage != null
          ? actionErrorMessage()
          : this.actionErrorMessage,
    );
  }
}

class AccountController extends Notifier<AccountState> {
  bool _refreshing = false;

  @override
  AccountState build() => AccountState.initial;

  /// Fetches again without taking what is on screen away.
  ///
  /// For a screen that already shows the account and keeps it current: a
  /// refresh that put the spinner back would blink every time it ran, and one
  /// that turned a dropped request into an error would replace good figures
  /// with a failure over nothing. So a failed refresh keeps the last figures,
  /// and the next refresh tries again.
  Future<void> refresh() async {
    if (state.loadStatus != AccountLoadStatus.loaded) {
      return load();
    }
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    final AccountRepository repository = ref.read(accountRepositoryProvider);
    try {
      final AccountSummary account = await repository.fetchAccount();
      final List<AccountDevice> devices = await repository.listDevices();
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(account: () => account, devices: devices);
    } on Object {
      // Kept as it was. See above.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> load() async {
    state = state.copyWith(
      loadStatus: AccountLoadStatus.loading,
      loadErrorMessage: () => null,
    );
    final AccountRepository repository = ref.read(accountRepositoryProvider);
    try {
      // Sequential rather than concurrent: two requests that can fail
      // independently would leave the screen showing a header from one load
      // and rows from another, and the count would stop matching the list.
      final AccountSummary account = await repository.fetchAccount();
      final List<AccountDevice> devices = await repository.listDevices();
      state = state.copyWith(
        loadStatus: AccountLoadStatus.loaded,
        account: () => account,
        devices: devices,
        loadErrorMessage: () => null,
      );
      unawaited(_nameThisDevice(devices));
    } catch (error) {
      state = state.copyWith(
        loadStatus: AccountLoadStatus.failed,
        loadErrorMessage: () =>
            userFacingErrorMessage(error, ref.read(appTextProvider)),
      );
    }
  }

  /// Renames a device, then reloads; false if the server refused.
  Future<bool> renameDevice(String deviceId, String name) async {
    try {
      await ref.read(accountRepositoryProvider).renameDevice(deviceId, name);
      await load();
      return true;
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          actionErrorMessage: () =>
              userFacingErrorMessage(error, ref.read(appTextProvider)),
        );
      }
      return false;
    }
  }

  /// This device, still under the old "android device" name, takes its real
  /// one. Quietly: a server too old to rename answers 404, and nothing
  /// changes.
  Future<void> _nameThisDevice(List<AccountDevice> devices) async {
    final AccountDevice? me = devices
        .where((AccountDevice d) => d.isCurrent)
        .firstOrNull;
    if (me == null || !isPlaceholderDeviceName(me.name)) {
      return;
    }
    final String name = await readDeviceName();
    if (isPlaceholderDeviceName(name)) {
      return;
    }
    try {
      await ref.read(accountRepositoryProvider).renameDevice(me.id, name);
      if (ref.mounted) {
        await refresh();
      }
    } on Object {
      // An older server; the name stays as it was.
    }
  }

  /// Revokes another device, then reloads.
  ///
  /// Reloads rather than removing the row locally: revoking also changes the
  /// device count in the header, and the server is the only thing that knows
  /// whether it actually took.
  Future<void> revokeDevice(String deviceId) async {
    if (state.revokingDeviceId != null) {
      return;
    }
    state = state.copyWith(
      revokingDeviceId: () => deviceId,
      actionErrorMessage: () => null,
    );
    try {
      await ref.read(accountRepositoryProvider).revokeDevice(deviceId);
      await load();
      state = state.copyWith(revokingDeviceId: () => null);
    } catch (error) {
      state = state.copyWith(
        revokingDeviceId: () => null,
        actionErrorMessage: () =>
            userFacingErrorMessage(error, ref.read(appTextProvider)),
      );
    }
  }
}

final accountControllerProvider =
    NotifierProvider<AccountController, AccountState>(AccountController.new);

/// How often a visible account screen fetches its figures again.
///
/// Usage is measured on the server every minute, so this is about as stale as
/// the screen can get plus that.
final accountRefreshIntervalProvider = Provider<Duration>(
  (Ref ref) => const Duration(seconds: 30),
);
