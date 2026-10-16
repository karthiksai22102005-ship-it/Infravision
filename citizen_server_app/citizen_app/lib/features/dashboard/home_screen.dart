import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    final recent = st.complaints.take(3).toList();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: const AppBottomNav(0),
      body: Column(children: [
        Container(
          color: AppColors.navy,
          padding: EdgeInsets.fromLTRB(
              16, MediaQuery.of(context).padding.top + 12, 16, 16),
          child: Row(children: [
            CircleAvatar(
                backgroundColor: Colors.white24,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Image.asset('assets/images/app_icon.png',
                      fit: BoxFit.contain),
                )),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('InfraVision Citizen',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700))),
            Badge(
                isLabelVisible: st.unread > 0,
                label: Text('${st.unread}'),
                child: IconButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/notifications'),
                    icon: const Icon(Icons.notifications_none,
                        color: Colors.white))),
            IconButton(
              tooltip: s('settings'),
              onPressed: () => Navigator.pushNamed(context, '/profile'),
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: st.refreshAll,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child:
                        ListView(padding: const EdgeInsets.all(24), children: [
                      InkWell(
                        onTap: () => Navigator.pushNamed(context, '/category'),
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: AppColors.blue,
                              borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            const CircleAvatar(
                                backgroundColor: Colors.white,
                                child:
                                    Icon(Icons.report, color: AppColors.blue)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(s('reportIssue'),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700)),
                                  Text(s('reportSub'),
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                ])),
                            const Icon(Icons.chevron_right,
                                color: Colors.white),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                          child: ListTile(
                        onTap: () => Navigator.pushNamed(context, '/assistant'),
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE8F0FF),
                            child: Icon(Icons.auto_awesome,
                                color: AppColors.blue)),
                        title: Text(s('aiAssistant'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(s('aiHelp')),
                        trailing: const Icon(Icons.chevron_right),
                      )),
                      LayoutBuilder(
                          builder: (context, constraints) => GridView.count(
                                crossAxisCount:
                                    constraints.maxWidth >= 900 ? 4 : 2,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio:
                                    constraints.maxWidth >= 900 ? 1.25 : 1.7,
                                children: [
                                  _Tile(
                                      s('myReports'),
                                      '${st.complaints.length}',
                                      Icons.description,
                                      AppColors.green,
                                      '/reports'),
                                  _Tile(s('nearby'), '', Icons.place,
                                      AppColors.blue, '/nearby'),
                                  _Tile(
                                      s('notifications'),
                                      '${st.unread}',
                                      Icons.notifications,
                                      AppColors.red,
                                      '/notifications'),
                                  _Tile(
                                      s('drafts'),
                                      st.draft.isEmpty ? '0' : '1',
                                      Icons.edit_note,
                                      AppColors.amber,
                                      '/category'),
                                ],
                              )),
                      const SizedBox(height: 20),
                      Text(s('recent'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      if (st.loading && recent.isEmpty)
                        const Center(child: CircularProgressIndicator())
                      else if (st.offline && recent.isEmpty)
                        StateMessage(
                            icon: Icons.wifi_off,
                            text: s('offline'),
                            action: s('retry'),
                            onAction: st.refreshAll)
                      else if (recent.isEmpty)
                        StateMessage(
                            icon: Icons.inbox_outlined, text: s('empty'))
                      else
                        for (final c in recent)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                                child: ListTile(
                              onTap: () => Navigator.pushNamed(
                                  context, '/details',
                                  arguments: c.reference),
                              title: Text(c.reference,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(c.categoryName),
                              trailing: StatusBadge(c.status),
                            )),
                          ),
                    ]))),
          ),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.icon, this.color, this.route);
  final String label, value, route;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        child: Card(
            child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
                backgroundColor: color.withValues(alpha: .15),
                child: Icon(icon, color: color)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                  if (value.isNotEmpty)
                    Text(value,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                ])),
          ]),
        )),
      );
}
