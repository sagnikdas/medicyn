import '../../features/auth/auth_service.dart';
import '../../features/care/care_service.dart';
import '../../features/care/phone_dial.dart';
import '../../features/reminders_home/reminder_copy.dart';
import '../local/database.dart';

/// One row of the "current medicines" list on the emergency card -- title
/// and dose only. Schedule timing is deliberately left off: a first
/// responder needs to know what's in the bag, not when the next dose is due.
class EmergencyMedicineRow {
  const EmergencyMedicineRow({required this.title, required this.dose});

  final String title;
  final String dose;
}

/// Everything the emergency card shows, gathered in one place so the
/// on-screen view and the printable PDF read from the same snapshot.
class EmergencyCardData {
  const EmergencyCardData({
    required this.generatedAt,
    required this.patientName,
    required this.bloodGroup,
    required this.allergies,
    required this.conditions,
    required this.medicines,
    required this.caregiverPhone,
  });

  final DateTime generatedAt;
  final String? patientName;
  final String bloodGroup;
  final String allergies;
  final String conditions;
  final List<EmergencyMedicineRow> medicines;

  /// Dialable, or null if there is no active care link or it carries no
  /// number. Read from the *caregiver's* stored number, same as the Family
  /// screen's own "Call them" button.
  final String? caregiverPhone;

  static Future<EmergencyCardData> fromDatabase(
    AppDatabase db, {
    DateTime? now,
  }) async {
    final info = await db.emergencyInfoOnce();
    final schedules = await db.activeSchedulesOnce();
    final medicines = [
      for (final item in schedules)
        EmergencyMedicineRow(
          title: medicineTitle(item.medicine),
          dose: item.medicine.doseAmount.trim(),
        ),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    String? patientName;
    String? caregiverPhone;
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId != null) {
        final profile = await CareService.instance.profile(userId);
        patientName = _printableName(profile?.displayName);
        final link = await CareService.instance.currentLink();
        caregiverPhone = dialablePhone(link?.phoneToCall(userId));
      }
    } catch (_) {
      // Best-effort: the card is still useful with just local data even
      // when the network call for the caregiver's number fails.
    }

    return EmergencyCardData(
      generatedAt: now ?? DateTime.now(),
      patientName: patientName,
      bloodGroup: info?.bloodGroup.trim() ?? '',
      allergies: info?.allergies.trim() ?? '',
      conditions: info?.conditions.trim() ?? '',
      medicines: medicines,
      caregiverPhone: caregiverPhone,
    );
  }
}

String? _printableName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.contains('@')) return null;
  return trimmed;
}
