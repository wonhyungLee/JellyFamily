import 'package:flutter/material.dart';
import 'package:jelly_family_app/features/child/child_home.dart';
import 'package:jelly_family_app/features/parent/parent_home.dart';
import 'package:jelly_family_app/shared/widgets/error_state.dart';
import 'package:jelly_family_app/shared/widgets/loading_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          return const Scaffold(body: LoadingState(label: '프로필 불러오는 중...'));
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: ErrorState(
              title: '프로필 로드 실패',
              details: '${snapshot.error}',
              onRetry: () => setState(() => _profileFuture = _fetchProfile()),
            ),
          );
        }

        final profile = snapshot.data ?? <String, dynamic>{};
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

