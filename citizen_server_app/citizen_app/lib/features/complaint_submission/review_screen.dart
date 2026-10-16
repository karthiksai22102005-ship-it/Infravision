import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    final d = st.draft;
    final cat =
        st.categories.where((c) => c.code == d.categoryCode).firstOrNull;
    return Scaffold(
      appBar: StepHeader(4, s('review')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (d.photos.isNotEmpty)
          SizedBox(
              height: 110,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in d.photos)
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(p),
                              width: 110, height: 110, fit: BoxFit.cover))),
              ])),
        const SizedBox(height: 12),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                          s('category'),
                          cat == null
                              ? '-'
                              : st.s.categoryLabel(cat.code, cat.nameEn)),
                      _row(s('location'),
                          '${d.address ?? ''}\n${d.lat?.toStringAsFixed(5)}, ${d.lng?.toStringAsFixed(5)}'),
                      _row(s('photos'), '${d.photos.length}'),
                      _row(s('videos'), '${d.videos.length}'),
                      const Divider(),
                      Text(s('description'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(d.description),
                    ]))),
        if (st.error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child:
                  Text(st.error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            disabledBackgroundColor: const Color(0xFF5B8DEF),
            textStyle: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          icon: st.loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send, color: Colors.white),
          label: Text(
            st.loading
                ? s('submitting')
                : st.error != null
                    ? s('retry')
                    : s('submit'),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          onPressed: st.loading
              ? null
              : () async {
                  if (d.categoryCode == null) {
                    showSnack(context, 'Please select an issue category.');
                    return;
                  }
                  if (!d.hasLocation) {
                    showSnack(context, 'Please set the issue location on the map.');
                    return;
                  }
                  if (d.description.trim().length < 10) {
                    showSnack(context, 'Please enter a description of at least 10 characters.');
                    return;
                  }
                  final ok = await st.submit();
                  if (ok && context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(context, '/success',
                        (r) => r.settings.name == '/home' || r.isFirst);
                  }
                },
        ),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 80,
              child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v.trim())),
        ]),
      );
}
