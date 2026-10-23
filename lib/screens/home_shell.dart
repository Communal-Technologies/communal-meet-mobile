import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/callkit.dart';
import '../core/push.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/socket.dart';
import '../state/calls_cubit.dart';
import '../state/conversations_cubit.dart';
import '../state/services.dart';
import '../state/session_cubit.dart';
import '../state/spaces_cubit.dart';
import '../widgets/states.dart';
import 'call.dart';
import 'calls_tab.dart';
import 'chats_tab.dart';
import 'coops_tab.dart';
import 'incoming_call.dart';

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
        BlocProvider(create: (_) => ConversationsCubit(services)..load()),
        BlocProvider(create: (_) => SpacesCubit(services)..load()),
        BlocProvider(create: (_) => CallsCubit(services)..load()),
      ],
      child: _PushRouter(
        onTab: (i) {
          if (mounted) setState(() => _index = i);
        },
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

/// Takes a tapped notification to what it was about. Sits inside the providers
/// because opening a thread needs [ConversationsCubit].
class _PushRouter extends StatefulWidget {
  const _PushRouter({required this.child, required this.onTab});

  final Widget child;
  final void Function(int) onTab;

  @override
  State<_PushRouter> createState() => _PushRouterState();
}

class _PushRouterState extends State<_PushRouter> {
  StreamSubscription<PushTap>? _taps;
  StreamSubscription<SocketFrame>? _frames;
  StreamSubscription<String>? _answers;
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _taps = services.push.taps.listen(_follow);
    _frames = services.socket.frames.listen(_onFrame);
    _answers = services.push.answers.listen(_joinAnswered);

    final waiting = services.push.pending;
    services.push.pending = null;
    if (waiting != null && !waiting.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(waiting));
    }

    final answered = services.push.pendingAnswer;
    services.push.pendingAnswer = null;
    if (answered != null && answered.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _joinAnswered(answered),
      );
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    _frames?.cancel();
    _answers?.cancel();
    super.dispose();
  }

  Future<void> _joinAnswered(String callId) async {
    if (!mounted || callId.isEmpty || _ringing) return;
    _ringing = true;
    final services = context.read<AppServices>();
    final me = context.read<SessionCubit>().state.caller?.profileId ?? '';
    try {
      final ticket = await services.calls.accept(callId);
      await CallKit.clearAll();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              CallScreen(ticket: ticket, outgoing: false, selfProfileId: me),
        ),
      );
    } catch (_) {
      await CallKit.clearAll();
    }
    _ringing = false;
    if (mounted) context.read<CallsCubit>().refresh();
  }

  void _onFrame(SocketFrame frame) {
    if (frame.type != 'call.ring') return;
    _ring(CallRecord.fromJson(frame.data));
  }

  Future<void> _ring(CallRecord call) async {
    if (_ringing || !mounted || call.id.isEmpty) return;
    _ringing = true;
    final navigator = Navigator.of(context);
    await CallKit.clearAll();
    await navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(call: call),
      ),
    );
    _ringing = false;
    if (mounted) context.read<CallsCubit>().refresh();
  }

  Future<void> _follow(PushTap tap) async {
    if (tap.callId.isNotEmpty) {
      await _answerFromTray(tap.callId);
      return;
    }
    if (tap.conversationId.isEmpty) {
      if (tap.meetingId.isNotEmpty) widget.onTab(1);
      return;
    }
    widget.onTab(0);
    try {
      final conversation = await context.read<AppServices>().chat.conversation(
        tap.conversationId,
      );
      if (!mounted) return;
      await openThread(context, conversation);
    } catch (_) {
      return;
    }
  }

  Future<void> _answerFromTray(String callId) async {
    widget.onTab(2);
    try {
      final recent = await context.read<AppServices>().calls.recent();
      final call = recent.firstWhere(
        (c) => c.id == callId && c.isRinging,
        orElse: () => throw StateError('no longer ringing'),
      );
      await _ring(call);
    } catch (_) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
