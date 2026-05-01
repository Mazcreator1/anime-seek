// lib/widgets/poll_card.dart
import 'package:flutter/material.dart';
import '../models/post.dart';

typedef OnVote = Future<Post> Function(List<int> optionIds);

class PollCard extends StatefulWidget {
  const PollCard({super.key, required this.post, required this.onVote});
  final Post post;
  final OnVote onVote;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final Set<int> _selected = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.post.poll?.votedOptionIds ?? const <int>[]);
  }

  @override
  void didUpdateWidget(covariant PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selected
      ..clear()
      ..addAll(widget.post.poll?.votedOptionIds ?? const <int>[]);
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.post.poll!;
    final canVote = poll.canVote;

    // ... keep your existing build UI (options, buttons, etc.) unchanged
    // (the rest of your original file content follows)
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(poll.question, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...poll.options.map((opt) {
              final total = poll.totalVotes;
              final pct = total == 0 ? 0.0 : (opt.voteCount / total);
              final alreadyVoted = poll.votedOptionIds.isNotEmpty;

              if (poll.multiple) {
                final checked = _selected.contains(opt.id);
                return _OptionRow(
                  text: opt.text,
                  percent: pct,
                  showResult: alreadyVoted || !canVote,
                  control: Checkbox(
                    value: checked,
                    onChanged: (!canVote || _submitting)
                        ? null
                        : (v) => setState(() {
                      if (v == true) _selected.add(opt.id);
                      else _selected.remove(opt.id);
                    }),
                  ),
                );
              } else {
                final selected = _selected.contains(opt.id);
                return _OptionRow(
                  text: opt.text,
                  percent: pct,
                  showResult: alreadyVoted || !canVote,
                  control: Radio<int>(
                    value: opt.id,
                    groupValue: selected ? opt.id : (_selected.isEmpty ? null : _selected.first),
                    onChanged: (!canVote || _submitting)
                        ? null
                        : (_) => setState(() {
                      _selected
                        ..clear()
                        ..add(opt.id);
                    }),
                  ),
                );
              }
            }),
            const SizedBox(height: 12),
            Row(children: [
              Text(
                '${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'}'
                    '${poll.isClosed ? ' • closed' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              if (canVote)
                FilledButton(
                  onPressed: _submitting || _selected.isEmpty
                      ? null
                      : () async {
                    setState(() => _submitting = true);
                    try {
                      final updated = await widget.onVote(_selected.toList());
                      setState(() {
                        _submitting = false;
                        _selected
                          ..clear()
                          ..addAll(updated.poll?.votedOptionIds ?? const <int>[]);
                      });
                    } catch (_) {
                      setState(() => _submitting = false);
                    }
                  },
                  child: const Text('Vote'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.text,
    required this.percent,
    required this.showResult,
    required this.control,
  });

  final String text;
  final double percent;
  final bool showResult;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final pctLabel = '${(percent * 100).toStringAsFixed(0)}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        control,
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text),
            if (showResult)
              Stack(children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percent.clamp(0.0, 1.0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ]),
          ]),
        ),
        const SizedBox(width: 8),
        if (showResult) Text(pctLabel, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
