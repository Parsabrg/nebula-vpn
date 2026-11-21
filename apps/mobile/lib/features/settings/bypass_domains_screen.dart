import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/settings/advanced_settings_controller.dart';
import '../../core/settings/protection_controller.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../l10n/app_localizations.dart';

/// Websites that connect directly instead of through the VPN: a local bank
/// or service that refuses foreign addresses. Each entry covers its
/// subdomains. Applies from the next connection, to Xray protocols.
class BypassDomainsScreen extends ConsumerStatefulWidget {
  const BypassDomainsScreen({super.key});

  @override
  ConsumerState<BypassDomainsScreen> createState() =>
      _BypassDomainsScreenState();
}

class _BypassDomainsScreenState extends ConsumerState<BypassDomainsScreen> {
  final TextEditingController _field = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final bool taken = await ref
        .read(advancedSettingsControllerProvider.notifier)
        .addBypassDomain(_field.text);
    if (!mounted) {
      return;
    }
    setState(() => _invalid = !taken);
    if (taken) {
      _field.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    final AppText text = AppText.of(context);
    final List<String> domains = ref.watch(
      advancedSettingsControllerProvider.select((s) => s.bypassDomains),
    );

    return NebulaPage(
      title: text.bypassDomains,
      children: <Widget>[
        const SizedBox(height: 8),
        Text(
          text.bypassDomainsIntro,
          style: TextStyle(
            fontSize: 14,
            height: 20 / 14,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        NebulaField(
          label: text.bypassDomainsField,
          controller: _field,
          hint: 'example.com',
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          errorText: _invalid ? text.bypassDomainsInvalid : null,
          addLabel: text.bypassDomainsAdd,
          onAdd: _add,
        ),
        if (domains.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          NebulaRowGroup(
            children: <Widget>[
              for (final String domain in domains)
                NebulaRow(
                  title: domain,
                  trailing: IconButton(
                    tooltip: text.bypassDomainsRemove,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(Icons.close, size: 20, color: palette.textMuted),
                    onPressed: () => ref
                        .read(advancedSettingsControllerProvider.notifier)
                        .removeBypassDomain(domain),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(
          text.bypassDomainsNote,
          style: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            color: palette.textMuted,
          ),
        ),
        if (defaultTargetPlatform == TargetPlatform.windows &&
            ref
                .watch(protectionControllerProvider)
                .blockWhenVpnDrops) ...<Widget>[
          const SizedBox(height: 12),
          NebulaNotice(
            text: text.bypassDomainsKillSwitchWindows,
            kind: NebulaNoticeKind.warning,
          ),
        ],
      ],
    );
  }
}
