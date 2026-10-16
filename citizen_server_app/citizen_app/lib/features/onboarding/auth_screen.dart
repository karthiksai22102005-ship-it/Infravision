import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _pass = TextEditingController(),
      _name = TextEditingController();
  bool _register = false;
  bool _hidePassword = true;

  Future<void> _go() async {
    if (!_form.currentState!.validate()) return;
    final st = context.read<AppState>();
    final ok = await st.authenticate(_email.text.trim(), _pass.text,
        name: _register ? _name.text.trim() : null);
    if (ok && mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    return LayoutBuilder(builder: (context, bounds) {
      final desktop = bounds.maxWidth >= 900;
      final panelHeight = (bounds.maxHeight - 56).clamp(520.0, 680.0);
      final panelWidth = (bounds.maxWidth - 56).clamp(840.0, 1080.0);
      final form = _formPanel(context, st, s);
      return Scaffold(
        appBar: desktop
            ? null
            : AppBar(title: Text(_register ? s('register') : s('signIn'))),
        body: desktop
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: SizedBox(
                      width: panelWidth,
                      height: panelHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x160B2A6B),
                                blurRadius: 40,
                                offset: Offset(0, 18))
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 5, child: _welcomePanel()),
                              Expanded(
                                  flex: 5,
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 54, vertical: 44),
                                      child: form)),
                            ]),
                      ),
                    ),
                  ),
                ),
              )
            : SafeArea(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20), child: form)),
      );
    });
  }

  Widget _welcomePanel() => Container(
        padding: const EdgeInsets.all(48),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navy, Color(0xFF1748A0), AppColors.blue]),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.add_road_rounded,
                      color: Colors.white, size: 34)),
              const SizedBox(height: 28),
              const Text('InfraVision',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 35,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7)),
              const Text('Citizen',
                  style: TextStyle(
                      color: Color(0xFFBFD4FF),
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              const Text('Help make your neighborhood safer.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1.35,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const Text(
                  'Report road and street issues, add a location, and follow progress from your desktop.',
                  style: TextStyle(
                      color: Color(0xFFD9E4FF), fontSize: 14, height: 1.6)),
              const SizedBox(height: 30),
              const _Benefit(
                  icon: Icons.add_location_alt_outlined,
                  text: 'Pin an issue on the map'),
              const SizedBox(height: 14),
              const _Benefit(
                  icon: Icons.fact_check_outlined,
                  text: 'Track every report in one place'),
              const SizedBox(height: 14),
              const _Benefit(
                  icon: Icons.notifications_active_outlined,
                  text: 'Get updates as work progresses'),
            ]),
      );

  Widget _formPanel(BuildContext context, AppState st, dynamic s) => Form(
        key: _form,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_register ? 'Create your account' : 'Welcome back',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4)),
              const SizedBox(height: 7),
              Text(
                  _register
                      ? 'Get started reporting local issues.'
                      : 'Sign in to see your reports and updates.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14)),
              const SizedBox(height: 28),
              if (_register) ...[
                TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Enter your name' : null),
                const SizedBox(height: 14),
              ],
              TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                      labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) =>
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v ?? '')
                          ? null
                          : 'Enter a valid email'),
              const SizedBox(height: 14),
              TextFormField(
                  controller: _pass,
                  obscureText: _hidePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _go(),
                  decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                          tooltip:
                              _hidePassword ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined))),
                  validator: (v) => (v ?? '').length < 8
                      ? 'Use at least 8 characters'
                      : null),
              if (st.error != null) ...[
                const SizedBox(height: 14),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFEEEE),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(st.error!,
                              style: const TextStyle(color: AppColors.red)))
                    ])),
              ],
              const SizedBox(height: 22),
              FilledButton(
                  onPressed: st.loading ? null : _go,
                  child: st.loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_register ? s('register') : s('signIn'))),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: st.loading
                      ? null
                      : () => setState(() {
                            _register = !_register;
                            st.error = null;
                          }),
                  child: Text(_register
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account')),
              const SizedBox(height: 18),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('YOUR COMMUNITY',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2))),
                const Expanded(child: Divider())
              ]),
              const SizedBox(height: 12),
              Text('Your account keeps your reports and photos private.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12)),
            ]),
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: const Color(0xFFBFD4FF), size: 20),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ]);
}
