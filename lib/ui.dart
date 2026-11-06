import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// A rounded card with a hairline border. Tappable when [onTap] is given.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.borderColor,
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color ?? (dark ? c.surfaceContainerLow : c.surfaceContainerLowest) : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? c.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A small heading above a group of controls, such as "RHYTHM".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 24, 4, 10)});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.4,
        );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: style)),
          ?trailing,
        ],
      ),
    );
  }
}

/// An icon on a softly tinted rounded square.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, required this.color, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// A rounded status label, such as "3 min behind".
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.color, this.icon, this.leading});

  final String label;
  final Color color;
  final IconData? icon;

  /// Shown instead of [icon], for something animated like [PulseDot].
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)]
          else if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dot that gently pulses, for "recording now". Holds still when the phone asks for less motion.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.2,
      height: s * 2.2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s + s * 1.2 * t,
                height: s + s * 1.2 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.45 * (1 - t)),
                ),
              ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A friendly placeholder for an empty list.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0.06)]),
            ),
            child: Icon(icon, size: 40, color: tint),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// A soft glow of [color] behind its child, for the screen's main moment.
class Glow extends StatelessWidget {
  const Glow({super.key, required this.color, required this.child, this.strength = 0.22});

  final Color color;
  final Widget child;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // Fades out fully before the nearest edge, so the box itself never shows.
          radius: 0.5,
          colors: [color.withValues(alpha: strength), color.withValues(alpha: 0)],
        ),
      ),
      child: child,
    );
  }
}

/// The big countdown: a ring that empties as time runs out, with [child] in the middle.
///
/// [progress] is the share of time left, from 1 (just started) to 0 (time's up).
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.progress,
    required this.color,
    required this.child,
    this.size = 280,
    this.stroke = 16,
  });

  final double progress;
  final Color color;
  final Widget child;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        // Short, so it's finished well before the next once-a-second tick.
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        tween: Tween(end: progress.clamp(0.0, 1.0)),
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(
            progress: value,
            color: color,
            track: dark ? c.surfaceContainerHigh : c.surfaceContainerHighest,
            ticks: c.outlineVariant,
            stroke: stroke,
            glow: dark,
          ),
          child: child,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.ticks,
    required this.stroke,
    required this.glow,
  });

  final double progress;
  final Color color;
  final Color track;
  final Color ticks;
  final double stroke;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Minute-style ticks just outside the ring.
    final tick = Paint()
      ..color = ticks
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final angle = 2 * pi * i / 60 - pi / 2;
      final long = i % 5 == 0;
      final outer = radius + stroke / 2 + (long ? 10 : 7);
      final inner = radius + stroke / 2 + 4;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * inner,
        center + Offset(cos(angle), sin(angle)) * outer,
        tick,
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;

    final sweep = 2 * pi * progress;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        colors: [color.withValues(alpha: 0.55), color],
        stops: [0, progress.clamp(0.001, 1.0)],
        transform: const GradientRotation(-pi / 2),
      ).createShader(rect);

    if (glow) {
      canvas.drawArc(
        rect,
        -pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.6
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.drawArc(rect, -pi / 2, sweep, false, arc);

    // A bright head where the ring is emptying.
    final end = -pi / 2 + sweep;
    final head = center + Offset(cos(end), sin(end)) * radius;
    canvas.drawCircle(head, stroke / 2 - 1, Paint()..color = color);
    canvas.drawCircle(head, stroke / 5, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track || old.glow != glow;
}

/// Colours for a plan's segments, cycling through the app's accents.
Color segmentColor(BuildContext context, int index) {
  final c = Theme.of(context).colorScheme;
  final palette = [c.primary, c.secondary, c.tertiary];
  final base = palette[index % palette.length];
  return (index ~/ palette.length).isOdd ? base.withValues(alpha: 0.6) : base;
}

/// A plan drawn as one bar, each segment as wide as its share of the time.
class SegmentStrip extends StatelessWidget {
  const SegmentStrip({super.key, required this.minutes, this.height = 10, this.highlight});

  final List<int> minutes;
  final double height;

  /// Dims every segment but this one, for "you are here".
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    if (minutes.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < minutes.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              flex: max(1, minutes[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  color: segmentColor(context, i)
                      .withValues(alpha: highlight == null || highlight == i ? null : 0.25),
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A big number with a small unit, like "30 min" on the focus screen.
class BigValue extends StatelessWidget {
  const BigValue(this.value, {super.key, this.color, this.style});

  final String value;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Text(
      value,
      style: tabular((style ?? textTheme.headlineSmall)?.copyWith(color: color)),
    );
  }
}
