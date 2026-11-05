import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_engine.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_sync.dart';

const DnsTunnelDetails _details = DnsTunnelDetails(
  domains: <String>['nt.example.test', 'nt.backup.test'],
  key: '0123456789abcdef0123456789abcdef',
  encryptionMethod: 5,
  serverCode: 'study-lab-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first name active, the rest standby; TCP on the given port', () {
    final String config = renderDnsTunnelConfig(_details, 41234);

    expect(config, contains('DOMAINS = ["nt.example.test"]'));
    expect(config, contains('STANDBY_DOMAINS = ["nt.backup.test"]'));
    expect(config, contains('DATA_ENCRYPTION_METHOD = 5'));
    expect(
      config,
      contains('ENCRYPTION_KEY = "0123456789abcdef0123456789abcdef"'),
    );
    expect(config, contains('PROTOCOL_TYPE = "TCP"'));
    expect(config, contains('LISTEN_IP = "127.0.0.1"'));
    expect(config, contains('LISTEN_PORT = 41234'));
    expect(config, contains('TUNNEL_MODE = "legacy"'));
  });

  test('quotes cannot break out of a TOML string', () {
    final String config = renderDnsTunnelConfig(
      const DnsTunnelDetails(
        domains: <String>['a"b'],
        key: r'k\"',
        encryptionMethod: 5,
        serverCode: 's',
      ),
      1,
    );
    expect(config, contains(r'DOMAINS = ["a\"b"]'));
    expect(config, contains(r'ENCRYPTION_KEY = "k\\\""'));
  });

  test('scan returns the resolvers the engine reports valid', () async {
    const MethodChannel channel = MethodChannel('test/dns_tunnel');
    Map<Object?, Object?>? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          sent = call.arguments as Map<Object?, Object?>;
          return <String>['1.2.3.4:53'];
        });

    final List<String> valid = await scanDnsTunnelResolvers(
      _details,
      '1.2.3.4\n5.6.7.8\n',
      channel: channel,
    );

    expect(valid, <String>['1.2.3.4:53']);
    expect(sent!['resolvers'], '1.2.3.4\n5.6.7.8\n');
    expect(sent!['config'] as String, contains('nt.example.test'));
  });
}
