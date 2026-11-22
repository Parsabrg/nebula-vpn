// Writes what tool/macos_tunnel_smoke.sh needs into the folder given: the
// root helper and the app's own tunnel config around a VLESS profile to a
// local Xray server on port 18443. Run with `dart run`.
import 'dart:convert';
import 'dart:io';

import 'package:nebula_mobile/core/xray/macos_vpn_helper.dart';
import 'package:nebula_mobile/core/xray/macos_xray_tunnel.dart';

void main(List<String> args) {
  final String folder = args.single;
  File('$folder/helper.sh').writeAsStringSync(macosVpnHelperScript);
  final Map<String, dynamic> profile = <String, dynamic>{
    'log': <String, dynamic>{'loglevel': 'info'},
    'dns': <String, dynamic>{
      'servers': <String>['1.1.1.1'],
    },
    'outbounds': <Map<String, dynamic>>[
      <String, dynamic>{
        'tag': 'proxy',
        'protocol': 'vless',
        'settings': <String, dynamic>{
          'vnext': <Map<String, dynamic>>[
            <String, dynamic>{
              'address': '127.0.0.1',
              'port': 18443,
              'users': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': '9d1b7c58-2f3e-4f5a-9c33-5f2d7f0e1a11',
                  'encryption': 'none',
                },
              ],
            },
          ],
        },
      },
    ],
  };
  File(
    '$folder/client.json',
  ).writeAsStringSync(jsonEncode(macosXrayTunConfig(profile)));
}
