import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Status chips for one calendar day. Booleans, not counts — the parent
/// already rolled the day's doses up. Dots and semantics both read this.
class CalendarDayMarks {
  const CalendarDayMarks({
    this.taken = false,
    this.pending = false,
    this.missed = false,
    this.snoozed = false,
    this.notRecorded = false,
  });

  final bool taken;
  final bool pending;
  final bool missed;
  final bool snoozed;
  final bool notRecorded;

  bool get isEmpty => !taken && !pending && !missed && !snoozed && !notRecorded;
}

const _takenDot = Color(0xFF00685F);
const _pendingDot = Color(0xFF3D6FA8);

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// Layout the collapsing sliver has to share with the painted calendar.
/// Keep these in lockstep with [_Header], weekday row, and [_DayCell].
class DoseCalendarMetrics {
  DoseCalendarMetrics._();

  static const _baseRow = 48.0;
  static const _baseCircle = 36.0;
  static const _rowExtra = 12.0; // cell padding + dots
  static const _actionRow = 48.0;
  static const _gaps = 12.0; // 8 above weekdays + 4 below
  static const _weekdayFont = 12.0;
  static const _weekdayHeight = 16 / 12;

  /// Comfortable density, matching [DoselyTheme]. Callers with another
  /// density should pass [densityDy] from `visualDensity.baseSizeAdjustment`.
  static const _comfortableDensityDy = -4.0;

  static double dayCircle(TextScaler scaler) =>
      math.max(_baseCircle, scaler.scale(_baseCircle));

  static double rowHeight({
    TextScaler textScaler = const TextScaler.linear(1.0),
  }) => math.max(_baseRow, dayCircle(textScaler) + _rowExtra);

  static double chromeHeight({
    TextScaler textScaler = const TextScaler.linear(1.0),
    double densityDy = _comfortableDensityDy,
  }) {
    final iconRow = 48.0 + densityDy;
    final weekday = textScaler.scale(_weekdayFont) * _weekdayHeight;
    return iconRow + _actionRow + _gaps + weekday;
  }

  static int weekCount({required bool month, required DateTime anchor}) {
    return _calendarDays(month: month, anchor: _dateOnly(anchor)).length ~/ 7;
  }

  static double extent({
    required bool month,
    required DateTime anchor,
    TextScaler textScaler = const TextScaler.linear(1.0),
    double densityDy = _comfortableDensityDy,
  }) {
    return (chromeHeight(textScaler: textScaler, densityDy: densityDy) +
            rowHeight(textScaler: textScaler) *
                weekCount(month: month, anchor: anchor))
        .ceilToDouble();
  }

  static double extentOf(
    BuildContext context, {
    required bool month,
    required DateTime anchor,
  }) {
    return extent(
      month: month,
      anchor: anchor,
      textScaler: MediaQuery.textScalerOf(context),
      densityDy: Theme.of(context).visualDensity.baseSizeAdjustment.dy,
    );
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Sunday of the week containing [day]. Matches the rest of the app, where
/// stored weekdays are 0 = Sunday (Dart's `weekday` is Monday = 1).
DateTime _startOfWeek(DateTime day) {
  final d = _dateOnly(day);
  return DateTime(d.year, d.month, d.day - (d.weekday % 7));
}

List<DateTime> _calendarDays({required bool month, required DateTime anchor}) {
  final a = _dateOnly(anchor);
  if (!month) {
    final start = _startOfWeek(a);
    return [
      for (var i = 0; i < 7; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
  }
  final first = DateTime(a.year, a.month, 1);
  final last = DateTime(a.year, a.month + 1, 0);
  final start = _startOfWeek(first);
  final lastWeek = _startOfWeek(last);
  final end = DateTime(lastWeek.year, lastWeek.month, lastWeek.day + 6);
  return [
    for (
      var d = start;
      !d.isAfter(end);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];
}

/// Week-first calendar for the home screen. Collapsed it is one Sunday–
/// Saturday row so a dose list still fits on a small phone; Month expands
/// it to a grid that includes the leading/trailing days of adjacent months.
class DoseCalendar extends StatefulWidget {
  const DoseCalendar({
    super.key,
    required this.selectedDay,
    required this.now,
    required this.marks,
    required this.onSelectDay,
    this.forceWeekView = false,
    this.monthExpanded,
    this.onMonthExpandedChanged,
    this.collapseProgress = 0,
  });

  /// Date-only preferred; the widget normalizes to year/month/day.
  final DateTime selectedDay;
  final DateTime now;

  /// Keys should be date-only. A key that still has a time is looked up
  /// via `DateTime(y, m, d)` so a forgetful caller still matches.
  final Map<DateTime, CalendarDayMarks> marks;

  final ValueChanged<DateTime> onSelectDay;

  /// When true, never expand to month. Tests and extreme layouts pass this;
  /// normal large text still shows Today / Month.
  final bool forceWeekView;

  /// When set, the parent owns month vs week. Used so a collapsing scroll
  /// can shrink the month grid without fighting this widget's own toggle.
  final bool? monthExpanded;
  final ValueChanged<bool>? onMonthExpandedChanged;

  /// 0 = full month, 1 = only the selected week. Ignored in week view.
  /// The home sliver drives this from [Scrollable] shrink offset.
  final double collapseProgress;

  @override
  State<DoseCalendar> createState() => _DoseCalendarState();
}

class _DoseCalendarState extends State<DoseCalendar> {
  late DateTime _anchor;
  bool _localMonthExpanded = false;

  bool get _monthExpanded => widget.monthExpanded ?? _localMonthExpanded;

  void _setMonthExpanded(bool value) {
    if (widget.monthExpanded != null) {
      widget.onMonthExpandedChanged?.call(value);
      return;
    }
    setState(() => _localMonthExpanded = value);
  }

  @override
  void initState() {
    super.initState();
    _anchor = _dateOnly(widget.selectedDay);
  }

  @override
  void didUpdateWidget(DoseCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent changed the selected day (Today, a deep link) or the clock
    // crossed midnight — jump the visible range to contain selection.
    if (!_sameDay(widget.selectedDay, oldWidget.selectedDay) ||
        !_sameDay(widget.now, oldWidget.now)) {
      _anchor = _dateOnly(widget.selectedDay);
    }
  }

  bool get _weekOnly => widget.forceWeekView;

  bool _showingWeek() => _weekOnly || !_monthExpanded;

  List<DateTime> _visibleDays(bool week) =>
      _calendarDays(month: !week, anchor: _anchor);

  Map<DateTime, CalendarDayMarks> _indexedMarks() {
    return {for (final e in widget.marks.entries) _dateOnly(e.key): e.value};
  }

  void _shift(int step, bool week) {
    setState(() {
      if (week) {
        _anchor = DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * step);
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + step);
      }
    });
  }

  void _goToday() {
    final today = _dateOnly(widget.now);
    setState(() => _anchor = today);
    widget.onSelectDay(today);
  }

  @override
  Widget build(BuildContext context) {
    final weekOnly = _weekOnly;
    final week = _showingWeek();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final marks = _indexedMarks();
    final days = _visibleDays(week);
    final today = _dateOnly(widget.now);
    final selected = _dateOnly(widget.selectedDay);
    final visibleMonth = _anchor.month;
    final todayWeekday = today.weekday % 7;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          title: '${_months[_anchor.month - 1]} ${_anchor.year}',
          week: week,
          showMonthToggle: !weekOnly,
          monthExpanded: _monthExpanded,
          onPrevious: () => _shift(-1, week),
          onNext: () => _shift(1, week),
          onToday: _goToday,
          onToggleMonth: () => _setMonthExpanded(!_monthExpanded),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  _weekdayLetters[i],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: i == todayWeekday
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _WeekGrid(
          days: days,
          week: week,
          selected: selected,
          today: today,
          visibleMonth: visibleMonth,
          marks: marks,
          onSelect: widget.onSelectDay,
          collapseProgress: week ? 0 : widget.collapseProgress.clamp(0.0, 1.0),
        ),
      ],
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.days,
    required this.week,
    required this.selected,
    required this.today,
    required this.visibleMonth,
    required this.marks,
    required this.onSelect,
    required this.collapseProgress,
  });

  final List<DateTime> days;
  final bool week;
  final DateTime selected;
  final DateTime today;
  final int visibleMonth;
  final Map<DateTime, CalendarDayMarks> marks;
  final ValueChanged<DateTime> onSelect;
  final double collapseProgress;

  CalendarDayMarks _marksOn(DateTime day) =>
      marks[_dateOnly(day)] ?? const CalendarDayMarks();

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (var i = 0; i < days.length; i += 7)
        Row(
          children: [
            for (final day in days.sublist(i, i + 7))
              Expanded(
                child: _DayCell(
                  day: day,
                  selected: _sameDay(day, selected),
                  isToday: _sameDay(day, today),
                  outsideMonth: !week && day.month != visibleMonth,
                  marks: _marksOn(day),
                  onSelect: onSelect,
                ),
              ),
          ],
        ),
    ];
    if (week || collapseProgress <= 0 || rows.length <= 1) {
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    }

    final weekCount = rows.length;
    var selectedWeek = 0;
    for (var w = 0; w < weekCount; w++) {
      final slice = days.sublist(w * 7, w * 7 + 7);
      if (slice.any((d) => _sameDay(d, selected))) {
        selectedWeek = w;
        break;
      }
    }
    final heightFactor =
        (weekCount - collapseProgress * (weekCount - 1)) / weekCount;
    final alignmentY = weekCount == 1
        ? 0.0
        : -1.0 + 2.0 * (selectedWeek / (weekCount - 1));

    return ClipRect(
      child: Align(
        alignment: Alignment(0, alignmentY),
        heightFactor: heightFactor,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.week,
    required this.showMonthToggle,
    required this.monthExpanded,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onToggleMonth,
  });

  final String title;
  final bool week;
  final bool showMonthToggle;
  final bool monthExpanded;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onToggleMonth;

  @override
  Widget build(BuildContext context) {
    // Two rows so "Month" is never clipped to "Mcnth" by sharing a row
    // with the title, chevrons, and Today on a narrow phone.
    final scaler = MediaQuery.textScalerOf(context);
    final actionMinH = math.max(40.0, scaler.scale(14) + 16);
    final actionStyle = TextButton.styleFrom(
      minimumSize: Size(64, actionMinH),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: week ? 'Previous week' : 'Previous month',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: week ? 'Next week' : 'Next month',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            TextButton(
              style: actionStyle,
              onPressed: onToday,
              child: const Text('Today', maxLines: 1),
            ),
            const Spacer(),
            if (showMonthToggle)
              TextButton(
                style: actionStyle,
                onPressed: onToggleMonth,
                child: Text(monthExpanded ? 'Week' : 'Month', maxLines: 1),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.outsideMonth,
    required this.marks,
    required this.onSelect,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool outsideMonth;
  final CalendarDayMarks marks;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final Color numberColor;
    if (selected) {
      numberColor = scheme.onPrimary;
    } else if (outsideMonth) {
      numberColor = scheme.outline;
    } else if (isToday) {
      numberColor = scheme.primary;
    } else {
      numberColor = scheme.onSurface;
    }

    final scaler = MediaQuery.textScalerOf(context);
    final circle = DoseCalendarMetrics.dayCircle(scaler);
    final rowH = DoseCalendarMetrics.rowHeight(textScaler: scaler);

    return Semantics(
      button: true,
      selected: selected,
      label: _daySemanticsLabel(day, marks),
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onSelect(_dateOnly(day)),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 48, minHeight: rowH),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: circle,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? scheme.primary : null,
                      border: !selected && isToday
                          ? Border.all(color: scheme.primary)
                          : null,
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${day.day}',
                          maxLines: 1,
                          style: text.bodyMedium?.copyWith(color: numberColor),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 6,
                  child: _Dots(marks: marks, scheme: scheme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.marks, required this.scheme});

  final CalendarDayMarks marks;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      if (marks.taken) _takenDot,
      if (marks.missed) scheme.error,
      if (marks.pending) _pendingDot,
      if (marks.snoozed) scheme.tertiary,
      if (marks.notRecorded) scheme.outline,
    ];
    if (colors.length > 3) colors.removeRange(3, colors.length);
    if (colors.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < colors.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          DecoratedBox(
            decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle),
            child: const SizedBox(width: 6, height: 6),
          ),
        ],
      ],
    );
  }
}

String _daySemanticsLabel(DateTime day, CalendarDayMarks marks) {
  final date = '${day.day} ${_months[day.month - 1]}';
  if (marks.isEmpty) return date;
  final bits = <String>[
    if (marks.taken) 'taken',
    if (marks.missed) 'missed',
    if (marks.pending) 'pending',
    if (marks.snoozed) 'snoozed',
    if (marks.notRecorded) 'not recorded',
  ];
  return '$date, ${bits.join(', ')}';
}
