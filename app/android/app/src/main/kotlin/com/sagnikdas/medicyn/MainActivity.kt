package com.sagnikdas.medicyn

import io.flutter.embedding.android.FlutterFragmentActivity

/// [FlutterFragmentActivity] rather than [FlutterActivity]: local_auth's
/// biometric prompt is a fragment, and a plain Activity cannot host it.
class MainActivity : FlutterFragmentActivity()
