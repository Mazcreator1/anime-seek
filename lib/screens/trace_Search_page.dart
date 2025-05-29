// lib/screens/TraceSearchPage.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';

class TraceSearchPage extends StatefulWidget {
  const TraceSearchPage({Key? key}) : super(key: key);

  @override
  State<TraceSearchPage> createState() => _TraceSearchPageState();
}

class _TraceSearchPageState extends State<TraceSearchPage> {
  final ImagePicker _picker = ImagePicker();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://10.0.2.2:3311',
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final TextEditingController _urlController = TextEditingController();

  bool _isLoading = false;
  bool _isPicking = false;
  List<Map<String, dynamic>> _results = [];

  String _formatHMS(num secondsRaw) {
    final total = secondsRaw.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${h.toString().padLeft(2, '0')}.'
        '${m.toString().padLeft(2, '0')}.'
        '${s.toString().padLeft(2, '0')}';
  }

  Future<void> _searchByImage() async {
    if (_isPicking) return;
    _isPicking = true;
    setState(() => _isLoading = true);
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      final bytes = await File(file.path).readAsBytes();
      final resp = await _dio.post(
        '/search?anilistInfo=true',
        data: Stream.fromIterable(bytes.map((b) => [b])),
        options: Options(
          headers: {'Content-Type': 'image/jpeg'},
          responseType: ResponseType.json,
        ),
      );
      if (resp.statusCode != 200) throw Exception('Server returned ${resp.statusCode}');
      final list = (resp.data['result'] as List).cast<Map<String, dynamic>>();
      debugPrint('Search results (image): $list');
      setState(() => _results = list);
    } catch (e, st) {
      debugPrint('Search error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _isPicking = false;
      });
    }
  }

  Future<void> _searchByUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid image URL.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final resp = await _dio.get(
        '/search',
        queryParameters: {'url': url, 'anilistInfo': 'true'},
      );
      if (resp.statusCode != 200) throw Exception('Server returned ${resp.statusCode}');
      final list = (resp.data['result'] as List).cast<Map<String, dynamic>>();
      debugPrint('Search results (URL): $list');
      setState(() => _results = list);
    } catch (e, st) {
      debugPrint('URL search error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search by URL failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showDetails(Map<String, dynamic> item) {
    final ani = item['anilist'] as Map<String, dynamic>? ?? {};
    final titleMap = ani['title'] as Map<String, dynamic>? ?? {};
    final romaji = titleMap['romaji'] ?? '[Unknown]';
    final english = titleMap['english'];
    final native = titleMap['native'];

    final episodes = ani['episodes']?.toString() ?? '';
    final duration = ani['duration']?.toString() ?? '';
    final format = ani['format'] ?? '';
    final start = ani['startDate'] as Map<String, dynamic>? ?? {};
    final end = ani['endDate'] as Map<String, dynamic>? ?? {};
    final startStr = start.isNotEmpty
        ? '${start['year']}-${start['month']}-${start['day']}'
        : '';
    final endStr = end.isNotEmpty
        ? '${end['year']}-${end['month']}-${end['day']}'
        : '';

    final synonyms = (ani['synonyms'] as List<dynamic>?)
        ?.cast<String>()
        .join(', ') ??
        '';
    final genres = (ani['genres'] as List<dynamic>?)
        ?.cast<String>()
        .join(', ') ??
        '';
    final studios = (ani['studios']?['edges'] as List<dynamic>?)
        ?.map((e) => e['node']?['name'] as String)
        .toList() ??
        [];
    final links = (ani['externalLinks'] as List<dynamic>?)
        ?.map((e) => '${e['site']}: ${e['url']}')
        .join('\n') ??
        '';

    final cover = (ani['coverImage'] as Map<String, dynamic>?)?['large'] ?? '';
    final sim = (item['similarity'] as num?) ?? 0.0;
    final simPct = (sim * 100).toStringAsFixed(2) + '%';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: cover.isNotEmpty
                    ? Image.network(
                  cover,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                  const SizedBox(height: 180),
                )
                    : const SizedBox(
                  height: 180,
                  child: Icon(Icons.broken_image, size: 48),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                romaji,
                style:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (english != null)
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                          text: 'English: ',
                          style: TextStyle(color: Colors.teal)),
                      TextSpan(
                          text: english,
                          style: const TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              if (native != null)
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                          text: 'Native: ',
                          style: TextStyle(color: Colors.teal)),
                      TextSpan(
                          text: native,
                          style: const TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (episodes.isNotEmpty && duration.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                          text: 'Episodes: ',
                          style: TextStyle(color: Colors.teal)),
                      TextSpan(
                          text: '$episodes',
                          style: const TextStyle(color: Colors.black)),
                      const TextSpan(
                          text: '   Duration: ',
                          style: TextStyle(color: Colors.teal)),
                      TextSpan(
                          text: '$duration min',
                          style: const TextStyle(color: Colors.black)),
                      if (format.isNotEmpty)
                        const TextSpan(
                            text: '   Format: ',
                            style: TextStyle(color: Colors.teal)),
                      if (format.isNotEmpty)
                        TextSpan(
                            text: format,
                            style: const TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              if (startStr.isNotEmpty || endStr.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                          text: 'Airing: ',
                          style: TextStyle(color: Colors.teal)),
                      TextSpan(
                          text: startStr,
                          style: const TextStyle(color: Colors.black)),
                      if (endStr.isNotEmpty)
                        const TextSpan(
                            text: ' → ',
                            style: TextStyle(color: Colors.teal)),
                      if (endStr.isNotEmpty)
                        TextSpan(
                            text: endStr,
                            style: const TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                        text: 'Similarity: ',
                        style: TextStyle(color: Colors.teal)),
                    TextSpan(
                        text: simPct,
                        style: const TextStyle(color: Colors.black)),
                  ],
                ),
              ),
              const Divider(height: 24),
              if ((ani['description'] as String?)?.isNotEmpty ?? false)
                Text((ani['description'] as String)),
              if (synonyms.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                          text: 'Alias: ',
                          style: TextStyle(color: Colors.teal)),
                      TextSpan(
                          text: synonyms,
                          style: const TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              if (genres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                            text: 'Genres: ',
                            style: TextStyle(color: Colors.teal)),
                        TextSpan(
                            text: genres,
                            style: const TextStyle(color: Colors.black)),
                      ],
                    ),
                  ),
                ),
              if (studios.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                            text: 'Studios: ',
                            style: TextStyle(color: Colors.teal)),
                        TextSpan(
                            text: studios.join(', '),
                            style: const TextStyle(color: Colors.black)),
                      ],
                    ),
                  ),
                ),
              if (links.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                            text: 'External Links:\n',
                            style: TextStyle(color: Colors.teal)),
                        TextSpan(
                            text: links,
                            style: const TextStyle(color: Colors.black)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _results.isNotEmpty;
    Map<String, dynamic>? top;
    String topCover = '', topTitle = '', topSim = '0.00%';

    if (hasResults) {
      top = _results[0];
      final ani = top['anilist'] as Map<String, dynamic>? ?? {};
      topCover =
          (ani['coverImage'] as Map<String, dynamic>?)?['large'] ?? '';
      topTitle =
          ((ani['title'] as Map<String, dynamic>?)?['romaji']) ?? '[Unknown]';
      final sim = (top['similarity'] as num?) ?? 0.0;
      topSim = (sim * 100).toStringAsFixed(2) + '%';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scene Search')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchByUrl(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
                onPressed: _searchByUrl, child: const Text('Search by URL')),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _searchByImage, child: const Text('Upload Image')),
            const SizedBox(height: 12

            ),

            if (_isLoading) const Center(child: CircularProgressIndicator()),

            if (!_isLoading)
              Expanded(
                child: hasResults
                    ? SingleChildScrollView(
                  child: Column(
                    children: [
                      // — Big top cover —
                      GestureDetector(
                        onTap: () => _showDetails(top!),
                        child: Column(
                          children: [
                            Text(topTitle,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text('Similarity: $topSim'),
                            const SizedBox(height: 8),
                            topCover.isNotEmpty
                                ? Image.network(
                              topCover,
                              height: 180,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                              const SizedBox(height: 180),
                            )
                                : const SizedBox(
                              height: 180,
                              child: Icon(Icons.broken_image,
                                  size: 48),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),

                      // — Thumbnails of other hits —
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.zero,
                          itemCount: _results.length - 1,
                          itemBuilder: (_, i) {
                            final item = _results[i + 1];
                            final ani = item['anilist']
                            as Map<String, dynamic>? ??
                                {};
                            final thumb = (ani['coverImage']
                            as Map<String, dynamic>?)?[
                            'medium'] ??
                                '';
                            final sim =
                                (item['similarity'] as num?) ?? 0.0;
                            final simPct =
                                (sim * 100).toStringAsFixed(1) + '%';

                            return GestureDetector(
                              onTap: () => _showDetails(item),
                              child: Container(
                                width: 100,
                                margin:
                                const EdgeInsets.only(right: 12),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: thumb.isNotEmpty
                                          ? Image.network(
                                        thumb,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (_, __, ___) =>
                                        const Icon(Icons
                                            .broken_image),
                                      )
                                          : const Icon(
                                          Icons.broken_image),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(simPct,
                                        style: const TextStyle(
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                )
                    : const Center(child: Text('No matches found.')),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Information provided by anilist.co™',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ),
    );
  }
}
