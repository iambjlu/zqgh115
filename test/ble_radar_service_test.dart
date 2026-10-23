import 'package:flutter_test/flutter_test.dart';
import 'package:chc115/models/simulation_values.dart';
import 'package:chc115/services/ble_radar_service.dart';
void main() {
  const base = SimulationValues.empty;
  test('decodes firmware CSV without newline', () {
    final v = BleRadarService.parse('1,3,0,1,0,0,0', base)!;
    expect(v.leftDistance, 30);
    expect(v.rightDistance, 5);
    expect(v.leftApproaching, false);
    expect(v.rightApproaching, true);
    expect(v.frontCenter, FrontHazard.none);
    expect(v.bikeSpeed, base.bikeSpeed);
  });
  test('all twelve firmware phases have matching flags', () {
    for (var t = 0; t < 12; t++) {
      final left = t < 4 ? 1 : (t < 8 ? 2 : 3);
      final right = 3 - ((t ~/ 3) % 3);
      final packet = '$left,$right,${left == 3 ? 1 : 0},${right == 3 ? 1 : 0},'
          '${t == 3 ? 1 : (t == 9 ? 2 : 0)},${t == 6 || t == 7 ? 1 : 0},${t == 10 ? 3 : 0}';
      final v = BleRadarService.parse(packet, base)!;
      expect(v.frontLeft, t == 3 ? FrontHazard.pothole : (t == 9 ? FrontHazard.obstacle : FrontHazard.none));
      expect(v.frontCenter, t == 6 || t == 7 ? FrontHazard.pothole : FrontHazard.none);
      expect(v.frontRight, t == 10 ? FrontHazard.both : FrontHazard.none);
    }
  });
  test('rejects partial, combined, malformed and sensor-error packets', () {
    for (final packet in ['', '1,3,0', '1,3,0,1,0,0,0,0',
      '1,3,2,1,0,0,0', '4,3,0,1,0,0,0', '1,9,0,1,0,0,0',
      '1,3,0,1,9,0,0', 'x,3,0,1,0,0,0',
      '1,3,0,1,0,0,0\n1,3,0,1,0,0,0']) {
      expect(BleRadarService.parse(packet, base), isNull, reason: packet);
    }
  });
  test('distance 0 means no vehicle (distinct from far)', () {
    final v = BleRadarService.parse('0,0,0,0,1,0,0', base)!;
    expect(v.leftDistance, 99);
    expect(v.rightDistance, 99);
    expect(v.frontLeft, FrontHazard.pothole);
  });
  test('front codes 2 (obstacle) and 3 (both) are decoded, 4 is rejected', () {
    final v = BleRadarService.parse('1,1,0,0,2,3,1', base)!;
    expect(v.frontLeft, FrontHazard.obstacle);
    expect(v.frontCenter, FrontHazard.both);
    expect(v.frontRight, FrontHazard.pothole);
    expect(BleRadarService.parse('1,1,0,0,4,0,0', base), isNull);
  });
  test('front codes 2 (obstacle) and 3 (both) are decoded, 4 is rejected', () {
    final v = BleRadarService.parse('1,1,0,0,2,3,1', base)!;
    expect(v.frontLeft, FrontHazard.obstacle);
    expect(v.frontCenter, FrontHazard.both);
    expect(v.frontRight, FrontHazard.pothole);
    expect(BleRadarService.parse('1,1,0,0,4,0,0', base), isNull);
  });
  test('accepts whitespace and compact legacy packet', () {
    expect(BleRadarService.parse(' 2,1,1,0,1,0,1\r\n', base), isNotNull);
    expect(BleRadarService.parse('2110101', base), isNotNull);
  });
}
