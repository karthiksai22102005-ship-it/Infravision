import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/config/app_config.dart';
import '../../core/localization/languages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    return Scaffold(
      appBar: AppBar(title: Text(s('profile'))),
      bottomNavigationBar: const AppBottomNav(4),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              Text('Your account',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: st.api.me(),
                builder: (_, snap) {
                  final name = snap.data?['full_name'] as String? ??
                      'InfraVision Citizen';
                  final email = snap.data?['email'] as String? ??
                      (snap.hasError ? s('offline') : '');
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      leading: const CircleAvatar(
                          radius: 27,
                          child: Icon(Icons.person_outline, size: 28)),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(email),
                      trailing: const Icon(Icons.verified_user_outlined,
                          color: AppColors.green),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(s('settings'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.palette_outlined),
                          const SizedBox(width: 10),
                          Text(s('appearance'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700))
                        ]),
                        const SizedBox(height: 12),
                        Wrap(spacing: 10, runSpacing: 8, children: [
                          _ThemeOption(
                              label: 'System',
                              value: 'system',
                              icon: Icons.settings_suggest_outlined,
                              selected: st.themePreference,
                              onSelected: st.setTheme),
                          _ThemeOption(
                              label: 'Light',
                              value: 'light',
                              icon: Icons.light_mode_outlined,
                              selected: st.themePreference,
                              onSelected: st.setTheme),
                          _ThemeOption(
                              label: 'Dark',
                              value: 'dark',
                              icon: Icons.dark_mode_outlined,
                              selected: st.themePreference,
                              onSelected: st.setTheme),
                        ]),
                      ]),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
                            child: Row(children: [
                              const Icon(Icons.language),
                              const SizedBox(width: 10),
                              Text(s('language'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ])),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: languageFor(st.lang).code,
                          isExpanded: true,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface),
                          iconEnabledColor:
                              Theme.of(context).colorScheme.onSurface,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.translate),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final language in appLanguages)
                              DropdownMenuItem(
                                  value: language.code,
                                  child: Text(language.label,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              st.setLanguage(value);
                            }
                          },
                        ),
                      ]),
                ),
              ),
              const SizedBox(height: 24),
              Text('App settings',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Server connection'),
                  subtitle: Text(AppConfig.apiBaseUrl),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editServerUrl(context, st),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                  child: ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(s('notifications')),
                subtitle: const Text('View updates about your reports'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, '/notifications'),
              )),
              const SizedBox(height: 8),
              Card(
                  child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About InfraVision Citizen'),
                subtitle: const Text('Version 1.0.0 · Report, track, improve'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'InfraVision Citizen',
                  applicationVersion: '1.0.0',
                  applicationIcon: const Icon(Icons.add_road_rounded,
                      color: AppColors.blue, size: 36),
                  children: const [
                    Text(
                        'A community app for reporting and tracking local infrastructure issues.')
                  ],
                ),
              )),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: Text(s('signOut')),
                onPressed: () async {
                  await st.signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/auth', (_) => false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _editServerUrl(BuildContext context, AppState state) async {
  final controller = TextEditingController(text: AppConfig.apiBaseUrl);
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Server connection'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Server URL',
          hintText: 'http://192.168.1.20:8000',
          helperText: 'Use a URL reachable from this phone.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, ''),
          child: const Text('Use default'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (value == null || !context.mounted) return;
  try {
    await state.setServerUrl(value);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Server URL saved. The next server request will use it.')),
      );
    }
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption(
      {required this.label,
      required this.value,
      required this.icon,
      required this.selected,
      required this.onSelected});
  final String label;
  final String value;
  final IconData icon;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return ChoiceChip(
      selected: active,
      avatar: Icon(icon,
          size: 18,
          color: active ? Theme.of(context).colorScheme.onPrimary : null),
      label: Text(label),
      onSelected: (_) => onSelected(value),
    );
  }
}
