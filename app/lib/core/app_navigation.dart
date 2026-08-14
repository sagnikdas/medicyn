import 'package:flutter/widgets.dart';

/// Lets notification handling push routes without a BuildContext of its
/// own — it runs from a plugin callback, sometimes on a background isolate
/// with no widget tree at all, in which case [navigatorKey.currentState] is
/// simply null and any push on it is a harmless no-op.
final navigatorKey = GlobalKey<NavigatorState>();
