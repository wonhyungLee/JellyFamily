import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const supabaseUrl = 'https://gbzkrbepxejjcffyohcb.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdiemtyYmVweGVqamNmZnlvaGNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2ODkzMjQsImV4cCI6MjA4NTI2NTMyNH0.UVfArhZQB4cUw-em0IvYbgCKbSPFXA5jnMjI0emNldE';

const challengeTypes = ['BOOK_READING', 'ARITHMETIC', 'HANJA_WRITING'];
const jellyTypes = ['NORMAL', 'SPECIAL', 'BONUS'];
const parentJellyTypes = ['NORMAL'];

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

class UserOption {
  const UserOption(this.name, this.email);
  final String name;
  final String email;
}

const userOptions = <UserOption>[
  UserOption('이원형', 'wonhyung@jelly.family'),
  UserOption('박설화', 'seolhwa@jelly.family'),
  UserOption('이진아', 'jina@jelly.family'),
  UserOption('이진오', 'jino@jelly.family'),
  UserOption('이진서', 'jinseo@jelly.family'),
];

String twoDigits(int value) => value.toString().padLeft(2, '0');

DateTime seoulNow() {
  return DateTime.now().toUtc().add(const Duration(hours: 9));
}

String seoulDateString([int offsetDays = 0]) {
  final now = seoulNow();
  final base =
      DateTime.utc(now.year, now.month, now.day).add(Duration(days: offsetDays));
  return '${base.year}-${twoDigits(base.month)}-${twoDigits(base.day)}';
}

String seoulYearMonth() {
  final now = seoulNow();
  return '${now.year}-${twoDigits(now.month)}';
}

Future<void> _configureNotifications() async {
  try {
    tz.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(initSettings);

    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    await _scheduleDailySixAm();
  } catch (_) {
    // Notifications are optional; ignore initialization errors.
  }
}

Future<void> _scheduleDailySixAm() async {
  const notificationId = 600;
  await _notifications.cancel(notificationId);

  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 6);
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }

  const androidDetails = AndroidNotificationDetails(
    'jelly_morning',
    '아침 챌린지 알림',
    channelDescription: '매일 오전 6시에 오늘의 챌린지를 알려줘요.',
    importance: Importance.max,
    priority: Priority.high,
  );

  await _notifications.zonedSchedule(
    notificationId,
    '젤리패밀리',
    '좋은 아침! 오늘의 챌린지를 시작해요.',
    scheduled,
    const NotificationDetails(android: androidDetails),
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await _configureNotifications();
  runApp(const JellyFamilyApp());
}

class JellyFamilyApp extends StatelessWidget {
  const JellyFamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JellyFamily',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        return const HomeRouter();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  UserOption? _selected = userOptions.first;
  final _pinController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_selected == null) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _selected!.email,
        password: _pinController.text.trim(),
      );
    } on AuthException catch (error) {
      _showSnack('로그인 실패: ${error.message}');
    } catch (error) {
      _showSnack('로그인 실패: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JellyFamily 로그인')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<UserOption>(
              value: _selected,
              decoration: const InputDecoration(labelText: '이름 선택'),
              items: userOptions
                  .map((u) => DropdownMenuItem(
                        value: u,
                        child: Text(u.name),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _selected = value),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              decoration: const InputDecoration(labelText: 'PIN'),
              obscureText: true,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _signIn,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('로그인'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  late Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
  }

  Future<Map<String, dynamic>> _fetchProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw Exception('No session');
    }
    final response = await Supabase.instance.client
        .from('profiles')
        .select('display_name, role')
        .eq('id', user.id)
        .single();
    return response;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('프로필 로드 실패: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _profileFuture = _fetchProfile());
                    },
                    child: const Text('다시 시도'),
                  )
                ],
              ),
            ),
          );
        }
        final profile = snapshot.data ?? {};
        final role = profile['role'] as String? ?? 'CHILD';
        final name = profile['display_name'] as String? ?? '';
        if (role == 'PARENT') {
          return ParentHome(displayName: name);
        }
        return ChildHome(displayName: name);
      },
    );
  }
}

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
  Map<String, dynamic>? _wallet;
  List<dynamic> _requests = [];
  Map<String, dynamic>? _challengeMonth;
  List<dynamic> _challengeDays = [];
  Set<String> _holidaySet = {};
  Set<String> _normalGrantSet = {};
  Map<String, Set<String>> _grantDatesByChallenge = {};
  List<String> _requiredDates = [];
  String? _selectedChallenge;
  String _specialStatus = '확인 중...';
  String _bonusStatus = '확인 중...';
  bool _specialEligible = false;
  bool _bonusEligible = false;
  bool _assetsReady = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final assetsReady = await _checkAssets();
      final userId = _supabase.auth.currentUser!.id;
      final now = seoulNow();
      final year = now.year;
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
      List<dynamic> days = [];
      if (challenge != null) {
        days = await _supabase
            .from('challenge_days')
            .select('day_date, status')
            .eq('challenge_month_id', challenge['id'])
            .order('day_date', ascending: true);
      }
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
      final holidayStart = '$year-01-01';
      final holidayEnd = '$year-12-31';
      List<dynamic> holidays = await _supabase
          .from('public_holidays')
          .select('day_date, name')
          .gte('day_date', holidayStart)
          .lte('day_date', holidayEnd);
      if (holidays.isEmpty) {
        try {
          await _supabase.functions.invoke('sync-holidays', body: {'year': year});
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
        _challengeDays = days;
        _holidaySet = holidaySet;
        _normalGrantSet = normalGrantSet;
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
      _showSnack('데이터 로드 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    value: challengeA,
                    items: challengeTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) challengeA = value;
                    }),
                    decoration: const InputDecoration(labelText: '챌린지 A'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: challengeB,
                    items: challengeTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
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
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final response =
                      await _supabase.functions.invoke('select-challenges', body: {
                    'challenge_a': challengeA,
                    'challenge_b': challengeB,
                    'year_month': yearMonthController.text.trim(),
                  });
                  final data = response.data;
                  if (data is Map) {
                    setState(() {
                      _challengeMonth =
                          Map<String, dynamic>.from(data['month'] ?? {});
                      _challengeDays =
                          List<dynamic>.from(data['days'] ?? []);
                    });
                  }
                  _showSnack('챌린지가 저장되었습니다');
                } on FunctionException catch (error) {
                  _showSnack(
                      '챌린지 선택 실패: ${error.details ?? error.reasonPhrase ?? error.status}');
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
                    value: jelly,
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
            ElevatedButton(
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
            ElevatedButton(
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
      _showSnack('$jelly 젤리를 받았습니다');
      await _load();
    } on FunctionException catch (error) {
      _showSnack('요청 실패: ${error.details ?? error.reasonPhrase ?? error.status}');
    } catch (error) {
      _showSnack('요청 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'REWARDED':
        return Colors.green.shade200;
      case 'DONE':
        return Colors.orange.shade200;
      default:
        return Colors.grey.shade200;
    }
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

  Widget _jellyIcon(String type) {
    if (!_assetsReady) return const SizedBox.shrink();
    switch (type) {
      case 'SPECIAL':
        return Image.asset('assets/ui/jelly/jelly_special.png', width: 36);
      case 'BONUS':
        return Image.asset('assets/ui/jelly/jelly_bonus.png', width: 36);
      default:
        return Image.asset('assets/ui/jelly/jelly_normal.png', width: 36);
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

  Widget _challengeButton(String type) {
    final selected = _selectedChallenge == type;
    final progress = _challengeProgress(type);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedChallenge = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.orange.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.orange : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Column(
            children: [
              if (_assetsReady)
                Image.asset(_challengeIconPath(type), width: 52),
              const SizedBox(height: 6),
              Text(_challengeLabel(type),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.orange.shade700 : Colors.black87,
                  )),
              const SizedBox(height: 4),
              Text(
                '${progress.$1}/${progress.$2} (${progress.$3}%)',
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.orange.shade700 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarFor(String challengeType) {
    final challenge = _challengeMonth;
    if (challenge == null || challenge.isEmpty) {
      return const Text('이번 달 챌린지를 먼저 선택하세요.');
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
    rows.add(TableRow(
      children: weekLabels
          .map((label) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ))
          .toList(),
    ));

    int day = 1;
    final totalCells = (firstWeekday - 1) + totalDays;
    final rowCount = ((totalCells + 6) / 7).floor();
    for (int row = 0; row < rowCount; row += 1) {
      rows.add(TableRow(
        children: List.generate(7, (col) {
          final cellIndex = row * 7 + col;
          if (cellIndex < firstWeekday - 1 || day > totalDays) {
            return const SizedBox(height: 40);
          }
          final dateStr = '${yearMonth}-${twoDigits(day)}';
          final status = rewardDates.contains(dateStr) ? 'REWARDED' : 'PENDING';
          final displayDay = day;
          day += 1;
          return Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _statusColor(status),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$displayDay'),
                  Text(status, style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          );
        }),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('선택된 챌린지: ${_challengeLabel(challengeType)}'),
        const SizedBox(height: 8),
        Table(children: rows),
      ],
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
    final specialRequired = specialDates.where((d) => !holidaySet.contains(d)).toList();
    final specialClaimed = claims.any((row) =>
        row['reward_type'] == 'SPECIAL' && row['period_key'] == specialPeriod);
    final specialLast = specialRequired.isEmpty ? null : specialRequired.last;
    bool specialEligible = false;
    String specialStatus = '';
    if (specialClaimed) {
      specialStatus = '이미 지급됨';
    } else if (specialRequired.isEmpty) {
      specialStatus = '필수 일자 없음';
    } else if (specialLast != null &&
        today.isBefore(_parseDate(specialLast))) {
      specialStatus = '아직 기간 종료 전 (마지막 ${specialLast})';
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
    final bonusRequired = bonusDates.where((d) => !holidaySet.contains(d)).toList();
    final bonusClaimed = claims.any((row) =>
        row['reward_type'] == 'BONUS' && row['period_key'] == bonusPeriod);
    final bonusLast = bonusRequired.isEmpty ? null : bonusRequired.last;
    bool bonusEligible = false;
    String bonusStatus = '';
    if (bonusClaimed) {
      bonusStatus = '이미 지급됨';
    } else if (bonusRequired.isEmpty) {
      bonusStatus = '필수 일자 없음';
    } else if (bonusLast != null && today.isBefore(_parseDate(bonusLast))) {
      bonusStatus = '아직 기간 종료 전 (마지막 ${bonusLast})';
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
      return '${year}-${twoDigits(month)}-${twoDigits(day)}';
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
    final rewarded =
        (_grantDatesByChallenge[type] ?? <String>{})
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
    }
  }

  Future<void> _invokeFunction(String name, Map<String, dynamic> body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.functions.invoke(name, body: body);
      _showSnack('성공');
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

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    return Scaffold(
      appBar: AppBar(
        title: Text('자녀 ${widget.displayName}'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('로그아웃'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('지갑',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('NORMAL: ${wallet?['jelly_normal'] ?? 0}'),
                          Text('SPECIAL: ${wallet?['jelly_special'] ?? 0}'),
                          Text('BONUS: ${wallet?['jelly_bonus'] ?? 0}'),
                          const Divider(),
                          Text('현금: ${wallet?['cash_balance'] ?? 0}원'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _busy ? null : _selectChallenges,
                        child: const Text('월 챌린지 선택'),
                      ),
                      ElevatedButton(
                        onPressed: _busy ? null : _exchangeJelly,
                        child: const Text('젤리 환전'),
                      ),
                      ElevatedButton(
                        onPressed: _busy ? null : _requestAllowance,
                        child: const Text('용돈 요청'),
                      ),
                      ElevatedButton(
                        onPressed: _busy
                            ? null
                            : (_specialEligible ? () => _claimReward('SPECIAL') : null),
                      child: const Text('스페셜 젤리 받기'),
                    ),
                    ElevatedButton(
                        onPressed:
                            _busy ? null : (_bonusEligible ? () => _claimReward('BONUS') : null),
                        child: const Text('보너스 젤리 받기'),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _jellyIcon('SPECIAL'),
                          const SizedBox(width: 6),
                          Expanded(child: Text('스페셜: $_specialStatus')),
                        ],
                      ),
                      Row(
                        children: [
                          _jellyIcon('BONUS'),
                          const SizedBox(width: 6),
                          Expanded(child: Text('보너스: $_bonusStatus')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('챌린지 달력',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_challengeMonth != null && _challengeMonth!.isNotEmpty)
                    Row(
                      children: [
                        _challengeButton(
                            _challengeMonth!['challenge_a'] as String),
                        const SizedBox(width: 8),
                        _challengeButton(
                            _challengeMonth!['challenge_b'] as String),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (_selectedChallenge != null)
                    _buildCalendarFor(_selectedChallenge!),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green.shade200,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('REWARDED'),
                      const SizedBox(width: 12),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('PENDING'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('용돈 요청 내역',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_requests.isEmpty)
                    const Text('요청 내역이 없습니다.'),
                  for (final request in _requests)
                    Card(
                      child: ListTile(
                        title: Text('요청 ${request['requested_cash']}원'),
                        subtitle: Text(
                          '상태: ${request['status']}\nID: ${request['id']}',
                        ),
                        trailing: request['status'] == 'SETTLED'
                            ? TextButton(
                                onPressed: () => _openProof(request['id']),
                                child: const Text('증빙 보기'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class ParentHome extends StatefulWidget {
  const ParentHome({super.key, required this.displayName});
  final String displayName;

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  bool _loading = true;
  bool _busy = false;
  List<dynamic> _children = [];
  Map<String, dynamic> _walletsById = {};
  List<dynamic> _requests = [];
  Map<String, dynamic> _challengeByChild = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final children = await _supabase
          .from('profiles')
          .select('id, display_name, role')
          .eq('role', 'CHILD')
          .order('display_name');
      final childIds = children.map((c) => c['id']).toList();
      List<dynamic> wallets = [];
      if (childIds.isNotEmpty) {
        wallets = await _supabase
            .from('wallets')
            .select('*')
            .inFilter('user_id', childIds);
      }
      final requests = await _supabase
          .from('allowance_requests')
          .select('*, profiles:child_id(display_name)')
          .order('created_at', ascending: false);
      final challengeMonths = await _supabase
          .from('challenge_months')
          .select('child_id, year_month, challenge_a, challenge_b')
          .eq('year_month', seoulYearMonth());
      final walletMap = {
        for (final wallet in wallets) wallet['user_id'] as String: wallet,
      };
      final challengeMap = {
        for (final row in challengeMonths) row['child_id'] as String: row,
      };

      if (!mounted) return;
      setState(() {
        _children = children;
        _walletsById = walletMap;
        _requests = requests;
        _challengeByChild = challengeMap;
      });
    } catch (error) {
      _showSnack('데이터 로드 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _grantJelly([dynamic preselectedChild]) async {
    if (_children.isEmpty) {
      _showSnack('자녀 계정이 없습니다');
      return;
    }
    dynamic selectedChild = preselectedChild ?? _children.first;
    String challenge = challengeTypes.first;
    String jelly = parentJellyTypes.first;
    String targetDate = seoulDateString();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('젤리 지급'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<dynamic>(
                    value: selectedChild,
                    items: _children
                        .map((child) => DropdownMenuItem(
                              value: child,
                              child: Text(child['display_name']),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) selectedChild = value;
                    }),
                    decoration: const InputDecoration(labelText: '자녀'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: challenge,
                    items: challengeTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) challenge = value;
                    }),
                    decoration: const InputDecoration(labelText: '챌린지'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: jelly,
                    items: parentJellyTypes
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
                  DropdownButtonFormField<String>(
                    value: targetDate,
                    items: [
                      seoulDateString(),
                      seoulDateString(-1),
                    ]
                        .map((date) => DropdownMenuItem(
                              value: date,
                              child: Text(date),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) targetDate = value;
                    }),
                    decoration: const InputDecoration(labelText: '대상 날짜'),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('수량: 1개 (고정)'),
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
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _invokeFunction('grant-jelly', {
                  'child_id': selectedChild['id'],
                  'challenge': challenge,
                  'jelly': jelly,
                  'target_date': targetDate,
                });
              },
              child: const Text('지급'),
            )
          ],
        );
      },
    );
  }

  Future<void> _uploadProof(dynamic request) async {
    final requestId = request['id'] as String;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final extension = picked.path.split('.').last;
    final objectPath =
        'requests/$requestId/${DateTime.now().millisecondsSinceEpoch}.$extension';

    setState(() => _busy = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      await _supabase.storage.from('allowance-proofs').uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(contentType: picked.mimeType),
          );

      await _supabase.functions.invoke(
        'upload-proof-and-settle',
        body: {
          'request_id': requestId,
          'object_path': objectPath,
        },
      );
      _showSnack('정산 완료');
      await _load();
    } on FunctionException catch (error) {
      _showSnack('정산 실패: ${error.details ?? error.reasonPhrase ?? error.status}');
    } catch (error) {
      _showSnack('업로드 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invokeFunction(String name, Map<String, dynamic> body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.functions.invoke(name, body: body);
      _showSnack('성공');
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

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('부모 ${widget.displayName}'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('로그아웃'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('자녀 지갑',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          for (final child in _children)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '${child['display_name']}: '
                                'N ${_walletsById[child['id']]?['jelly_normal'] ?? 0}, '
                                'S ${_walletsById[child['id']]?['jelly_special'] ?? 0}, '
                                'B ${_walletsById[child['id']]?['jelly_bonus'] ?? 0}, '
                                '현금 ${_walletsById[child['id']]?['cash_balance'] ?? 0}원',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('챌린지 신청 현황',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_children.isEmpty)
                    const Text('자녀가 없습니다.'),
                  for (final child in _children)
                    Card(
                      child: ListTile(
                        title: Text(child['display_name']),
                        subtitle: _challengeByChild[child['id']] != null
                            ? Text(
                                '챌린지: ${_challengeByChild[child['id']]['challenge_a']} / ${_challengeByChild[child['id']]['challenge_b']}',
                              )
                            : const Text('이번 달 챌린지 미신청'),
                        trailing: _challengeByChild[child['id']] != null
                            ? TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _grantJelly(child),
                                child: const Text('젤리 지급'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _grantJelly,
                    child: const Text('젤리 지급'),
                  ),
                  const SizedBox(height: 24),
                  const Text('용돈 요청',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_requests.isEmpty) const Text('요청 내역이 없습니다.'),
                  for (final request in _requests)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${request['profiles']?['display_name'] ?? '자녀'} '
                          '요청 ${request['requested_cash']}원',
                        ),
                        subtitle: Text(
                          '상태: ${request['status']}\nID: ${request['id']}',
                        ),
                        trailing: request['status'] == 'REQUESTED'
                            ? TextButton(
                                onPressed:
                                    _busy ? null : () => _uploadProof(request),
                                child: const Text('증빙 업로드'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
