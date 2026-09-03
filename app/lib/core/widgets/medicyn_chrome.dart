import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import 'medicyn_motion.dart';

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

class AmbientCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: MedicynTheme.ambientShadow,
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return MedicynPressable(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: card,
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.onSecondaryContainer),
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
    this.profileImageUrl,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final String? profileImageUrl;

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
    return Material(
      color: scheme.surfaceContainer,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A00685F),
              blurRadius: 12,
              offset: Offset(0, -4),
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
                      profileImageUrl: i == 3 ? profileImageUrl : null,
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
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    this.profileImageUrl,
    required this.onTap,
  });

  final ({IconData icon, IconData selected, String label}) item;
  final bool selected;
  final String? profileImageUrl;
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
          child: profileImageUrl == null
              ? Icon(
                  selected ? item.selected : item.icon,
                  key: ValueKey<bool>(selected),
                  size: 22,
                  color: color,
                )
              : ClipOval(
                  key: const ValueKey('profile-image'),
                  child: Image.network(
                    profileImageUrl!,
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      selected ? item.selected : item.icon,
                      size: 22,
                      color: color,
                    ),
                  ),
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
