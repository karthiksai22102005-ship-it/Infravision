import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/network/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../pdf_reports/pdf_service.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});
  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.65, curve: Curves.elasticOut),
    );
    _checkAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOutBack),
    );
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _pdf(PdfService svc, String ref, {bool share = false}) async {
    setState(() => _busy = true);
    try {
      share ? await svc.share(ref) : await svc.open(ref);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    final c = st.lastSubmitted;
    if (c == null) {
      return Scaffold(
          body: StateMessage(icon: Icons.inbox_outlined, text: s('empty')));
    }
    final svc = PdfService(st.api);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.green.withValues(alpha: 0.4),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: ScaleTransition(
                      scale: _checkAnimation,
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(s('submitted'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(s('referenceNumber'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: const Color(0xFFE6EEFF),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(c.reference,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.blue)),
                  IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c.reference));
                        showSnack(context, 'Copied');
                      }),
                ]),
              ),
              if (st.submitWarning != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(st.submitWarning!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.amber))),
              const SizedBox(height: 12),
              Text(s('thankYou'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const Spacer(),
              FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/details',
                      arguments: c.reference),
                  child: Text(s('viewReport'))),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pdf(svc, c.reference),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(s('downloadPdf'))),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                  onPressed:
                      _busy ? null : () => _pdf(svc, c.reference, share: true),
                  icon: const Icon(Icons.share),
                  label: Text(s('share'))),
              TextButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context, '/home', (_) => false),
                  child: Text(s('backHome'))),
            ]),
          ),
        ),
      ),
    );
  }
}
