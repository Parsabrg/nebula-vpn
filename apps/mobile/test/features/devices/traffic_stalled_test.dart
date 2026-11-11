import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/tunnel/tunnel_traffic.dart';
import 'package:nebula_mobile/features/devices/devices_controller.dart';

void main() {
  final DateTime t0 = DateTime(2026, 11, 11, 20);
  final TrafficMark mark = (rx: 1000, tx: 500, at: t0);

  TunnelTraffic reading(int rx, int tx) =>
      TunnelTraffic(rxBytes: rx, txBytes: tx);

  test('sending with nothing back for 15 s is a stall', () {
    expect(
      trafficStalled(
        reading(1000, 500 + 4096),
        mark,
        t0.add(const Duration(seconds: 15)),
      ),
      isTrue,
    );
  });

  test('anything received, too little sent, or too soon is not', () {
    final DateTime later = t0.add(const Duration(seconds: 30));
    expect(trafficStalled(reading(1001, 9000), mark, later), isFalse);
    expect(trafficStalled(reading(1000, 500 + 4095), mark, later), isFalse);
    expect(
      trafficStalled(
        reading(1000, 9000),
        mark,
        t0.add(const Duration(seconds: 14)),
      ),
      isFalse,
    );
    expect(trafficStalled(reading(1000, 9000), null, later), isFalse);
  });
}
