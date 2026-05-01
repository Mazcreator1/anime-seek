import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/scene_challenge.dart';
import '../services/scene_challenge_api.dart';

class GuessScenePage extends StatefulWidget {
  const GuessScenePage({super.key});

  @override
  State<GuessScenePage> createState() => _GuessScenePageState();
}

class _GuessScenePageState extends State<GuessScenePage> {
  SceneChallenge? _challenge;
  SceneChallengeSubmitResult? _result;

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  int _hintsUsed = 0;
  int _revealedHints = 0;
  DateTime? _startedAt;
  String? _selectedOption;

  @override
  void initState() {
    super.initState();
    _loadChallenge();
  }

  Future<void> _loadChallenge() async {
    setState(() {
      _loading = true;
      _submitting = false;
      _error = null;
      _challenge = null;
      _result = null;
      _hintsUsed = 0;
      _revealedHints = 0;
      _selectedOption = null;
    });

    try {
      final challenge = await SceneChallengeApi.getRandomChallenge();
      setState(() {
        _challenge = challenge;
        _startedAt = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submitGuess() async {
    if (_challenge == null || _selectedOption == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final timeTaken =
          _startedAt == null ? null : now.difference(_startedAt!).inMilliseconds;

      final result = await SceneChallengeApi.submitGuess(
        challengeId: _challenge!.id,
        guessedTitle: _selectedOption!,
        hintsUsed: _hintsUsed,
        timeTakenMs: timeTaken,
      );

      setState(() {
        _result = result;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }

    if (mounted) {
      setState(() {
        _submitting = false;
      });
    }
  }

  void _showHint() {
    if (_challenge == null) return;
    if (_revealedHints >= _challenge!.hints.length) return;

    setState(() {
      _revealedHints += 1;
      _hintsUsed += 1;
    });
  }

  double _blurSigma(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return 8;
      case 'medium':
        return 14;
      case 'hard':
        return 20;
      default:
        return 14;
    }
  }

  String _fullImageUrl(String path) {
    if (path.startsWith('http')) return path;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return 'https://anime-seek.com/fastapi$cleanPath';
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guess the Scene'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : challenge == null
                  ? const Center(child: Text('No challenge found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Difficulty: ${challenge.difficulty}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                              children: [
                                Image.network(
                                  _fullImageUrl(challenge.imageUrl),
                                  width: double.infinity,
                                  height: 300,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const SizedBox(
                                      height: 300,
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 300,
                                      color: Colors.black12,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        'Image failed to load\n${_fullImageUrl(challenge.imageUrl)}',
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  },
                                ),
                                if (_result == null)
                                  Positioned.fill(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: _blurSigma(challenge.difficulty),
                                        sigmaY: _blurSigma(challenge.difficulty),
                                      ),
                                      child: Container(
                                        color: Colors.black.withOpacity(0.10),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Multiple choice options
                          ...challenge.options.map((option) {
                            final selected = _selectedOption == option;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        selected ? Colors.white12 : null,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 12,
                                    ),
                                  ),
                                  onPressed: (_result == null && !_submitting)
                                      ? () {
                                          setState(() {
                                            _selectedOption = option;
                                          });
                                        }
                                      : null,
                                  child: Text(
                                    option,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: (_result == null &&
                                          !_submitting &&
                                          _selectedOption != null)
                                      ? _submitGuess
                                      : null,
                                  child: _submitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Submit'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: (_result == null && !_submitting)
                                      ? _showHint
                                      : null,
                                  child: const Text('Hint'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (_revealedHints > 0) ...[
                            const Text(
                              'Hints',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...challenge.hints.take(_revealedHints).map(
                                  (hint) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text('• $hint'),
                                  ),
                                ),
                            const SizedBox(height: 20),
                          ],

                          if (_result != null)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: _result!.correct
                                    ? Colors.green.withOpacity(0.12)
                                    : Colors.red.withOpacity(0.12),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _result!.correct ? 'Correct!' : 'Wrong!',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: _result!.correct
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Answer: ${_result!.answer}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  if (_result!.episode != null) ...[
                                    const SizedBox(height: 6),
                                    Text('Episode: ${_result!.episode}'),
                                  ],
                                  if (_result!.timestamp != null) ...[
                                    const SizedBox(height: 6),
                                    Text('Timestamp: ${_result!.timestamp}'),
                                  ],
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _loadChallenge,
                                    child: const Text('Next Scene'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}