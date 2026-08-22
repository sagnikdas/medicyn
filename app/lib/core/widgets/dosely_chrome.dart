import 'package:flutter/material.dart';

import '../theme.dart';

/// Greeting copy from the Stitch Today screen, keyed off the local hour.
String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return 'Good morning,';
  if (hour < 17) return 'Good afternoon,';
  return 'Good evening,';
}

class DoselyBrandMark extends StatelessWidget {
  const DoselyBrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.medication, color: color, size: compact ? 22 : 26),
        const SizedBox(width: 8),
        Text(
          'Dosely',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 32px circle used as the top-bar avatar. Tapping it opens Profile.
class DoselyAvatarButton extends StatelessWidget {
  const DoselyAvatarButton({
    super.key,
    required this.label,
    this.onTap,
  });

  /// First letter of the signed-in email, or a generic person icon.
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = (label ?? '').trim();
    final initial = letter.isEmpty ? null : letter.substring(0, 1).toUpperCase();
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Ink(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: initial == null
              ? Icon(Icons.person, size: 18, color: scheme.onSurfaceVariant)
              : Text(
                  initial,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
        ),
      ),
    );
  }
}

class DoselyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const DoselyTopBar({
    super.key,
    this.onAvatarTap,
    this.avatarLabel,
    this.trailing,
  });

  final VoidCallback? onAvatarTap;
  final String? avatarLabel;
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
              const DoselyBrandMark(compact: true),
              const Spacer(),
              trailing ??
                  DoselyAvatarButton(label: avatarLabel, onTap: onAvatarTap),
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
        boxShadow: DoselyTheme.ambientShadow,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = fraction.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 1,
            strokeWidth: stroke,
            color: scheme.secondaryContainer,
          ),
          CircularProgressIndicator(
            value: clamped,
            strokeWidth: stroke,
            color: scheme.primary,
            strokeCap: StrokeCap.round,
          ),
          Text(
            '${(clamped * 100).round()}%',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
            ),
          ),
        ],
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
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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

class DoselyBottomNav extends StatelessWidget {
  const DoselyBottomNav({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const items = [
    (icon: Icons.calendar_today_outlined, selected: Icons.calendar_today, label: 'Today'),
    (icon: Icons.medical_services_outlined, selected: Icons.medical_services, label: 'Plan'),
    (icon: Icons.analytics_outlined, selected: Icons.analytics, label: 'Insights'),
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
    required this.onTap,
  });

  final ({IconData icon, IconData selected, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? item.selected : item.icon,
          size: 22,
          color: selected
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
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
            duration: const Duration(milliseconds: 200),
            padding: selected
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
