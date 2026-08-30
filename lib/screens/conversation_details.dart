import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../state/conversations_cubit.dart';
import '../state/services.dart';
import '../state/thread_cubit.dart';
import '../widgets/states.dart';
import 'thread.dart';

class ConversationDetailsScreen extends StatefulWidget {
  const ConversationDetailsScreen({super.key});

  @override
  State<ConversationDetailsScreen> createState() =>
      _ConversationDetailsScreenState();
}

class _ConversationDetailsScreenState extends State<ConversationDetailsScreen> {
  List<Person> _people = const [];
  Set<String> _online = const {};
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = context.read<AppServices>();
    final id = context.read<ThreadCubit>().state.conversation.id;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final people = await services.chat.participants(id);
      Set<String> online = const {};
      try {
        online = await services.chat.presence(id);
      } on ApiException {
        online = const {};
      }
      if (!mounted) return;
      setState(() {
        _people = people;
        _online = online;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _openDm(Person person) async {
    final services = context.read<AppServices>();
    final conversations = context.read<ConversationsCubit>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conversation = await services.chat.openDm(person.profileId);
      conversations.upsert(conversation);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: conversations,
            child: ThreadScreen(conversation: conversation),
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ThreadCubit>();
    return BlocBuilder<ThreadCubit, ThreadState>(
      builder: (context, state) {
        final conversation = state.conversation;
        final me = context.read<AppServices>().session.caller?.profileId ?? '';
        return Scaffold(
          appBar: AppBar(title: const Text('Details')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Container(
                width: double.infinity,
                color: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    AppAvatar(
                      name: conversation.displayName,
                      seed: conversation.isGroup
                          ? conversation.cooperativeId
                          : conversation.counterpartProfileId,
                      group: conversation.isGroup,
                      size: 82,
                    ),
                    const SizedBox(height: 12),
                    Text(conversation.displayName, style: AppText.title),
                    if (conversation.cooperativeName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          conversation.cooperativeName,
                          style: AppText.meta,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                children: [
                  SwitchListTile(
                    value: conversation.isMuted,
                    onChanged: (on) => cubit.mute(on ? 60 * 8 : 0),
                    activeThumbColor: AppColors.primary,
                    title: Text('Mute notifications', style: AppText.body),
                    subtitle: Text(
                      conversation.isMuted
                          ? 'Muted until ${bubbleTime(conversation.mutedUntil!)}'
                          : 'For eight hours',
                      style: AppText.caption,
                    ),
                  ),
                  if (conversation.isGroup && conversation.isAdmin)
                    SwitchListTile(
                      value: conversation.postingPolicy == 'admins_only',
                      onChanged: (on) => cubit.setPostingPolicy(
                        on ? 'admins_only' : 'all_members',
                      ),
                      activeThumbColor: AppColors.primary,
                      title: Text('Announcements only', style: AppText.body),
                      subtitle: Text(
                        'Only administrators can post',
                        style: AppText.caption,
                      ),
                    ),
                ],
              ),
              if (conversation.isGroup) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _peopleHeading(conversation),
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(_error, style: AppText.meta),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                else
                  _Section(
                    children: [
                      for (final person in _people)
                        ListTile(
                          leading: AppAvatar(
                            name: person.name,
                            seed: person.profileId,
                            size: 40,
                          ),
                          title: Text(
                            person.profileId == me ? 'You' : person.name,
                            style: AppText.body,
                          ),
                          subtitle: _online.contains(person.profileId)
                              ? Text(
                                  'Online',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.success,
                                  ),
                                )
                              : null,
                          trailing: person.profileId == me
                              ? null
                              : IconButton(
                                  tooltip: 'Message',
                                  onPressed: () => _openDm(person),
                                  icon: const Icon(
                                    Icons.chat_bubble_outline,
                                    color: AppColors.primary,
                                  ),
                                ),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _peopleHeading(Conversation conversation) {
    if (_people.isNotEmpty) return '${_people.length} MEMBERS';
    return 'MEMBERS';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      child: Column(
        children: [
          const Divider(height: 1),
          ...children,
          const Divider(height: 1),
        ],
      ),
    );
  }
}
