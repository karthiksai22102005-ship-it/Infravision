import 'package:flutter/material.dart';

import '../core/query.dart' show ReportFilter;
import '../models/analysis.dart';
import '../models/observation.dart';
import 'portal_services.dart';
import 'report_detail_screen.dart';
import 'widgets.dart';

/// Human-readable category label for lists and headers.
String categoryLabel(String categoryId) =>
    DefectCategoryCatalog.byId(categoryId)?.label ?? categoryId;

/// My Reports: filter chips, search and page-at-a-time loading so a long
/// history never decodes every thumbnail at once (§46/§55).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const int _pageSize = 20;

  final TextEditingController _search = TextEditingController();
  ReportFilter _filter = ReportFilter.all;
  int _limit = _pageSize;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openDetail(Observation observation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ReportDetailScreen(observationId: observation.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PortalServices services = PortalScope.of(context);
    return ListenableBuilder(
      listenable: services.repository,
      builder: (BuildContext context, Widget? child) {
        final page = services.database.pageObservations(
          filter: _filter,
          search: _search.text,
          limit: _limit,
        );
        final Map<ReportFilter, int> counts = services.repository.filterCounts;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _search,
                onChanged: (String value) => setState(() => _limit = _pageSize),
                decoration: InputDecoration(
                  hintText: 'Search description, id or case',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            _search.clear();
                            _limit = _pageSize;
                          }),
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: ReportFilter.values.map((ReportFilter f) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: ChoiceChip(
                      label: Text('${f.label} (${counts[f] ?? 0})'),
                      selected: f == _filter,
                      onSelected: (bool isSelected) {
                        if (!isSelected) return;
                        setState(() {
                          _filter = f;
                          _limit = _pageSize;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: page.items.isEmpty
                  ? EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No reports in this view',
                      hint: _search.text.isEmpty
                          ? 'Capture a report or change the filter above.'
                          : 'Nothing matches "${_search.text}".',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: page.items.length + (page.hasMore ? 1 : 0),
                      itemBuilder: (BuildContext context, int index) {
                        if (index >= page.items.length) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: OutlinedButton(
                                onPressed: () =>
                                    setState(() => _limit += _pageSize),
                                child: Text(
                                  'Load $_pageSize more '
                                  '(${page.total - page.loadedCount} left)',
                                ),
                              ),
                            ),
                          );
                        }
                        final Observation o = page.items[index];
                        return Card(
                          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: ListTile(
                            leading: const Icon(Icons.report_outlined),
                            title: Text(
                              o.description.isEmpty
                                  ? categoryLabel(o.category)
                                  : o.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${categoryLabel(o.category)} · '
                              '${timeAgo(o.createdAt)} · '
                              '${o.evidenceIds.length} evidence',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                PriorityPill(level: o.priority, dense: true),
                                const SizedBox(height: 4),
                                SyncPill(state: o.syncState, dense: true),
                              ],
                            ),
                            onTap: () => _openDetail(o),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
