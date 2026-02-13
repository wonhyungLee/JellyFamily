import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jelly_family_app/domain/constants.dart';
import 'package:jelly_family_app/shared/utils/number_format.dart';
import 'package:jelly_family_app/shared/utils/seoul_time.dart';
import 'package:jelly_family_app/shared/widgets/empty_state.dart';
import 'package:jelly_family_app/shared/widgets/error_state.dart';
import 'package:jelly_family_app/shared/widgets/loading_state.dart';
import 'package:jelly_family_app/shared/widgets/section_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ParentHome extends StatefulWidget {
  const ParentHome({super.key, required this.displayName});

  final String displayName;

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  int _tabIndex = 0;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

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
    setState(() {
      _loading = true;
      _loadError = null;
    });
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
                    initialValue: selectedChild,
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
                    initialValue: challenge,
                    items: challengeTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(_challengeLabel(type)),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) challenge = value;
                    }),
                    decoration: const InputDecoration(labelText: '챌린지'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: jelly,
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
                    initialValue: targetDate,
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
            FilledButton(
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

  Widget _walletLine({
    required String label,
    required int value,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
        const Spacer(),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _childCard(dynamic child) {
    final id = child['id'] as String;
    final name = child['display_name'] as String? ?? '';
    final wallet = _walletsById[id] as Map<String, dynamic>?;
    final cash = (wallet?['cash_balance'] as int?) ?? 0;
    final n = (wallet?['jelly_normal'] as int?) ?? 0;
    final s = (wallet?['jelly_special'] as int?) ?? 0;
    final b = (wallet?['jelly_bonus'] as int?) ?? 0;

    final challenge = _challengeByChild[id] as Map<String, dynamic>?;
    final a = challenge?['challenge_a'] as String?;
    final bb = challenge?['challenge_b'] as String?;

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
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    child: Text(
                      name.isEmpty ? '?' : name.substring(0, 1),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed:
                        _busy || a == null || bb == null ? null : () => _grantJelly(child),
                    child: const Text('젤리 지급'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _walletLine(label: '일반', value: n, icon: Icons.circle),
              const SizedBox(height: 6),
              _walletLine(label: '스페셜', value: s, icon: Icons.star_outline),
              const SizedBox(height: 6),
              _walletLine(label: '보너스', value: b, icon: Icons.card_giftcard),
              const Divider(height: 22),
              Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '현금',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatWon(cash),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (a != null && bb != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '이번 달: ${_challengeLabel(a)} / ${_challengeLabel(bb)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  '이번 달 챌린지 미신청',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildrenTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '자녀',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _grantJelly,
              icon: const Icon(Icons.add),
              label: const Text('젤리 지급'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Image.asset('assets/ui/status/ic_time_grant.png', width: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '지급 가능 시간: 06:00~08:00\n대상 날짜: 오늘 또는 어제',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SectionHeader(title: '지갑/챌린지 현황'),
        const SizedBox(height: 10),
        if (_children.isEmpty)
          const EmptyState(
            title: '자녀가 없습니다',
            message: 'profiles 테이블에 role=CHILD 사용자가 있어야 해요.',
          )
        else
          ..._children.map(_childCard),
      ],
    );
  }

  Widget _buildRequestsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '용돈 요청',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        if (_requests.isEmpty)
          const EmptyState(
            title: '요청 내역이 없습니다',
            message: '자녀가 용돈을 요청하면 여기에 표시됩니다.',
          )
        else
          ..._requests.map(_requestCard),
      ],
    );
  }

  Widget _requestCard(dynamic request) {
    final status = (request['status'] as String?) ?? 'UNKNOWN';
    final childName = request['profiles']?['display_name'] as String? ?? '자녀';
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
                  Image.asset(icon, width: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$childName · 요청 ${formatWon(requestedCash)}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
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
              if (status == 'REQUESTED') ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _uploadProof(request),
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('증빙 업로드'),
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
        icon: Icon(Icons.group_outlined),
        selectedIcon: Icon(Icons.group),
        label: '자녀',
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
      final tab = _tabIndex == 0 ? _buildChildrenTab() : _buildRequestsTab();
      body = RefreshIndicator(onRefresh: _load, child: tab);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('부모 ${widget.displayName}'),
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
