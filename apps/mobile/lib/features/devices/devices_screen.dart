import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/account/account_repository.dart';
import '../../core/format/dates.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/widgets/nebula/nebula_surface.dart';
import '../../core/widgets/panel/panel_atoms.dart';
import '../../core/widgets/refresh_while_visible.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_controller.dart';

/// View, rename and revoke the devices on this account.
///
/// Scope is deliberately that. No connecting another device, no reading
/// another device's configuration -- a screen that can act on a device you
/// are not holding should be able to do as little as possible.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen>
    with RefreshWhileVisible<DevicesScreen> {
  // Loaded once, in initState, the list went on showing devices revoked
  // elsewhere for as long as the app stayed open. See RefreshWhileVisible.
  @override
  Duration get refreshInterval => ref.read(accountRefreshIntervalProvider);

  @override
  void refresh() {
    unawaited(ref.read(accountControllerProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final AccountState state = ref.watch(accountControllerProvider);

    ref.listen<AccountState>(accountControllerProvider, (
      AccountState? previous,
      AccountState next,
    ) {
      final String? message = next.actionErrorMessage;
      if (message != null && message != previous?.actionErrorMessage) {
        showNebulaSnackbar(context, message);
      }
    });

    return NebulaPage(
      title: text.devicesHeading,
      showBack: false,
      children: _body(context, state),
    );
  }

  List<Widget> _body(BuildContext context, AccountState state) {
    final AppText text = AppText.of(context);
    final NebulaPalette palette = context.palette;

    switch (state.loadStatus) {
      case AccountLoadStatus.loading:
        return const <Widget>[
          SizedBox(height: 16),
          _SkeletonDeviceRow(),
          _SkeletonDeviceRow(),
        ];

      case AccountLoadStatus.failed:
        return <Widget>[
          const SizedBox(height: 16),
          NebulaNotice(
            text: state.loadErrorMessage ?? text.couldNotLoadDevices,
            kind: NebulaNoticeKind.error,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: NebulaButton.text(
              label: text.ctaTryAgain,
              onPressed: () =>
                  ref.read(accountControllerProvider.notifier).load(),
            ),
          ),
        ];

      case AccountLoadStatus.loaded:
        final AccountSummary account = state.account!;
        return <Widget>[
          const SizedBox(height: 16),
          NebulaPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        text.devicesOfLimit(
                          account.devicesInUse,
                          account.deviceLimit,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      text.devicesInUseOfLimit(
                        account.devicesInUse,
                        account.deviceLimit,
                      ),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                NebulaUsageMeter(
                  fraction: account.deviceLimit <= 0
                      ? 0
                      : account.devicesInUse / account.deviceLimit,
                ),
              ],
            ),
          ),
          NebulaSectionLabel(text.devicesSignedIn),
          NebulaRowGroup(
            children: <Widget>[
              for (final AccountDevice device in state.devices)
                NebulaRow(
                  icon: _platformIcon(device.platform),
                  title: device.name,
                  subtitle: _meta(context, text, device),
                  onTap: () => _renameDevice(context, ref, device),
                  // The current device has no Revoke: revoking the device
                  // you are holding would drop your own tunnel, and the
                  // server refuses it anyway.
                  trailing: device.isCurrent
                      ? NebulaRowTrailing.badge(
                          context,
                          text.deviceThisDeviceBadge,
                        )
                      : _RevokeAction(
                          device: device,
                          busy: state.revokingDeviceId == device.id,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${text.devicesRenameHint} ${text.revokeFootnote}',
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
          const SizedBox(height: 8),
        ];
    }
  }

  /// `this device · tunnelling` or `peer on de-fra-1 · registered 2 Sep`.
  ///
  /// Says what the server actually reports. A device with no live credential
  /// says so rather than being described as connected somewhere.
  static String _meta(
    BuildContext context,
    AppText text,
    AccountDevice device,
  ) {
    final String where = device.serverCodes.isEmpty
        ? text.deviceNoPeer
        : text.devicePeerOn(device.serverCodes.join(', '));
    if (device.isCurrent) {
      return text.deviceThisDevice(where);
    }
    return text.deviceRegistered(
      where,
      formatShortDate(context, device.registeredAt),
    );
  }

  static IconData _platformIcon(String platform) {
    switch (platform) {
      case 'android':
        return Icons.smartphone;
      case 'windows':
        return Icons.laptop_windows;
      case 'linux':
        return Icons.computer;
      default:
        return Icons.devices_other;
    }
  }
}

class _RevokeAction extends ConsumerWidget {
  const _RevokeAction({required this.device, required this.busy});

  final AccountDevice device;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (busy) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.palette.textMuted,
            ),
          ),
        ),
      );
    }
    final AppText text = AppText.of(context);
    return NebulaButton.text(
      label: text.revoke,
      danger: true,
      onPressed: () async {
        final bool confirmed = await showNebulaConfirm(
          context,
          title: text.revokeDeviceQuestion(device.name),
          body: text.revokeDeviceBody,
          action: text.revoke,
          cancel: text.cancel,
          destructive: true,
        );
        if (confirmed) {
          await ref
              .read(accountControllerProvider.notifier)
              .revokeDevice(device.id);
        }
      },
    );
  }
}

class _SkeletonDeviceRow extends StatelessWidget {
  const _SkeletonDeviceRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: const Row(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SkeletonBar(width: 120, height: 14),
              SizedBox(height: 6),
              SkeletonBar(width: 168, height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for a new name for [device] and saves it.
Future<void> _renameDevice(
  BuildContext context,
  WidgetRef ref,
  AccountDevice device,
) async {
  final AppText text = AppText.of(context);
  final TextEditingController field = TextEditingController(text: device.name);
  final String? name = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => NebulaDialog(
      title: text.renameDevice,
      content: NebulaField(
        label: text.deviceNameLabel,
        controller: field,
        autofocus: true,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(80),
        ],
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        NebulaButton.secondary(
          label: text.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NebulaButton(
          label: text.save,
          onPressed: () => Navigator.of(context).pop(field.text),
        ),
      ],
    ),
  );
  field.dispose();
  final String? trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == device.name) {
    return;
  }
  await ref
      .read(accountControllerProvider.notifier)
      .renameDevice(device.id, trimmed);
}
