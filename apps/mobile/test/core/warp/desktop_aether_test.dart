import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/warp/desktop_aether.dart';

void main() {
  test('the bridge leaves directly, ahead of every other rule', () {
    final AetherBridge bridge = AetherBridge(4242);
    final Map<String, dynamic> config = withAetherBridge(
      <String, dynamic>{
        'inbounds': <dynamic>[
          <String, dynamic>{'tag': 'tun-in'},
        ],
        'outbounds': <dynamic>[
          <String, dynamic>{'tag': 'proxy'},
        ],
        'routing': <String, dynamic>{
          'domainStrategy': 'AsIs',
          'rules': <dynamic>[
            <String, dynamic>{'outboundTag': 'proxy'},
          ],
        },
      },
      bridge,
      mark: 51888,
    );

    final List<dynamic> inbounds = config['inbounds'] as List<dynamic>;
    expect(inbounds.first, <String, dynamic>{'tag': 'tun-in'});
    final Map<String, dynamic> socks = inbounds.last as Map<String, dynamic>;
    expect(socks['listen'], '127.0.0.1');
    expect(socks['port'], 4242);
    final Map<String, dynamic> settings =
        socks['settings'] as Map<String, dynamic>;
    expect(settings['auth'], 'password');
    expect(settings['udp'], isTrue);
    expect(settings['accounts'], <Map<String, String>>[
      <String, String>{'user': bridge.user, 'pass': bridge.password},
    ]);
    expect(
      bridge.upstream,
      'socks5://${bridge.user}:${bridge.password}@127.0.0.1:4242',
    );

    final Map<String, dynamic> direct =
        (config['outbounds'] as List<dynamic>).last as Map<String, dynamic>;
    expect(direct['protocol'], 'freedom');
    expect(direct['streamSettings'], <String, dynamic>{
      'sockopt': <String, dynamic>{'mark': 51888},
    });

    final Map<String, dynamic> routing =
        config['routing'] as Map<String, dynamic>;
    expect(routing['domainStrategy'], 'AsIs');
    final List<dynamic> rules = routing['rules'] as List<dynamic>;
    expect(rules, hasLength(2));
    expect((rules.first as Map<String, dynamic>)['inboundTag'], <String>[
      socks['tag'] as String,
    ]);
    expect((rules.first as Map<String, dynamic>)['outboundTag'], direct['tag']);
  });

  test('Windows: no mark, and every bridge has its own password', () {
    final Map<String, dynamic> config = withAetherBridge(
      <String, dynamic>{},
      AetherBridge(1),
    );
    final Map<String, dynamic> direct =
        (config['outbounds'] as List<dynamic>).single as Map<String, dynamic>;
    expect(direct.containsKey('streamSettings'), isFalse);
    expect(AetherBridge(1).password, isNot(AetherBridge(1).password));
    expect(AetherBridge(1).password, hasLength(32));
  });

  test('the identity registered is the protocol in use', () {
    expect(aetherRegisterWord(<String>['--protocol', 'masque']), 'masque');
    expect(aetherRegisterWord(<String>['--protocol', 'wg']), 'wg');
    expect(aetherRegisterWord(<String>['--protocol', 'mim']), 'mim');
    expect(
      aetherRegisterWord(<String>['--protocol', 'gool', '--gool-classic']),
      'gool-classic',
    );
    expect(aetherRegisterWord(<String>[]), 'masque');
  });
}
