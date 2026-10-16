import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _filter = 'all';
  static const _filters = {
    'all': 'All',
    'in_progress': 'In Progress',
    'resolved': 'Resolved',
    'closed': 'Closed'
  };

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final list = _filter == 'all'
        ? st.complaints
        : st.complaints.where((c) => c.status == _filter).toList();
    return Scaffold(
      appBar: AppBar(title: Text(st.s('myReports'))),
      bottomNavigationBar: const AppBottomNav(3),
      body: Column(children: [
        SizedBox(
            height: 52,
            child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final e in _filters.entries)
                    Padding(
                        padding:
                            const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                        child: ChoiceChip(
                            label: Text(e.value),
                            selected: _filter == e.key,
                            onSelected: (_) =>
                                setState(() => _filter = e.key))),
                ])),
        Expanded(
          child: AsyncBody(
            isEmpty: list.isEmpty,
            onRetry: st.refreshAll,
            child: RefreshIndicator(
              onRefresh: st.refreshAll,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final c = list[i];
                  return Card(
                      child: ListTile(
                    onTap: () => Navigator.pushNamed(context, '/details',
                        arguments: c.reference),
                    leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE6EEFF),
                        child:
                            Icon(Icons.report_problem, color: AppColors.blue)),
                    title: Text(c.reference,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                        '${c.categoryName}\n${c.address ?? ''}  ${c.createdAt.day}/${c.createdAt.month}/${c.createdAt.year}',
                        maxLines: 2),
                    isThreeLine: true,
                    trailing: StatusBadge(c.status),
                  ));
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
