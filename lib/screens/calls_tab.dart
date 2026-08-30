import 'package:flutter/material.dart';

import '../widgets/states.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      asset: 'empty_calls.svg',
      title: 'No calls yet',
      body: 'Audio and video calls arrive in the next build of this app. '
          'Chat works now.',
    );
  }
}
