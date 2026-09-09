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
    required this.allergiesSevere,
    required this.conditions,
    required this.notes,
    required this.insuranceNumber,
    required this.nationalId,
    required this.healthCardNumber,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.medicines,
    required this.caregiverName,
    required this.caregiverPhone,
    required this.updatedAt,
  });

  final DateTime generatedAt;
  final String? patientName;
  final String bloodGroup;
  final String allergies;
  final bool allergiesSevere;
  final String conditions;
  final String notes;
  final String insuranceNumber;
  final String nationalId;
  final String healthCardNumber;

  /// Entered directly on the card, independent of Family sharing -- see
  /// [EmergencyInfo.emergencyContactName] for why this is separate from
  /// [caregiverName].
  final String emergencyContactName;
  final String emergencyContactPhone;
  final List<EmergencyMedicineRow> medicines;

  /// Best-effort display name for the person on the other end of the active
  /// care link, resolved the same way [caregiverPhone] is.
  final String? caregiverName;

  /// Dialable, or null if there is no active care link or it carries no
  /// number. Read from the *caregiver's* stored number, same as the Family
  /// screen's own "Call them" button.
  final String? caregiverPhone;

  /// When the emergency-info fields (blood group, allergies, conditions,
  /// notes, IDs) were last edited. Null when nothing has ever been saved.
  final DateTime? updatedAt;

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
    String? caregiverName;
    String? caregiverPhone;
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId != null) {
        final profile = await CareService.instance.profile(userId);
        patientName = _printableName(profile?.displayName);
        final link = await CareService.instance.currentLink();
        // Only the patient side of a link has a caregiver to report here --
        // otherPartyId/phoneToCall return whoever is on the other end
        // regardless of role, which for the caregiver side of a link is
        // the patient they help, not their own caregiver.
        if (link != null && link.isPatient(userId)) {
          caregiverPhone = dialablePhone(link.phoneToCall(userId));
          final otherPartyId = link.otherPartyId(userId);
          if (otherPartyId != null) {
            caregiverName = _printableName(
              await CareService.instance.displayName(otherPartyId),
            );
          }
        }
      }
    } catch (_) {
      // Best-effort: the card is still useful with just local data even
      // when the network call for the caregiver's details fails.
    }

    return EmergencyCardData(
      generatedAt: now ?? DateTime.now(),
      patientName: patientName,
      bloodGroup: info?.bloodGroup.trim() ?? '',
      allergies: info?.allergies.trim() ?? '',
      allergiesSevere: info?.allergiesSevere ?? false,
      conditions: info?.conditions.trim() ?? '',
      notes: info?.notes.trim() ?? '',
      insuranceNumber: info?.insuranceNumber.trim() ?? '',
      nationalId: info?.nationalId.trim() ?? '',
      healthCardNumber: info?.healthCardNumber.trim() ?? '',
      emergencyContactName: info?.emergencyContactName.trim() ?? '',
      emergencyContactPhone: info?.emergencyContactPhone.trim() ?? '',
      medicines: medicines,
      caregiverName: caregiverName,
      caregiverPhone: caregiverPhone,
      updatedAt: info?.updatedAt,
    );
  }
}

String? _printableName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.contains('@')) return null;
  return trimmed;
}
