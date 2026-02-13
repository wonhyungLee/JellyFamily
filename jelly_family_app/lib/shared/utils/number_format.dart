String formatIntWithCommas(int value) {
  final sign = value < 0 ? '-' : '';
  var digits = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i += 1) {
    final indexFromEnd = digits.length - i;
    out.write(digits[i]);
    if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
      out.write(',');
    }
  }
  return '$sign${out.toString()}';
}

String formatWon(int value) => '${formatIntWithCommas(value)}원';

