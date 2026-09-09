import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import 'medicyn_motion.dart';
import 'medicyn_platform.dart';

/// Greeting copy from the Stitch Today screen, keyed off the local hour.
String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return 'Good morning,';
  if (hour < 17) return 'Good afternoon,';
  return 'Good evening,';
}

class MedicynBrandMark extends StatelessWidget {
  const MedicynBrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 8 : 10),
          child: Image.asset(
            'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Medicyn',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: compact ? 24 : 26,
          ),
        ),
      ],
    );
  }
}

class MedicynTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MedicynTopBar({super.key, this.trailing});

  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0.5,
      shadowColor: const Color(0x14000000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            const MedicynBrandMark(compact: true),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The large page-identity heading shared by every primary tab: a short,
/// page-specific name at headline size, with an optional small uppercase
/// eyebrow above it and a one-line description below — the same shape
/// Today already used. Deliberately not a repeated "Medicyn" wordmark:
/// once a tab is on screen the user already knows which app they're in,
/// so the brand mark now lives only at entry points (onboarding, sign-in,
/// the label-capture flow) where nothing else has established that yet.
class MedicynPageHeading extends StatelessWidget {
  const MedicynPageHeading({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontSize: 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.4,
                  color: scheme.primary,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The system's signature container — a "page" resting on the chart's
/// linen ground. When tappable, it visibly lifts (a deeper, wider shadow)
/// the instant a finger touches it, on top of the existing 2% press-scale,
/// so touch reads as physically picking the page up before the tap
/// registers — not just a color/ripple response.
class AmbientCard extends StatefulWidget {
  const AmbientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;

  @override
  State<AmbientCard> createState() => _AmbientCardState();
}

class _AmbientCardState extends State<AmbientCard> {
  var _lifted = false;

  void _setLifted(bool value) {
    if (_lifted == value) return;
    setState(() => _lifted = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MedicynMotion.reduce(context);
    final card = AnimatedContainer(
      duration: MedicynMotion.duration(context, MedicynMotion.fast),
      curve: MedicynMotion.decelerate,
      decoration: BoxDecoration(
        color: widget.color ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _lifted
            ? MedicynTheme.liftedShadow
            : MedicynTheme.ambientShadow,
        border: widget.borderColor == null
            ? null
            : Border.all(color: widget.borderColor!),
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );
    if (widget.onTap == null) return card;
    return Listener(
      onPointerDown: reduceMotion ? null : (_) => _setLifted(true),
      onPointerUp: reduceMotion ? null : (_) => _setLifted(false),
      onPointerCancel: reduceMotion ? null : (_) => _setLifted(false),
      child: MedicynPressable(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: card,
          ),
        ),
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.fraction,
    this.size = 64,
    this.stroke = 6,
  });

  final double fraction;
  final double size;
  final double stroke;

  /// Percent text drawn in the hole of the ring (`100%` at completion).
  static String percentLabel(double fraction) =>
      '${(fraction.clamp(0.0, 1.0) * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final clamped = fraction.clamp(0.0, 1.0);
    return MedicynAnimatedValue(
      value: clamped,
      builder: (context, animated) => _paint(context, animated),
    );
  }

  Widget _paint(BuildContext context, double clamped) {
    final scheme = Theme.of(context).colorScheme;
    final box = MediaQuery.textScalerOf(context).scale(size).clamp(size, 80.0);
    // Keep the digits inside the unpainted hole, not over the stroke.
    final inner = (box - stroke * 2 - 8).clamp(16.0, box);
    return RepaintBoundary(
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CircularProgressIndicator(
                value: 1,
                strokeWidth: stroke,
                color: scheme.secondaryContainer,
              ),
            ),
            Positioned.fill(
              child: CircularProgressIndicator(
                value: clamped,
                strokeWidth: stroke,
                color: scheme.primary,
                strokeCap: StrokeCap.round,
              ),
            ),
            SizedBox(
              width: inner,
              height: inner,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  percentLabel(clamped),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileMenuRow extends StatelessWidget {
  const ProfileMenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconBackgroundColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Override the leading icon's circle, e.g. to give one row (emergency
  /// card) the app's "needs attention" red instead of every row's usual
  /// teal. Null keeps the standard secondaryContainer treatment.
  final Color? iconBackgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AmbientCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBackgroundColor ?? scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor ?? scheme.onSecondaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.outline),
        ],
      ),
    );
  }
}

class MedicynBottomNav extends StatelessWidget {
  const MedicynBottomNav({
    super.key,
    required this.index,
    required this.onChanged,
    this.profileInitial,
  });

  final int index;
  final ValueChanged<int> onChanged;

  /// A single uppercase letter for the signed-in account, or null when
  /// signed out. Never a third-party photo, so the Profile tab stays on the
  /// app's own teal-on-mint mark instead of an arbitrary, uncontrolled
  /// color on every screen.
  final String? profileInitial;

  static const items = [
    (
      icon: Icons.calendar_today_outlined,
      selected: Icons.calendar_today,
      label: 'Today',
    ),
    (
      icon: Icons.medical_services_outlined,
      selected: Icons.medical_services,
      label: 'Plan',
    ),
    (
      icon: Icons.analytics_outlined,
      selected: Icons.analytics,
      label: 'Insights',
    ),
    (icon: Icons.person_outline, selected: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isApplePlatform(context)) {
      return CupertinoTabBar(
        currentIndex: index,
        onTap: onChanged,
        activeColor: scheme.primary,
        inactiveColor: scheme.onSurfaceVariant,
        backgroundColor: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
        items: [
          for (var i = 0; i < items.length; i++)
            BottomNavigationBarItem(
              icon: _iconForItem(context, i, selected: false),
              activeIcon: _iconForItem(context, i, selected: true),
              label: items[i].label,
            ),
        ],
      );
    }

    return Material(
      color: scheme.surfaceContainer,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2B2318),
              blurRadius: 16,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              // Scaffold measures the bottom bar with maxHeight = the
              // full screen. A Center (or a Column with mainAxisSize.max)
              // inside that constraint expands to fill it, the bar eats
              // the body, and Today renders as a blank page with the
              // icons floating in the middle.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItem(
                      item: items[i],
                      selected: i == index,
                      profileInitial: i == 3 ? profileInitial : null,
                      onTap: () => onChanged(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconForItem(
    BuildContext context,
    int index, {
    required bool selected,
  }) {
    final item = items[index];
    final initial = index == 3 ? profileInitial : null;
    if (initial == null) {
      return Icon(selected ? item.selected : item.icon);
    }
    return _InitialAvatar(initial: initial, diameter: 22);
  }
}

/// The app's own avatar mark: a single initial on the same
/// secondaryContainer/onSecondaryContainer pairing Settings uses for its
/// profile hero, so identity never introduces a color the design system
/// doesn't already own.
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    super.key,
    required this.initial,
    required this.diameter,
  });

  final String initial;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(
            initial,
            maxLines: 1,
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    this.profileInitial,
    required this.onTap,
  });

  final ({IconData icon, IconData selected, String label}) item;
  final bool selected;
  final String? profileInitial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: MedicynMotion.duration(context, MedicynMotion.fast),
          switchInCurve: MedicynMotion.decelerate,
          child: profileInitial == null
              ? Icon(
                  selected ? item.selected : item.icon,
                  key: ValueKey<bool>(selected),
                  size: 22,
                  color: color,
                )
              : _InitialAvatar(
                  key: const ValueKey('profile-initial'),
                  initial: profileInitial!,
                  diameter: 22,
                ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedDefaultTextStyle(
            duration: MedicynMotion.duration(context, MedicynMotion.fast),
            curve: MedicynMotion.decelerate,
            style:
                Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color) ??
                TextStyle(color: color),
            child: Text(item.label, maxLines: 1),
          ),
        ),
      ],
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: Alignment.topCenter,
          // Without heightFactor, Align (and Center) expand to the max
          // height Scaffold offers the bottom bar — the full screen.
          heightFactor: 1,
          child: AnimatedContainer(
            duration: MedicynMotion.duration(context, MedicynMotion.fast),
            curve: MedicynMotion.decelerate,
            padding: selected
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
