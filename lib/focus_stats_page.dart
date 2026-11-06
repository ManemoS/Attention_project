import 'dart:math';

import 'package:flutter/material.dart';

import 'focus_stats.dart';
import 'theme.dart';
import 'ui.dart';
import 'l10n.dart';

/// Seven bars, one per day, each as tall as that day's focus time. Today is drawn solid and
/// labelled; press and hold any bar for its exact time.
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.stats, this.height = 120, this.showTodayValue = true});

  final FocusStats stats;
  final double height;
  final bool showTodayValue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = MaterialLocalizations.of(context);
    // At least half an hour tall, so one short session doesn't fill the chart.
    final top = max(stats.best.inSeconds, 30 * 60).toDouble();
    const labelHeight = 18.0;
    final valueHeight = showTodayValue ? 20.0 : 0.0;
    final plot = height - labelHeight - valueHeight;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Builder(builder: (context) {
                final day = stats.days[i];
                final value = stats.daily[i];
                final isToday = i == 6;
                final label = '${l10n.formatMediumDate(day)}: ${formatFocus(value)}';
                final barHeight = value == Duration.zero ? 3.0 : max(6.0, plot * value.inSeconds / top);
                return Semantics(
                  // Its own item, so a screen reader can step through the days one at a time.
                  container: true,
                  label: isToday ? '${'Today'.tr}, $label' : label,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: label,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isToday && showTodayValue)
                          SizedBox(
                            height: valueHeight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(formatFocus(value), style: tabular(textTheme.labelMedium)),
                            ),
                          ),
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: value == Duration.zero
                                ? colors.outlineVariant
                                : colors.primary.withValues(alpha: isToday ? 1 : 0.45),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        Container(height: 1, color: colors.outlineVariant),
                        SizedBox(
                          height: labelHeight - 1,
                          child: Center(
                            child: Text(
                              l10n.narrowWeekdays[day.weekday % 7],
                              style: textTheme.labelSmall?.copyWith(
                                letterSpacing: 0,
                                color: isToday ? colors.onSurface : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

/// The small "This week".tr card at the top of the Focus tab.
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.stats, required this.onTap});

  final FocusStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      onTap: onTap,
      child: stats.isEmpty
          ? Row(
              children: [
                IconBadge(Icons.insights_rounded, color: colors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Your focus week shows up here after your first session.'.tr,
                    style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('THIS WEEK'.tr, style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(formatFocus(stats.week), style: tabular(textTheme.headlineMedium)),
                      ),
                      Text('focused'.tr, style: textTheme.bodySmall),
                      if (stats.streak >= 2) ...[
                        const SizedBox(height: 10),
                        Pill(
                          label: '{n}-day streak'.trf({'n': stats.streak}),
                          color: colors.primary,
                          icon: Icons.local_fire_department_rounded,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: WeekBars(stats: stats, height: 92, showTodayValue: false)),
              ],
            ),
    );
  }
}

class FocusStatsPage extends StatelessWidget {
  const FocusStatsPage({super.key, required this.stats});

  final FocusStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = MaterialLocalizations.of(context);
    final mostTried = stats.topBlocked.isEmpty ? 1 : stats.topBlocked.first.count;

    return Scaffold(
      appBar: AppBar(title: Text('Your focus'.tr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _Tile(label: 'Today'.tr, value: formatFocus(stats.today), icon: Icons.today_rounded),
              _Tile(label: 'This week'.tr, value: formatFocus(stats.week), icon: Icons.date_range_rounded),
              _Tile(label: 'Best day'.tr, value: formatFocus(stats.best), icon: Icons.emoji_events_rounded),
              _Tile(
                label: 'Streak'.tr,
                value: stats.streak == 1 ? '1 day'.tr : '{n} days'.trf({'n': stats.streak}),
                icon: Icons.local_fire_department_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Focus time, last 7 days'.tr, style: textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  (stats.sessionsThisWeek == 1
                        ? '1 session. Press and hold a bar for its time.'
                        : '{n} sessions. Press and hold a bar for its time.')
                    .trf({'n': stats.sessionsThisWeek}),
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                WeekBars(stats: stats, height: 160),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Show as table'.tr, style: textTheme.titleSmall),
                  children: [
                    for (var i = 6; i >= 0; i--)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(i == 6 ? 'Today'.tr : l10n.formatMediumDate(stats.days[i]))),
                            Text(formatFocus(stats.daily[i]), style: tabular(textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SectionLabel('Most tried while locked'.tr),
          Panel(
            child: stats.topBlocked.isEmpty
                ? Row(
                    children: [
                      Icon(Icons.verified_rounded, color: colors.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No locked apps opened this week. Nice.'.tr,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      for (final app in stats.topBlocked.take(5)) ...[
                        Row(
                          children: [
                            Expanded(child: Text(app.name, style: textTheme.titleSmall)),
                            Text(
                              app.count == 1 ? '1 try'.tr : '{n} tries'.trf({'n': app.count}),
                              style: tabular(textTheme.bodySmall),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LayoutBuilder(
                          builder: (context, constraints) => Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              height: 8,
                              width: max(8, constraints.maxWidth * app.count / mostTried),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.8),
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        'Each try is one time you opened a locked app. Fewer tries means the habit is fading.'.tr,
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall)),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: tabular(textTheme.headlineSmall)),
          ),
        ],
      ),
    );
  }
}
