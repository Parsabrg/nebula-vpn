import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/split_tunnel/installed_apps.dart';
import '../../core/split_tunnel/split_tunnel_controller.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../l10n/app_localizations.dart';

/// Choose which apps go around the tunnel instead of through it.
///
/// The list is of exclusions, not inclusions. A person who wants their bank's
/// app outside the tunnel wants everything else inside it, and an inclusion
/// list quietly stops covering anything installed afterwards -- so a newly
/// installed app is protected here by default, which is the safer direction
/// for a tool whose whole job is to carry traffic.
///
/// Changes apply to the next connection. Android fixes the disallow list when
/// the VpnService is established, so a running tunnel cannot be re-scoped
/// without tearing it down, and pretending otherwise would leave somebody
/// believing an app had been excluded while its traffic still went through.
class SplitTunnelScreen extends ConsumerStatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  ConsumerState<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends ConsumerState<SplitTunnelScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<InstalledApp>> apps = ref.watch(
      installedAppsProvider,
    );
    final Set<String> excluded = ref.watch(splitTunnelControllerProvider);

    final AppText text = AppText.of(context);
    return NebulaPage(
      title: text.splitTunneling,
      trailing: excluded.isEmpty
          ? null
          : NebulaButton.rowAction(
              label: text.clear,
              onPressed: () =>
                  ref.read(splitTunnelControllerProvider.notifier).clear(),
            ),
      children: <Widget>[
        const SizedBox(height: 16),
        NebulaNotice(
          text: excluded.isEmpty
              ? text.everyAppTunnelled
              : text.appsBypassTunnel(excluded.length),
          kind: NebulaNoticeKind.info,
        ),
        ...apps.when(
          loading: () => const <Widget>[
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          // Named plainly. The likely cause is a platform that has no
          // per-app routing at all, and "something went wrong" would send
          // somebody looking for a fault that is not there.
          error: (Object error, StackTrace _) => <Widget>[
            const SizedBox(height: 16),
            _Message(text: text.appsUnreadable),
          ],
          data: (List<InstalledApp> all) {
            final List<InstalledApp> visible = _matching(all, _query);
            return <Widget>[
              const SizedBox(height: 16),
              NebulaField(
                label: text.searchApps,
                hint: text.searchApps,
                prefixIcon: Icons.search,
                autocorrect: false,
                onChanged: (String value) => setState(() => _query = value),
              ),
              const SizedBox(height: 20),
              if (visible.isEmpty)
                _Message(text: text.noAppsMatch)
              else
                NebulaRowGroup(
                  children: <Widget>[
                    for (final InstalledApp app in visible)
                      _AppRow(
                        app: app,
                        excluded: excluded.contains(app.packageName),
                        onChanged: (bool value) => ref
                            .read(splitTunnelControllerProvider.notifier)
                            .setExcluded(app.packageName, excluded: value),
                      ),
                  ],
                ),
            ];
          },
        ),
      ],
    );
  }

  /// Matches the label and the package name both. People search for "gmail"
  /// but also paste "com.google.android.gm" off a support page.
  static List<InstalledApp> _matching(List<InstalledApp> all, String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return all;
    }
    return all
        .where(
          (InstalledApp app) =>
              app.label.toLowerCase().contains(needle) ||
              app.packageName.toLowerCase().contains(needle),
        )
        .toList();
  }
}

class _AppRow extends ConsumerWidget {
  const _AppRow({
    required this.app,
    required this.excluded,
    required this.onChanged,
  });

  final InstalledApp app;
  final bool excluded;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NebulaPalette palette = context.palette;
    final AsyncValue<Uint8List?> icon = ref.watch(
      appIconProvider(app.packageName),
    );

    // A checkbox, as the design draws a list of apps to pick from.
    return NebulaRow(
      title: app.label,
      subtitle: app.packageName,
      toggled: excluded,
      onTap: () => onChanged(!excluded),
      leading: SizedBox(
        width: 32,
        height: 32,
        // A missing icon leaves the space rather than collapsing the row,
        // so the list does not jump as icons arrive one at a time.
        child: icon.maybeWhen(
          data: (Uint8List? bytes) =>
              bytes == null ? null : Image.memory(bytes, gaplessPlayback: true),
          orElse: () => null,
        ),
      ),
      trailing: Icon(
        excluded ? Icons.check_box : Icons.check_box_outline_blank,
        size: 24,
        color: excluded ? palette.blue : palette.textMuted,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.textMuted),
        ),
      ),
    );
  }
}
