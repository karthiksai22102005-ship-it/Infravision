import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/localization/languages.dart';
import '../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _continueTimer;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    if (st.initialized && st.store.onboarded) {
      _continueTimer = Timer(const Duration(milliseconds: 550), () {
        if (mounted) {
          Navigator.pushReplacementNamed(
              context, st.signedIn ? '/home' : '/auth');
        }
      });
    }
  }

  @override
  void dispose() {
    _continueTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final firstLaunch = !st.initialized || !st.store.onboarded;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/images/city_road_sunrise.png', fit: BoxFit.cover),
        const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33213F70), Color(0x08304C79), Color(0xB8081B3D)],
          stops: [0, .48, 1],
        ))),
        SafeArea(
          child: LayoutBuilder(builder: (context, bounds) {
            final compact = bounds.maxWidth < 620;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: compact ? 24 : 56, vertical: 24),
                  child: Column(children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Image.asset('assets/images/app_icon.png',
                            width: 38, height: 38),
                        const SizedBox(width: 10),
                        const Text('InfraVision Citizen',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const Spacer(flex: 2),
                    Container(
                      width: compact ? 82 : 100,
                      height: compact ? 82 : 100,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .96),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x55071938),
                                blurRadius: 28,
                                offset: Offset(0, 10))
                          ]),
                      child: ClipOval(
                          child: Image.asset('assets/images/app_icon.png',
                              fit: BoxFit.cover)),
                    ),
                    const SizedBox(height: 22),
                    Text('InfraVision',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 38 : 54,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.9,
                            shadows: const [
                              Shadow(
                                  color: Color(0x99091A36),
                                  blurRadius: 16,
                                  offset: Offset(0, 3))
                            ])),
                    const SizedBox(height: 6),
                    const Text('CITIZEN',
                        style: TextStyle(
                            color: Color(0xFFEBF1FB),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 5)),
                    const SizedBox(height: 18),
                    Text(st.s('tagline'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Color(0xAA091A36), blurRadius: 10)
                            ])),
                    if (firstLaunch)
                      const Spacer(flex: 3)
                    else
                      const Spacer(flex: 4),
                    if (firstLaunch)
                      Container(
                        constraints: const BoxConstraints(maxWidth: 560),
                        padding: EdgeInsets.all(compact ? 16 : 22),
                        decoration: BoxDecoration(
                            color: const Color(0xEAF8FAFF),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .8)),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x33071938),
                                  blurRadius: 28,
                                  offset: Offset(0, 12))
                            ]),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              st.initialized
                                  ? st.s('chooseLanguage')
                                  : 'InfraVision could not finish startup',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      color: st.initialized
                                          ? AppColors.navy
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          if (!st.initialized && st.startupError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                st.startupError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ),
                          if (st.initialized) ...[
                            DropdownButtonFormField<String>(
                              initialValue: languageFor(st.lang).code,
                              isExpanded: true,
                              style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                              iconEnabledColor: AppColors.navy,
                              dropdownColor: Colors.white,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.translate,
                                    color: AppColors.navy),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFCBD5E1))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFCBD5E1))),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                              selectedItemBuilder: (BuildContext context) {
                                return appLanguages
                                    .map<Widget>((AppLanguage lang) {
                                  return Text(
                                    lang.label,
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                }).toList();
                              },
                              items: [
                                for (final language in appLanguages)
                                  DropdownMenuItem(
                                      value: language.code,
                                      child: Text(
                                        language.label,
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ))
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  st.setLanguage(value);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () async {
                                final navigator = Navigator.of(context);
                                if (!st.initialized) {
                                  await st.initialize();
                                  if (!mounted || !st.initialized) return;
                                }
                                st.store.onboarded = true;
                                navigator.pushReplacementNamed(
                                    st.signedIn ? '/home' : '/auth');
                              },
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: Text(
                                  st.initialized
                                      ? st.s('getStarted')
                                      : st.s('retry'),
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  backgroundColor: AppColors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14))),
                            ),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }
}
