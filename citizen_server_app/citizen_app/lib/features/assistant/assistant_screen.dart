import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/theme/app_theme.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _messages = <({String text, bool fromUser})>[];
  bool? _ready;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (mounted) {
      setState(() {
        _ready = null;
        _error = null;
      });
    }
    try {
      final ready = await context.read<AppState>().api.aiReady();
      if (mounted) setState(() => _ready = ready);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.length < 2 || _sending) return;
    final st = context.read<AppState>();
    setState(() {
      _messages.add((text: text, fromUser: true));
      _sending = true;
      _error = null;
    });
    _input.clear();
    try {
      final answer = await st.api.askAI(text, st.lang);
      if (mounted) {
        setState(() => _messages.add((text: answer, fromUser: false)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AI Assistant')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(children: [
            if (_ready == false)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('AI assistant is not configured'),
                        subtitle: Text(
                            'Set AI_PROVIDER, AI_BASE_URL and AI_MODEL in backend/.env. Ollama does not need an API key; hosted providers do. Restart the server after changing it.'))),
              ),
            if (_ready == null && _error == null)
              const LinearProgressIndicator(),
            if (_ready == null && _error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text('AI service status unavailable'),
                    subtitle:
                        Text('Check the server connection, then retry. $_error'),
                    trailing: TextButton(
                        onPressed: _checkStatus, child: const Text('Retry')),
                  ),
                ),
              ),
            if (_error != null && _ready == true)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            Expanded(
                child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return Align(
                          alignment: message.fromUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              constraints: const BoxConstraints(maxWidth: 650),
                              decoration: BoxDecoration(
                                  color: message.fromUser
                                      ? AppColors.blue
                                      : Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(16)),
                              child: Text(message.text,
                                  style: TextStyle(
                                      color: message.fromUser
                                          ? Colors.white
                                          : null))));
                    })),
            Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _input,
                          enabled: _ready == true && !_sending,
                          minLines: 1,
                          maxLines: 4,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                              hintText: 'Ask about reporting a civic issue',
                              border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      onPressed: _ready == true && !_sending ? _send : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send)),
                ])),
          ]),
        )),
      );
}
