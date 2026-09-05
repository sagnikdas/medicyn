import 'package:flutter/foundation.dart';

/// Navigation signal only; appointment details remain in the encrypted store.
const todayCarePayloadKey = 'todayCareReminderId';
final todayCareReminderTaps = ValueNotifier<String?>(null);

void openTodayCareReminder(String id) {
  todayCareReminderTaps.value = null;
  todayCareReminderTaps.value = id;
}
