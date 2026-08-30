import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme.dart';
import '../state/conversations_cubit.dart';
import '../state/services.dart';
import '../state/session_cubit.dart';
import '../state/spaces_cubit.dart';
import '../widgets/states.dart';
import 'calls_tab.dart';
import 'chats_tab.dart';
import 'coops_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ConversationsCubit(services)..load(),
        ),
        BlocProvider(create: (_) => SpacesCubit(services)..load()),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index]),
          actions: [
            IconButton(
              tooltip: 'Account',
              onPressed: () => _showAccount(context),
              icon: const Icon(Icons.account_circle_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(
          index: _index,
          children: const [ChatsTab(), CoopsTab(), CallsTab()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Cooperatives',
            ),
            NavigationDestination(
              icon: Icon(Icons.call_outlined),
              selectedIcon: Icon(Icons.call),
              label: 'Calls',
            ),
          ],
        ),
      ),
    );
  }

  static const _titles = ['Chats', 'Cooperatives', 'Calls'];

  void _showAccount(BuildContext context) {
    final session = context.read<SessionCubit>();
    final caller = session.state.caller;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(name: caller?.name ?? '', seed: caller?.profileId),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          caller?.name.isNotEmpty == true
                              ? caller!.name
                              : 'Signed in',
                          style: AppText.subtitle,
                        ),
                        Text(
                          caller?.guard == 'coop-admin'
                              ? 'Cooperative administrator'
                              : 'Member',
                          style: AppText.meta,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: AppColors.danger),
                title: Text(
                  'Sign out',
                  style: AppText.subtitle.copyWith(color: AppColors.danger),
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  session.signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
