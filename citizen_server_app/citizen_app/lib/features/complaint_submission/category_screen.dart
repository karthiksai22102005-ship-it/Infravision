import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

const _icons = <String, IconData>{
  'pothole': Icons.warning_amber,
  'road_damage': Icons.edit_road,
  'footpath': Icons.directions_walk,
  'streetlight': Icons.lightbulb_outline,
  'drainage': Icons.water_drop_outlined,
  'manhole': Icons.circle_outlined,
  'traffic_sign': Icons.signpost_outlined,
  'road_marking': Icons.horizontal_rule,
  'other': Icons.more_horiz,
};

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});
  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    final sel = st.draft.categoryCode;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100
        ? 4
        : width >= 760
            ? 3
            : 2;
    final tileRatio = width >= 760 ? 2.8 : 1.5;
    return Scaffold(
      appBar: StepHeader(1, s('reportIssue')),
      body: AsyncBody(
        isEmpty: st.categories.isEmpty,
        onRetry: st.refreshAll,
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  Text(s('chooseCategory'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: tileRatio,
                    children: [
                      for (final c in st.categories)
                        InkWell(
                          onTap: () =>
                              st.updateDraft((d) => d.categoryCode = c.code),
                          child: Container(
                            decoration: BoxDecoration(
                              color: sel == c.code
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: sel == c.code
                                      ? AppColors.blue
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                  width: sel == c.code ? 2 : 1),
                            ),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_icons[c.code] ?? Icons.report,
                                      size: 30,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(height: 6),
                                  Text(st.s.categoryLabel(c.code, c.nameEn),
                                      style: const TextStyle(fontSize: 13)),
                                ]),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(s('next')),
                    onPressed: () {
                      if (sel == null) {
                        return showSnack(context, st.s('chooseCategoryFirst'));
                      }
                      Navigator.pushNamed(context, '/location');
                    },
                  ),
                ]))),
      ),
    );
  }
}
