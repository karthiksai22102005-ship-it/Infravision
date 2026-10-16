import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// In-app notifications pulled from the server (committed status updates only).
/// Push (FCM) is intentionally not wired until Firebase config is supplied.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(st.s('notifications'))),
      body: AsyncBody(
        isEmpty: st.notifications.isEmpty,
        onRetry: st.refreshAll,
        child: RefreshIndicator(
          onRefresh: st.refreshAll,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: st.notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final n = st.notifications[i];
              return Card(
                  child: ListTile(
                leading: CircleAvatar(
                    backgroundColor:
                        n.isRead ? AppColors.line : const Color(0xFFE6EEFF),
                    child: Icon(Icons.notifications,
                        color: n.isRead ? AppColors.muted : AppColors.blue)),
                title: Text(n.title,
                    style: TextStyle(
                        fontWeight:
                            n.isRead ? FontWeight.w500 : FontWeight.w700)),
                subtitle:
                    Text('${n.body}\n${n.at.toString().substring(0, 16)}'),
                isThreeLine: true,
              ));
            },
          ),
        ),
      ),
    );
  }
}
