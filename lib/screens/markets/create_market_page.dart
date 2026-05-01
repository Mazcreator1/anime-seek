import 'package:flutter/material.dart';
import 'package:anime_finder/services/api_service.dart';

class CreateMarketPage extends StatefulWidget {
  const CreateMarketPage({super.key});

  @override
  State<CreateMarketPage> createState() => _CreateMarketPageState();
}

class _CreateMarketPageState extends State<CreateMarketPage> {
  final _title = TextEditingController(text: 'Market');
  final _desc = TextEditingController(text: 'Test');
  final _category = TextEditingController(text: 'test');
  final _outcomes = TextEditingController(text: 'YES,NO');

  final _closeMinutes = TextEditingController(text: '60');
  final _resolveMinutes = TextEditingController(text: '65');

  bool submitting = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _category.dispose();
    _outcomes.dispose();
    _closeMinutes.dispose();
    _resolveMinutes.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  Future<void> _submit() async {
    if (submitting) return;

    final title = _title.text.trim();
    final desc = _desc.text.trim();
    final category = _category.text.trim().isEmpty ? 'test' : _category.text.trim();

    final outcomeLabels = _outcomes.text
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();

    final closeM = int.tryParse(_closeMinutes.text.trim()) ?? 60;
    final resolveM = int.tryParse(_resolveMinutes.text.trim()) ?? (closeM + 5);

    if (title.isEmpty) {
      _toast('Title is required', error: true);
      return;
    }
    if (outcomeLabels.length < 2) {
      _toast('Provide at least 2 outcomes (comma-separated)', error: true);
      return;
    }
    if (resolveM <= closeM) {
      _toast('Resolve minutes must be greater than close minutes', error: true);
      return;
    }

    // Model 1 hard rule (YES/NO only)
    final setLabels = outcomeLabels.toSet();
    if (!(setLabels.contains('YES') && setLabels.contains('NO')) || setLabels.length != 2) {
      _toast('Outcomes must be exactly: YES,NO', error: true);
      return;
    }

    setState(() => submitting = true);

    try {
      final now = DateTime.now().toUtc();
      final openTime = now;
      final closeTime = now.add(Duration(minutes: closeM));
      final resolveTime = now.add(Duration(minutes: resolveM));

      // backend accepts list of objects [{"label":"YES"},{"label":"NO"}]
      final outcomes = outcomeLabels.map((lab) => <String, dynamic>{'label': lab}).toList();

      final payload = <String, dynamic>{
        'title': title,
        'description': desc,
        'category': category,
        'open_time': openTime.toIso8601String(),
        'close_time': closeTime.toIso8601String(),
        'resolve_time': resolveTime.toIso8601String(),
        'resolution_source': 'manual',
        'resolution_data': <String, dynamic>{},
        'outcomes': outcomes,
      };

      // ✅ IMPORTANT:
      // ApiService already prefixes with /fastapi internally,
      // so DO NOT include /fastapi here.
      await ApiService.instance.postJson('/admin/markets', payload);

      if (!mounted) return;
      _toast('Market created');
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Create failed: $e', error: true);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Market (Dev)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _outcomes,
            decoration: const InputDecoration(
              labelText: 'Outcomes (comma-separated)',
              hintText: 'YES,NO',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _closeMinutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Close in (minutes)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _resolveMinutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Resolve in (minutes)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Market'),
            ),
          ),
        ],
      ),
    );
  }
}
