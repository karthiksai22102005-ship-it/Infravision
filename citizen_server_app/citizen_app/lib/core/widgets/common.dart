import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel(status),
          style:
              TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class StepHeader extends StatelessWidget implements PreferredSizeWidget {
  const StepHeader(this.step, this.title, {super.key});
  final int step; // 1..4
  final String title;
  @override
  Size get preferredSize => const Size.fromHeight(100);
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    final labels = [
      s('category'),
      s('details'),
      s('evidence'),
      s('reviewShort')
    ];
    return AppBar(
      title: Text(title),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            for (var i = 0; i < 4; i++) ...[
              Column(children: [
                CircleAvatar(
                    radius: 12,
                    backgroundColor: i < step
                        ? AppColors.blue
                        : Theme.of(context).colorScheme.surface,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            color: i < step ? Colors.white : AppColors.muted))),
                Text(labels[i],
                    style: TextStyle(
                        fontSize: 10,
                        color: i < step
                            ? AppColors.blue
                            : Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
              if (i < 3)
                Expanded(
                    child: Container(
                        height: 2,
                        color: i < step - 1
                            ? AppColors.blue
                            : Theme.of(context).colorScheme.outlineVariant)),
            ]
          ]),
        ),
      ),
    );
  }
}

class StateMessage extends StatelessWidget {
  const StateMessage(
      {super.key,
      required this.icon,
      required this.text,
      this.action,
      this.onAction});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ]
          ]),
        ),
      );
}

/// Shared loading / offline / error / empty handling for list screens.
class AsyncBody extends StatelessWidget {
  const AsyncBody(
      {super.key, required this.isEmpty, required this.child, this.onRetry});
  final bool isEmpty;
  final Widget child;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    if (st.loading && isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (st.offline && isEmpty) {
      return StateMessage(
          icon: Icons.wifi_off,
          text: st.s('offline'),
          action: st.s('retry'),
          onAction: onRetry);
    }
    if (st.error != null && isEmpty) {
      return StateMessage(
          icon: Icons.error_outline,
          text: st.error!,
          action: st.s('retry'),
          onAction: onRetry);
    }
    if (isEmpty) {
      return StateMessage(icon: Icons.inbox_outlined, text: st.s('empty'));
    }
    return child;
  }
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav(this.index, {super.key});
  final int index;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    const routes = ['/home', '/nearby', '/category', '/reports', '/profile'];
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) {
        if (i == 2) {
          Navigator.pushNamed(context, '/category');
        } else if (i != index) {
          Navigator.pushReplacementNamed(context, routes[i]);
        }
      },
      destinations: [
        NavigationDestination(
            icon: const Icon(Icons.home_outlined), label: s('home')),
        NavigationDestination(
            icon: const Icon(Icons.map_outlined), label: s('map')),
        NavigationDestination(
            icon: const Icon(Icons.add_circle, color: AppColors.blue, size: 36),
            label: s('report')),
        NavigationDestination(
            icon: const Icon(Icons.description_outlined),
            label: s('myReports')),
        NavigationDestination(
            icon: const Icon(Icons.person_outline), label: s('profile')),
      ],
    );
  }
}

void showSnack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
