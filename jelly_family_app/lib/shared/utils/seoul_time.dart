String twoDigits(int value) => value.toString().padLeft(2, '0');

DateTime seoulNow() {
  return DateTime.now().toUtc().add(const Duration(hours: 9));
}

String seoulDateString([int offsetDays = 0]) {
  final now = seoulNow();
  final base =
      DateTime.utc(now.year, now.month, now.day).add(Duration(days: offsetDays));
  return '${base.year}-${twoDigits(base.month)}-${twoDigits(base.day)}';
}

String seoulYearMonth() {
  final now = seoulNow();
  return '${now.year}-${twoDigits(now.month)}';
}

