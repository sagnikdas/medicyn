import 'package:medicyn/features/care/phone_dial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a leading plus and digits', () {
    expect(dialablePhone('+91 98765 43210'), '+919876543210');
  });

  test('rejects a number too short to be worth offering Call for', () {
    expect(dialablePhone('12345'), isNull);
    expect(dialablePhone(''), isNull);
    expect(dialablePhone(null), isNull);
  });

  test('rejects letters that would open a broken dialer', () {
    expect(dialablePhone('call mum'), isNull);
  });
}
