import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String _jellyAssetPath(String jelly) {
  switch (jelly) {
    case 'SPECIAL':
      return 'assets/ui/jelly/jelly_special.png';
    case 'BONUS':
      return 'assets/ui/jelly/jelly_bonus.png';
    default:
      return 'assets/ui/jelly/jelly_normal.png';
  }
}

String _jellyDisplayName(String jelly) {
  switch (jelly) {
    case 'SPECIAL':
      return '스페셜';
    case 'BONUS':
      return '보너스';
    default:
      return '일반';
  }
}

Future<void> showJellyRewardDialog(
  BuildContext context, {
  required String jelly,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'jelly_reward',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return JellyRewardDialog(jelly: jelly);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class JellyRewardDialog extends StatefulWidget {
  const JellyRewardDialog({super.key, required this.jelly});

  final String jelly;

  @override
  State<JellyRewardDialog> createState() => _JellyRewardDialogState();
}

class _JellyRewardDialogState extends State<JellyRewardDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  bool _didHaptic = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final jellyAsset = _jellyAssetPath(widget.jelly);
    final jellyName = _jellyDisplayName(widget.jelly);

    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;

                // Bounce in first, then shake, then reveal sparkles.
                final scale = Tween<double>(begin: 0.78, end: 1.0)
                    .chain(CurveTween(curve: Curves.elasticOut))
                    .transform((t / 0.35).clamp(0.0, 1.0));

                final shakePhase = ((t - 0.28) / 0.40).clamp(0.0, 1.0);
                final shakeAmount = (1.0 - shakePhase) * 0.10;
                final shake = math.sin(t * math.pi * 18) * shakeAmount;

                final sparkleT = ((t - 0.55) / 0.35).clamp(0.0, 1.0);

                if (!_didHaptic && t > 0.58) {
                  _didHaptic = true;
                  HapticFeedback.mediumImpact();
                }

                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '$jellyName 젤리!',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '젤리를 까는 중...',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 170,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                _sparkle(
                                  t: sparkleT,
                                  offset: const Offset(-90, -40),
                                  color: scheme.primary,
                                ),
                                _sparkle(
                                  t: sparkleT,
                                  offset: const Offset(100, -30),
                                  color: scheme.tertiary,
                                ),
                                _sparkle(
                                  t: sparkleT,
                                  offset: const Offset(-70, 60),
                                  color: scheme.secondary,
                                ),
                                _sparkle(
                                  t: sparkleT,
                                  offset: const Offset(85, 70),
                                  color: scheme.primary,
                                ),
                                Transform.rotate(
                                  angle: shake,
                                  child: Transform.scale(
                                    scale: scale,
                                    child: Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest
                                            .withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Image.asset(
                                          jellyAsset,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stack) {
                                            return Icon(
                                              Icons.card_giftcard,
                                              size: 56,
                                              color: scheme.primary,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedOpacity(
                            opacity: sparkleT,
                            duration: const Duration(milliseconds: 120),
                            child: Text(
                              '잘했어! 지갑에 추가됐어요.',
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('좋아!'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _sparkle({
    required double t,
    required Offset offset,
    required Color color,
  }) {
    final eased = Curves.easeOutBack.transform(t);
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(offset.dx * eased, offset.dy * eased),
        child: Transform.rotate(
          angle: t * math.pi,
          child: Icon(
            Icons.auto_awesome,
            size: 22 + (eased * 10),
            color: color.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

