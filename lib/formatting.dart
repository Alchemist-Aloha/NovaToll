import 'package:timezone/timezone.dart' as tz;

const roadNames = {
  '495': 'I-495 Express Lanes',
  '66': 'I-66 · inside the Beltway',
  '66outside': 'I-66 · outside the Beltway',
  '95': 'I-95 Express Lanes',
  '395': 'I-395 Express Lanes',
};

String money(dynamic value) =>
    value is num ? '\$${value.toStringAsFixed(2)}' : '—';

String easternTime(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final local = tz.TZDateTime.from(date, tz.getLocation('America/New_York'));
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'} ${local.timeZoneName}';
}
