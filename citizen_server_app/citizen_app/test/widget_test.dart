import 'package:citizen_app/app/app_state.dart';
import 'package:citizen_app/core/localization/strings.dart';
import 'package:flutter_test/flutter_test.dart';

// NOT YET EXECUTED: Flutter SDK was unavailable in the authoring environment.
void main() {
  test('Telugu strings fall back to English when missing', () {
    expect(const S('te')('home'), 'హోమ్');
    expect(const S('te')('does_not_exist'), 'does_not_exist');
  });

  test('draft round-trips through JSON and keeps the idempotency key', () {
    final d = Draft()
      ..categoryCode = 'pothole'
      ..description = 'Large pothole near the bus stop'
      ..lat = 16.7
      ..lng = 81.1;
    final r = Draft.fromJson(d.toJson());
    expect(r.categoryCode, 'pothole');
    expect(r.idempotencyKey, d.idempotencyKey);
    expect(r.hasLocation, isTrue);
  });
}
