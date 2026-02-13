import 'package:flutter/material.dart';

class DailyPraiseCard extends StatefulWidget {
  const DailyPraiseCard({
    super.key,
    required this.headline,
    required this.message,
    this.assetPath = 'assets/images/app_icon.png',
  });

  final String headline;
  final String message;
  final String assetPath;

  @override
  State<DailyPraiseCard> createState() => _DailyPraiseCardState();
}

class _DailyPraiseCardState extends State<DailyPraiseCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.65),
              scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_controller.value);
                final dy = (-6.0 * t);
                final scale = 1.0 + (0.03 * t);
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  widget.assetPath,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) {
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.emoji_events, color: scheme.primary),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.headline,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.message,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_controller.value);
                return Opacity(opacity: 0.6 + (0.4 * t), child: child);
              },
              child: Icon(Icons.auto_awesome, color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

