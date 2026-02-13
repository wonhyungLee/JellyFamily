import 'package:flutter/material.dart';
import 'package:jelly_family_app/domain/constants.dart';
import 'package:jelly_family_app/features/child/widgets/daily_praise_card.dart';
import 'package:jelly_family_app/shared/utils/number_format.dart';
import 'package:jelly_family_app/shared/utils/seoul_time.dart';
import 'package:jelly_family_app/shared/widgets/empty_state.dart';
import 'package:jelly_family_app/shared/widgets/error_state.dart';
import 'package:jelly_family_app/shared/widgets/jelly_reward_dialog.dart';
import 'package:jelly_family_app/shared/widgets/loading_state.dart';
import 'package:jelly_family_app/shared/widgets/section_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ChildHome extends StatefulWidget {
  const ChildHome({super.key, required this.displayName});

  final String displayName;

  @override
  State<ChildHome> createState() => _ChildHomeState();
}

class _EligibilityResult {
  const _EligibilityResult({
    required this.specialEligible,
    required this.bonusEligible,
    required this.specialStatus,
    required this.bonusStatus,
  });

  final bool specialEligible;
  final bool bonusEligible;
  final String specialStatus;
  final String bonusStatus;
}

class _ChildHomeState extends State<ChildHome> {
  final _supabase = Supabase.instance.client;

  int _tabIndex = 0;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  Map<String, dynamic>? _wallet;
  List<dynamic> _requests = [];
  Map<String, dynamic>? _challengeMonth;
  Set<String> _holidaySet = {};
  Map<String, Set<String>> _grantDatesByChallenge = {};
  List<String> _requiredDates = [];

  String? _selectedChallenge;
  String _specialStatus = '확인 중...';
  String _bonusStatus = '확인 중...';
  bool _specialEligible = false;
  bool _bonusEligible = false;

  bool _assetsReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final assetsReady = await _checkAssets();
      final userId = _supabase.auth.currentUser!.id;
      final now = seoulNow();
      final currentYear = now.year;

      final wallet = await _supabase
          .from('wallets')
          .select('*')
          .eq('user_id', userId)
          .single();

      final requests = await _supabase
          .from('allowance_requests')
          .select('*')
          .eq('child_id', userId)
          .order('created_at', ascending: false);

      final challenge = await _supabase
          .from('challenge_months')
          .select('*')
          .eq('child_id', userId)
          .eq('year_month', seoulYearMonth())
          .maybeSingle();

      Map<String, Set<String>> grantDatesByChallenge = {};
      if (challenge != null) {
        final yearMonth = challenge['year_month'] as String;
        final parts = yearMonth.split('-');
        final year = int.tryParse(parts[0]) ?? now.year;
        final month = int.tryParse(parts[1]) ?? now.month;
        final totalDays = DateUtils.getDaysInMonth(year, month);
        final startDate = '$yearMonth-01';
        final endDate = '$yearMonth-${twoDigits(totalDays)}';
        final grants = await _supabase
            .from('jelly_grants')
            .select('challenge, target_date')
            .eq('child_id', userId)
            .gte('target_date', startDate)
            .lte('target_date', endDate);
        for (final row in grants) {
          final challengeType = row['challenge'] as String?;
          final dateStr = row['target_date'] as String?;
          if (challengeType == null || dateStr == null) continue;
          grantDatesByChallenge
              .putIfAbsent(challengeType, () => <String>{})
              .add(dateStr);
        }
      }

      final holidayStart = '$currentYear-01-01';
      final holidayEnd = '$currentYear-12-31';
      List<dynamic> holidays = await _supabase
          .from('public_holidays')
          .select('day_date, name')
          .gte('day_date', holidayStart)
          .lte('day_date', holidayEnd);
      if (holidays.isEmpty) {
        try {
          await _supabase.functions
              .invoke('sync-holidays', body: {'year': currentYear});
          holidays = await _supabase
              .from('public_holidays')
              .select('day_date, name')
              .gte('day_date', holidayStart)
              .lte('day_date', holidayEnd);
        } on FunctionException {
          // ignore sync failure; continue without holidays
        }
      }

      final grants = await _supabase
          .from('jelly_grants')
          .select('target_date')
          .eq('child_id', userId)
          .eq('jelly', 'NORMAL')
          .gte('target_date', holidayStart)
          .lte('target_date', holidayEnd);

      final claims = await _supabase
          .from('reward_claims')
          .select('reward_type, period_key')
          .eq('child_id', userId);

      if (!mounted) return;

      final holidaySet = holidays
          .map<String>((row) => row['day_date'] as String)
          .toSet();
      final normalGrantSet = grants
          .map<String>((row) => row['target_date'] as String)
          .toSet();

      List<String> requiredDates = [];
      if (challenge != null) {
        requiredDates = _requiredDatesForMonth(
          challenge['year_month'] as String,
          holidaySet,
          upTo: seoulDateString(-1),
        );
      }

      final eligibility = _computeEligibility(
        now,
        holidaySet,
        normalGrantSet,
        claims,
      );

      setState(() {
        _wallet = wallet;
        _requests = requests;
        _challengeMonth = challenge;
        _holidaySet = holidaySet;
        _grantDatesByChallenge = grantDatesByChallenge;
        _requiredDates = requiredDates;
        _specialStatus = eligibility.specialStatus;
        _bonusStatus = eligibility.bonusStatus;
        _specialEligible = eligibility.specialEligible;
        _bonusEligible = eligibility.bonusEligible;
        if (challenge != null) {
          final a = challenge['challenge_a'] as String?;
          final b = challenge['challenge_b'] as String?;
          if (_selectedChallenge == null ||
              (_selectedChallenge != a && _selectedChallenge != b)) {
            _selectedChallenge = a ?? b;
          }
        }
        _assetsReady = assetsReady;
      });
    } catch (error) {
      setState(() => _loadError = '$error');
      _showSnack('데이터 로드 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('로그아웃'),
            content: const Text('정말 로그아웃할까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('로그아웃'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    await _supabase.auth.signOut();
  }

  Future<void> _selectChallenges() async {
    String challengeA = challengeTypes.first;
    String challengeB = challengeTypes[1];
    final yearMonthController = TextEditingController(text: seoulYearMonth());

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('월 챌린지 선택'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: challengeA,
                    items: challengeTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(_challengeLabel(type)),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) challengeA = value;
                    }),
                    decoration: const InputDecoration(labelText: '챌린지 A'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: challengeB,
                    items: challengeTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(_challengeLabel(type)),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) challengeB = value;
                    }),
                    decoration: const InputDecoration(labelText: '챌린지 B'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: yearMonthController,
                    decoration: const InputDecoration(
                      labelText: '연-월 (YYYY-MM)',
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final response = await _supabase.functions.invoke(
                    'select-challenges',
                    body: {
                      'challenge_a': challengeA,
                      'challenge_b': challengeB,
                      'year_month': yearMonthController.text.trim(),
                    },
                  );
                  final data = response.data;
                  if (data is Map) {
                    setState(() {
                      _challengeMonth =
                          Map<String, dynamic>.from(data['month'] ?? {});
                    });
                  }
                  _showSnack('챌린지가 저장되었습니다');
                  await _load();
                } on FunctionException catch (error) {
                  _showSnack(
                    '챌린지 선택 실패: ${error.details ?? error.reasonPhrase ?? error.status}',
                  );
                } catch (error) {
                  _showSnack('챌린지 선택 실패: $error');
                }
              },
              child: const Text('선택'),
            )
          ],
        );
      },
    );

    yearMonthController.dispose();
  }

  Future<void> _exchangeJelly() async {
    String jelly = jellyTypes.first;
    final amountController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('젤리 환전'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: jelly,
                    items: jellyTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) jelly = value;
                    }),
                    decoration: const InputDecoration(labelText: '젤리 종류'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(labelText: '수량'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final amount = int.tryParse(amountController.text.trim());
                if (amount == null || amount <= 0) {
                  _showSnack('수량을 입력하세요');
                  return;
                }
                await _invokeFunction('exchange-jelly', {
                  'jelly': jelly,
                  'amount': amount,
                });
              },
              child: const Text('환전'),
            )
          ],
        );
      },
    );

    amountController.dispose();
  }

  Future<void> _requestAllowance() async {
    final amountController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('용돈 요청'),
          content: TextField(
            controller: amountController,
            decoration: const InputDecoration(labelText: '요청 금액 (빈칸이면 전액)'),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final text = amountController.text.trim();
                final amount = text.isEmpty ? null : int.tryParse(text);
                if (text.isNotEmpty && (amount == null || amount < 0)) {
                  _showSnack('금액을 확인하세요');
                  return;
                }
                await _invokeFunction('request-allowance', {
                  if (amount != null) 'requested_cash': amount,
                });
              },
              child: const Text('요청'),
            )
          ],
        );
      },
    );

    amountController.dispose();
  }

  Future<void> _claimReward(String jelly) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.functions.invoke('claim-reward', body: {
        'jelly': jelly,
      });
      if (!mounted) return;
      await showJellyRewardDialog(context, jelly: jelly);
      await _load();
    } on FunctionException catch (error) {
      _showSnack('요청 실패: ${error.details ?? error.reasonPhrase ?? error.status}');
    } catch (error) {
      _showSnack('요청 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openProof(String requestId) async {
    try {
      final response = await _supabase.functions.invoke('get-proof-url', body: {
        'request_id': requestId,
      });
      final data = response.data;
      if (data is Map && data['signed_url'] != null) {
        final url = Uri.parse(data['signed_url'] as String);
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          _showSnack('URL 열기 실패');
        }
      }
    } on FunctionException catch (error) {
      _showSnack('증빙 열기 실패: ${error.details ?? error.reasonPhrase ?? error.status}');
    } catch (error) {
      _showSnack('증빙 열기 실패: $error');
    }
  }

  Future<void> _invokeFunction(String name, Map<String, dynamic> body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.functions.invoke(name, body: body);
      _showSnack('완료');
      await _load();
    } on FunctionException catch (error) {
      _showSnack('요청 실패: ${error.details ?? error.reasonPhrase ?? error.status}');
    } catch (error) {
      _showSnack('요청 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _checkAssets() async {
    try {
      await DefaultAssetBundle.of(context)
          .load('assets/ui/jelly/jelly_normal.png');
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _jellyIcon(String type, {double size = 22}) {
    if (!_assetsReady) {
      return Icon(Icons.circle, size: size, color: Colors.orange.shade200);
    }
    switch (type) {
      case 'SPECIAL':
        return Image.asset('assets/ui/jelly/jelly_special.png', width: size);
      case 'BONUS':
        return Image.asset('assets/ui/jelly/jelly_bonus.png', width: size);
      default:
        return Image.asset('assets/ui/jelly/jelly_normal.png', width: size);
    }
  }

  String _challengeIconPath(String type) {
    switch (type) {
      case 'ARITHMETIC':
        return 'assets/ui/challenge/ic_challenge_arithmetic.png';
      case 'HANJA_WRITING':
        return 'assets/ui/challenge/ic_challenge_hanja.png';
      default:
        return 'assets/ui/challenge/ic_challenge_reading.png';
    }
  }

  String _challengeLabel(String type) {
    switch (type) {
      case 'ARITHMETIC':
        return '연산';
      case 'HANJA_WRITING':
        return '한자';
      default:
        return '독서';
    }
  }

  Widget _challengePickerButton(String type) {
    final selected = _selectedChallenge == type;
    final progress = _challengeProgress(type);
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedChallenge = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.55)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              if (_assetsReady)
                Image.asset(_challengeIconPath(type), width: 52),
              const SizedBox(height: 8),
              Text(
                _challengeLabel(type),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${progress.$1}/${progress.$2} (${progress.$3}%)',
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _cellColor(bool rewarded, bool isHoliday) {
    final scheme = Theme.of(context).colorScheme;
    if (isHoliday) return scheme.surfaceContainerHighest.withValues(alpha: 0.22);
    if (rewarded) return Colors.green.shade200;
    return scheme.surfaceContainerHighest.withValues(alpha: 0.35);
  }

  Widget _buildCalendarFor(String challengeType) {
    final challenge = _challengeMonth;
    if (challenge == null || challenge.isEmpty) {
      return EmptyState(
        title: '이번 달 챌린지를 먼저 선택하세요',
        message: '챌린지를 선택하면 달력에서 진행 상황을 볼 수 있어요.',
        icon: Icons.flag_outlined,
        action: FilledButton.icon(
          onPressed: _busy ? null : _selectChallenges,
          icon: const Icon(Icons.tune),
          label: const Text('월 챌린지 선택'),
        ),
      );
    }

    final yearMonth = (challenge['year_month'] as String?) ?? seoulYearMonth();
    final parts = yearMonth.split('-');
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final totalDays = DateUtils.getDaysInMonth(year, month);
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon

    final rewardDates = _grantDatesByChallenge[challengeType] ?? <String>{};

    final rows = <TableRow>[];
    const weekLabels = ['월', '화', '수', '목', '금', '토', '일'];
    rows.add(
      TableRow(
        children: weekLabels
            .map(
              (label) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );

    int day = 1;
    final totalCells = (firstWeekday - 1) + totalDays;
    final rowCount = ((totalCells + 6) / 7).floor();
    for (int row = 0; row < rowCount; row += 1) {
      rows.add(
        TableRow(
          children: List.generate(7, (col) {
            final cellIndex = row * 7 + col;
            if (cellIndex < firstWeekday - 1 || day > totalDays) {
              return const SizedBox(height: 46);
            }

            final dateStr = '$yearMonth-${twoDigits(day)}';
            final rewarded = rewardDates.contains(dateStr);
            final isHoliday = _holidaySet.contains(dateStr);
            final displayDay = day;
            day += 1;

            return Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: _cellColor(rewarded, isHoliday),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        '$displayDay',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color:
                              isHoliday ? Colors.black54 : Colors.grey.shade900,
                        ),
                      ),
                    ),
                    if (rewarded)
                      const Positioned(
                        right: 6,
                        top: 6,
                        child: Icon(Icons.check_circle, size: 16),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$yearMonth · ${_challengeLabel(challengeType)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '지급 ${(_grantDatesByChallenge[challengeType] ?? <String>{}).length}일',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Table(children: rows),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _legendChip(
              color: Colors.green.shade200,
              label: '지급됨',
              icon: Icons.check_circle,
            ),
            _legendChip(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
              label: '대기',
              icon: Icons.schedule,
            ),
            _legendChip(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.22),
              label: '휴일',
              icon: Icons.event_busy,
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendChip({
    required Color color,
    required String label,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  _EligibilityResult _computeEligibility(
    DateTime now,
    Set<String> holidaySet,
    Set<String> normalGrantSet,
    List<dynamic> claims,
  ) {
    final today = DateTime.utc(now.year, now.month, now.day);

    final specialPeriod = '${now.year}-${twoDigits(now.month)}';
    final specialDates = _datesInMonth(now.year, now.month);
    final specialRequired =
        specialDates.where((d) => !holidaySet.contains(d)).toList();
    final specialClaimed = claims.any(
      (row) => row['reward_type'] == 'SPECIAL' && row['period_key'] == specialPeriod,
    );
    final specialLast = specialRequired.isEmpty ? null : specialRequired.last;
    bool specialEligible = false;
    String specialStatus = '';
    if (specialClaimed) {
      specialStatus = '이미 지급됨';
    } else if (specialRequired.isEmpty) {
      specialStatus = '필수 일자 없음';
    } else if (specialLast != null && today.isBefore(_parseDate(specialLast))) {
      specialStatus = '아직 기간 종료 전 (마지막 $specialLast)';
    } else {
      final missing =
          specialRequired.where((d) => !normalGrantSet.contains(d)).toList();
      if (missing.isNotEmpty) {
        specialStatus = '일반 젤리 미지급 ${missing.length}일';
      } else {
        specialEligible = true;
        specialStatus = '지급 가능';
      }
    }

    final weekStart = _weekStart(today);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final bonusPeriod = _formatDate(weekStart);
    final bonusDates = _dateRange(weekStart, weekEnd);
    final bonusRequired =
        bonusDates.where((d) => !holidaySet.contains(d)).toList();
    final bonusClaimed = claims.any(
      (row) => row['reward_type'] == 'BONUS' && row['period_key'] == bonusPeriod,
    );
    final bonusLast = bonusRequired.isEmpty ? null : bonusRequired.last;
    bool bonusEligible = false;
    String bonusStatus = '';
    if (bonusClaimed) {
      bonusStatus = '이미 지급됨';
    } else if (bonusRequired.isEmpty) {
      bonusStatus = '필수 일자 없음';
    } else if (bonusLast != null && today.isBefore(_parseDate(bonusLast))) {
      bonusStatus = '아직 기간 종료 전 (마지막 $bonusLast)';
    } else {
      final missing =
          bonusRequired.where((d) => !normalGrantSet.contains(d)).toList();
      if (missing.isNotEmpty) {
        bonusStatus = '일반 젤리 미지급 ${missing.length}일';
      } else {
        bonusEligible = true;
        bonusStatus = '지급 가능';
      }
    }

    return _EligibilityResult(
      specialEligible: specialEligible,
      bonusEligible: bonusEligible,
      specialStatus: specialStatus,
      bonusStatus: bonusStatus,
    );
  }

  List<String> _datesInMonth(int year, int month) {
    final total = DateUtils.getDaysInMonth(year, month);
    return List.generate(total, (i) {
      final day = i + 1;
      return '$year-${twoDigits(month)}-${twoDigits(day)}';
    });
  }

  List<String> _requiredDatesForMonth(
    String yearMonth,
    Set<String> holidays, {
    String? upTo,
  }) {
    final parts = yearMonth.split('-');
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final dates = _datesInMonth(year, month);
    final filtered = dates.where((d) => !holidays.contains(d)).toList();
    if (upTo == null) {
      return filtered;
    }
    final upToDate = _parseDate(upTo);
    final firstDay = DateTime.utc(year, month, 1);
    if (upToDate.isBefore(firstDay)) {
      return [];
    }
    if (upToDate.year == year && upToDate.month == month) {
      return filtered.where((d) => d.compareTo(upTo) <= 0).toList();
    }
    return filtered;
  }

  (int, int, int) _challengeProgress(String type) {
    final total = _requiredDates.length;
    final rewarded = (_grantDatesByChallenge[type] ?? <String>{})
        .where((d) => _requiredDates.contains(d))
        .length;
    final percent = total == 0 ? 0 : ((rewarded / total) * 100).round();
    return (rewarded, total, percent);
  }

  DateTime _parseDate(String value) {
    final parts = value.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    return DateTime.utc(year, month, day);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }

  DateTime _weekStart(DateTime date) {
    final weekday = date.weekday; // 1=Mon
    return date.subtract(Duration(days: weekday - 1));
  }

  List<String> _dateRange(DateTime start, DateTime end) {
    final dates = <String>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      dates.add(_formatDate(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return dates;
  }

  Widget _walletRow({
    required String label,
    required Widget leading,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    final wallet = _wallet;
    final normal = (wallet?['jelly_normal'] as int?) ?? 0;
    final special = (wallet?['jelly_special'] as int?) ?? 0;
    final bonus = (wallet?['jelly_bonus'] as int?) ?? 0;
    final cash = (wallet?['cash_balance'] as int?) ?? 0;

    final challenge = _challengeMonth;
    final a = challenge?['challenge_a'] as String?;
    final b = challenge?['challenge_b'] as String?;
    final today = seoulDateString();
    final todayHoliday = _holidaySet.contains(today);
    final todayDone = _isTodayChallengeDone(today);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '안녕, ${widget.displayName}',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        if (todayDone)
          const DailyPraiseCard(
            headline: '오늘 챌린지 완료!',
            message: '대단해. 오늘은 더 할 챌린지가 없어요.',
          )
        else if (a != null && b != null && todayHoliday)
          const DailyPraiseCard(
            headline: '오늘은 쉬는 날!',
            message: '휴일에는 마음껏 쉬어도 돼요.',
          ),
        if (todayDone || (a != null && b != null && todayHoliday))
          const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: '지갑'),
                const SizedBox(height: 8),
                _walletRow(
                  label: '일반 젤리',
                  leading: _jellyIcon('NORMAL'),
                  value: '$normal',
                ),
                _walletRow(
                  label: '스페셜 젤리',
                  leading: _jellyIcon('SPECIAL'),
                  value: '$special',
                ),
                _walletRow(
                  label: '보너스 젤리',
                  leading: _jellyIcon('BONUS'),
                  value: '$bonus',
                ),
                const Divider(height: 22),
                _walletRow(
                  label: '현금 잔액',
                  leading: const Icon(Icons.payments_outlined, size: 22),
                  value: formatWon(cash),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: '빠른 작업'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _requestAllowance,
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('용돈 요청'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _exchangeJelly,
                      icon: const Icon(Icons.currency_exchange),
                      label: const Text('젤리 환전'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _selectChallenges,
                      icon: const Icon(Icons.tune),
                      label: const Text('월 챌린지 선택'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: '리워드'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : (_specialEligible
                                ? () => _claimReward('SPECIAL')
                                : null),
                        child: const Text('스페셜 받기'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : (_bonusEligible ? () => _claimReward('BONUS') : null),
                        child: const Text('보너스 받기'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _jellyIcon('SPECIAL'),
                    const SizedBox(width: 8),
                    Expanded(child: Text('스페셜: $_specialStatus')),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _jellyIcon('BONUS'),
                    const SizedBox(width: 8),
                    Expanded(child: Text('보너스: $_bonusStatus')),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (a != null || b != null) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: '이번 달 진행'),
                  const SizedBox(height: 10),
                  if (a != null) _challengeProgressCard(a),
                  if (a != null && b != null) const SizedBox(height: 10),
                  if (b != null) _challengeProgressCard(b),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  bool _isTodayChallengeDone(String today) {
    final challenge = _challengeMonth;
    final a = challenge?['challenge_a'] as String?;
    final b = challenge?['challenge_b'] as String?;
    if (a == null || b == null) return false;
    if (_holidaySet.contains(today)) return false;
    final aRewarded = (_grantDatesByChallenge[a] ?? <String>{}).contains(today);
    final bRewarded = (_grantDatesByChallenge[b] ?? <String>{}).contains(today);
    return aRewarded && bRewarded;
  }

  Widget _challengeProgressCard(String type) {
    final progress = _challengeProgress(type);
    final scheme = Theme.of(context).colorScheme;
    final percent = progress.$3.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (_assetsReady)
            Image.asset(_challengeIconPath(type), width: 40),
          if (_assetsReady) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _challengeLabel(type),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: percent / 100.0,
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${progress.$1}/${progress.$2}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengesTab() {
    final challenge = _challengeMonth;
    final a = challenge?['challenge_a'] as String?;
    final b = challenge?['challenge_b'] as String?;

    if (a == null || b == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyState(
            title: '이번 달 챌린지가 아직 없어요',
            message: '챌린지 2개를 선택하면 달력에서 진행 상황을 볼 수 있어요.',
            icon: Icons.flag_outlined,
            action: FilledButton.icon(
              onPressed: _busy ? null : _selectChallenges,
              icon: const Icon(Icons.tune),
              label: const Text('월 챌린지 선택'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '챌린지',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _selectChallenges,
              icon: const Icon(Icons.tune),
              label: const Text('변경'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _challengePickerButton(a),
            const SizedBox(width: 10),
            _challengePickerButton(b),
          ],
        ),
        const SizedBox(height: 16),
        if (_selectedChallenge != null) _buildCalendarFor(_selectedChallenge!),
      ],
    );
  }

  Widget _buildRequestsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '용돈 요청',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _requestAllowance,
              icon: const Icon(Icons.add),
              label: const Text('요청'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_requests.isEmpty)
          const EmptyState(
            title: '요청 내역이 없습니다',
            message: '필요할 때 용돈을 요청해보세요.',
          )
        else
          ..._requests.map(_requestCard),
      ],
    );
  }

  Widget _requestCard(dynamic request) {
    final status = (request['status'] as String?) ?? 'UNKNOWN';
    final requestedCash = (request['requested_cash'] as int?) ?? 0;
    final id = (request['id'] as String?) ?? '';

    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status) {
      'REQUESTED' => (
          'assets/ui/status/ic_status_requested.png',
          '요청됨',
          scheme.tertiaryContainer.withValues(alpha: 0.6),
        ),
      'SETTLED' => (
          'assets/ui/status/ic_status_settled.png',
          '정산 완료',
          Colors.green.shade200,
        ),
      _ => (
          'assets/ui/status/ic_status_requested.png',
          status,
          scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_assetsReady)
                    Image.asset(icon, width: 22)
                  else
                    const Icon(Icons.receipt_long_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '요청 ${formatWon(requestedCash)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(label, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'ID: $id',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              if (status == 'SETTLED') ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _openProof(id),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('증빙 보기'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '홈',
      ),
      const NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: '챌린지',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: '요청',
      ),
    ];

    Widget body;
    if (_loading) {
      body = const LoadingState(label: '불러오는 중...');
    } else if (_loadError != null) {
      body = ErrorState(
        title: '데이터 로드 실패',
        details: _loadError!,
        onRetry: _load,
      );
    } else {
      final tab = switch (_tabIndex) {
        0 => _buildDashboardTab(),
        1 => _buildChallengesTab(),
        _ => _buildRequestsTab(),
      };
      body = RefreshIndicator(onRefresh: _load, child: tab);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('자녀 ${widget.displayName}'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _confirmSignOut,
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        destinations: destinations,
      ),
    );
  }
}
