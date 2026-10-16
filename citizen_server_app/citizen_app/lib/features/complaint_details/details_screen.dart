import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/network/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../pdf_reports/pdf_service.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.reference});
  final String reference;
  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  @override
  void initState() {
    super.initState();
    // Always refresh from the server: local copy is only a cache.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppState>().refreshComplaint(widget.reference));
  }

  static const _order = [
    'submitted',
    'under_review',
    'assigned',
    'in_progress',
    'resolved'
  ];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c =
        st.complaints.where((x) => x.reference == widget.reference).firstOrNull;
    final svc = PdfService(st.api);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Complaint Details'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Timeline'),
              Tab(text: 'Photos'),
              Tab(text: 'Details')
            ])),
        body: c == null
            ? AsyncBody(
                isEmpty: true,
                onRetry: () => st.refreshComplaint(widget.reference),
                child: const SizedBox())
            : Column(children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(c.reference,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                            Text(
                                'Submitted on ${c.createdAt.toLocal().toString().substring(0, 16)}',
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 12)),
                          ])),
                      StatusBadge(c.status),
                    ])),
                Expanded(
                    child: TabBarView(
                        children: [_timeline(c), _photos(c, st), _info(c)])),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf),
                              label: Text(st.s('downloadPdf')),
                              onPressed: () async {
                                try {
                                  await svc.open(c.reference);
                                } on ApiException catch (e) {
                                  if (context.mounted) {
                                    showSnack(context, e.message);
                                  }
                                }
                              })),
                      const SizedBox(width: 10),
                      Expanded(
                          child: FilledButton.icon(
                              icon: const Icon(Icons.share),
                              label: Text(st.s('share')),
                              onPressed: () async {
                                try {
                                  await svc.share(c.reference);
                                } on ApiException catch (e) {
                                  if (context.mounted) {
                                    showSnack(context, e.message);
                                  }
                                }
                              })),
                    ])),
              ]),
      ),
    );
  }

  Widget _timeline(Complaint c) {
    final done = {for (final h in c.history) h.status: h};
    return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final step in _order)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Icon(
                    done.containsKey(step)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: done.containsKey(step)
                        ? AppColors.green
                        : AppColors.muted),
                Container(width: 2, height: 44, color: AppColors.line),
              ]),
              const SizedBox(width: 12),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(statusLabel(step),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(
                                done[step] != null
                                    ? '${done[step]!.at.toString().substring(0, 16)}\n${done[step]!.message}'
                                    : 'Pending',
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 12)),
                          ]))),
            ]),
        ]);
  }

  Widget _photos(Complaint c, AppState st) => c.evidenceIds.isEmpty
      ? const StateMessage(
          icon: Icons.photo_outlined, text: 'No photos attached')
      : GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: c.evidenceIds.length,
          itemBuilder: (_, i) => FutureBuilder<List<int>>(
            future: st.api.evidenceBytes(c.reference, c.evidenceIds[i]),
            builder: (_, snap) => snap.hasData
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(Uint8List.fromList(snap.data!),
                        fit: BoxFit.cover))
                : Container(
                    decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(12)),
                    child: Center(
                        child: snap.hasError
                            ? const Icon(Icons.broken_image)
                            : const CircularProgressIndicator())),
          ),
        );

  Widget _info(Complaint c) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Text('Category: ${c.categoryName}'),
        const SizedBox(height: 8),
        Text(
            'Location: ${c.address ?? ''} (${c.latitude.toStringAsFixed(5)}, ${c.longitude.toStringAsFixed(5)})'),
        const SizedBox(height: 8),
        Text('Description:\n${c.description}'),
      ]);
}
