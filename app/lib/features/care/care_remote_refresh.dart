import 'package:flutter/foundation.dart';

/// Pokes caregiver-side screens that read the patient's rows from Supabase
/// rather than Drift. A `data_changed` push still runs [applyRemoteDataChange],
/// which pulls the *signed-in* user's medicines — for a caregiver those are
/// the wrong rows. This is the refresh those screens actually need.
class CareRemoteRefresh extends ChangeNotifier {
  CareRemoteRefresh._();
  static final CareRemoteRefresh instance = CareRemoteRefresh._();

  void ping() => notifyListeners();
}
