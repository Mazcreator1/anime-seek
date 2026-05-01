import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/generated_character.dart';
import '../services/auth_service.dart';
import '../services/character_service.dart';

class CharacterCreatorPage extends StatefulWidget {
  const CharacterCreatorPage({super.key});

  @override
  State<CharacterCreatorPage> createState() => _CharacterCreatorPageState();
}

class _CharacterCreatorPageState extends State<CharacterCreatorPage> {
  final TextEditingController _promptController = TextEditingController();
  final CharacterService _characterService = CharacterService();

  String _selectedStyle = 'anime_portrait';
  String _selectedGender = 'female';
  String _selectedHair = 'black';
  String _selectedEyes = 'blue';
  String _selectedOutfit = 'school';
  String _selectedMood = 'calm';
  bool _showBackstoryTab = false;
  Map<String, dynamic>? _currentUser;
  bool _isLoadingTier = true;
  bool _isGenerating = false;
  GeneratedCharacter? _generatedCharacter;
  final List<GeneratedCharacter> _history = [];

  bool get _canUseBackstoryTab {
  final user = _currentUser;
  if (user == null) return false;
  
  final tierName = (user['tier'] ??
          user['anime_tier'] ??
          user['tier_name'] ??
          user['subscription_tier'] ??
          '')
      .toString()
      .toLowerCase();

  if (tierName == 'otaku' || tierName == 'senpai' || tierName == 'kami') {
    return true;
  }

  final tierIdRaw = user['anime_tier_id'] ?? user['tier_id'];
  final tierId = int.tryParse('$tierIdRaw');

  if (tierId != null && tierId >= 2) {
    return true;
  }

  return false;
  }

  final List<Map<String, String>> _styles = [
  {'value': 'anime_portrait', 'label': 'Anime Portrait'},
  {'value': 'fantasy_hero', 'label': 'Fantasy Hero'},
  {'value': 'school_life', 'label': 'School Life'},
  {'value': 'cyberpunk', 'label': 'Cyberpunk'},
  {'value': 'samurai', 'label': 'Samurai'},
  {'value': 'idol', 'label': 'Idol'},
  {'value': 'mecha_pilot', 'label': 'Mecha Pilot'},
  {'value': 'gothic', 'label': 'Gothic'},
  {'value': 'magical_girl', 'label': 'Magical Girl'},
  {'value': 'villain', 'label': 'Villain'},
  {'value': 'slice_of_life', 'label': 'Slice of Life'},
  {'value': 'shonen_hero', 'label': 'Shonen Hero'},
  {'value': 'royal_princess', 'label': 'Royal Princess'},
  {'value': 'ninja', 'label': 'Ninja'},
  {'value': 'detective', 'label': 'Detective'},
  {'value': 'post_apocalyptic', 'label': 'Post Apocalyptic'},
  {'value': 'demon', 'label': 'Demon'},
  {'value': 'angel', 'label': 'Angel'},
  {'value': 'sports', 'label': 'Sports'},
  ];
  
  String _selectedArtStyle = 'modern_anime';

  final List<Map<String, String>> _artStyles = [
    {'value': 'modern_anime', 'label': 'Modern Anime'},
    {'value': '90s_anime', 'label': '90s Anime'},
    {'value': '80s_anime', 'label': '80s Anime'},
    {'value': 'early_2000s_anime', 'label': 'Early 2000s'},
    {'value': 'retro_ova', 'label': 'Retro OVA'},
    {'value': 'shojo_90s', 'label': '90s Shojo'},
    {'value': 'grainy_vhs_anime', 'label': 'Grainy VHS Anime'},
    {'value': 'cel_shaded_classic', 'label': 'Cel-Shaded Classic'},
  ];

  String _styleLabel(String style) {
  switch (style) {
    case 'anime_portrait':
      return 'Anime Portrait';
    case 'school_life':
      return 'School Life';
    case 'fantasy_hero':
      return 'Fantasy Hero';
    case 'cyberpunk':
      return 'Cyberpunk';
    case 'samurai':
      return 'Samurai';
    case 'ninja':
      return 'Ninja';
    case 'shonen_hero':
      return 'Shonen Hero';
    case 'villain':
      return 'Villain';
    case 'magical_girl':
      return 'Magical Girl';
    case 'idol':
      return 'Idol';
    case 'mecha_pilot':
      return 'Mecha Pilot';
    case 'gothic':
      return 'Gothic';
    case 'royal_princess':
      return 'Royal Princess';
    case 'detective':
      return 'Detective';
    case 'slice_of_life':
      return 'Slice of Life';
    case 'sports':
      return 'Sports';
    case 'post_apocalyptic':
      return 'Post-Apocalyptic';
    case 'demon':
      return 'Demon';
    case 'angel':
      return 'Angel';
    default:
      return style;
  }
}

String _artStyleLabel(String artStyle) {
  switch (artStyle) {
    case 'modern_anime':
      return 'Modern Anime';
    case '90s_anime':
      return '90s Anime';
    case '80s_anime':
      return '80s Anime';
    case 'early_2000s_anime':
      return 'Early 2000s';
    case 'retro_ova':
      return 'Retro OVA';
    case 'shojo_90s':
      return '90s Shojo';
    case 'grainy_vhs_anime':
      return 'Grainy VHS Anime';
    case 'cel_shaded_classic':
      return 'Cel-Shaded Classic';
    default:
      return artStyle;
  }
  }
  final List<String> _genders = ['female', 'male', 'other'];
  final List<String> _hairOptions = ['black', 'brown', 'blonde', 'silver', 'pink', 'blue'];
  final List<String> _eyeOptions = ['blue', 'green', 'brown', 'red', 'purple', 'gold'];
  final List<String> _outfitOptions = ['school', 'fantasy', 'casual', 'battle', 'formal'];
  final List<String> _moodOptions = ['calm', 'happy', 'serious', 'mysterious', 'energetic'];

  final List<String> _postColors = const [
  '#2B2D42',
  '#6D597A',
  '#355070',
  '#7C5CFF',
  '#B56576',
  '#2A9D8F',
  '#E76F51',
  '#1F2937',
];

String _defaultPostColor = '#7C5CFF';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadCurrentUserTier();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _characterService.dispose();
    super.dispose();
  }

  void _showBackstoryLockedMessage() {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'This tab requires credits from the API, so it is unavailable to watcher tiers.',
      ),
    ),
  );
  }

  void _showGenerationLockedMessage() {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Anime generation requires credits from the API, so it is unavailable to watcher tiers.',
      ),
    ),
  );
  }
  String _buildGenerationMeta(GeneratedCharacter character) {
    final parts = <String>[
      if (character.name?.trim().isNotEmpty ?? false)
        'name=${character.name!.trim()}',
      'theme=${_styleLabel(character.style)}',
      'artStyle=${_artStyleLabel(character.artStyle ?? 'modern_anime')}',
      'gender=${character.gender}',
      'hair=${character.hair}',
      'eyes=${character.eyes}',
      'outfit=${character.outfit}',
      'mood=${character.mood}',
    ];

    return 'Generated with: ${parts.join(', ')}';
  }
  Color _colorFromHex(String hex) {
  var value = hex.replaceAll('#', '').trim();
  if (value.length == 6) {
    value = 'FF$value';
  }
  return Color(int.parse(value, radix: 16));
  }

  Color _idealTextColor(Color bg) {
    return bg.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
    }
    Future<void> _loadHistory() async {
      try {
        final items = await _characterService.getHistory();

        if (!mounted) return;

        setState(() {
          _history
            ..clear()
            ..addAll(items);

          if (items.isNotEmpty) {
            _generatedCharacter ??= items.first;
          }
        });
      } catch (e) {
        debugPrint('Character history load failed: $e');

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load character history: $e')),
        );
      }
    }
    
  Future<void> _loadCurrentUserTier() async {
  try {
    final user = await AuthService.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _currentUser = user;
      _isLoadingTier = false;
    });
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _isLoadingTier = false;
    });
  }
  }

  Widget _buildLoreBlock(
    String title,
    String text, {
    bool initiallyExpanded = false,
    }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        iconColor: Colors.black87,
        collapsedIconColor: Colors.black54,
        children: [
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
    }
  Future<void> _generateCharacter() async {
    if (_promptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final result = await _characterService.generateCharacter(
        prompt: _promptController.text.trim(),
        style: _selectedStyle,
        artStyle: _selectedArtStyle,
        gender: _selectedGender,
        hair: _selectedHair,
        eyes: _selectedEyes,
        outfit: _selectedOutfit,
        mood: _selectedMood,
      );

      setState(() {
        _generatedCharacter = result;
        _history.removeWhere((e) => e.id == result.id && result.id != null);
        _history.insert(0, result);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generation failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _postCharacterToFeed() async {
  final character = _generatedCharacter;
  if (character == null) return;

  String captionText = '';
  String selectedColor = _defaultPostColor;
  bool includeGenerationMeta = true;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final previewColor = _colorFromHex(selectedColor);
          final previewTextColor = _idealTextColor(previewColor);

          final previewParts = <String>[
            if (captionText.trim().isNotEmpty) captionText.trim(),
            if (includeGenerationMeta) _buildGenerationMeta(character),
          ];

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FA),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(18),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Create feed post',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: const Icon(Icons.close, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          character.resolvedImageUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 180,
                            color: Colors.grey.shade300,
                            alignment: Alignment.center,
                            child: const Text('Preview unavailable'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: captionText,
                        maxLines: 4,
                        onChanged: (value) {
                          setModalState(() {
                            captionText = value;
                          });
                        },
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Write your caption...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 15,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            borderSide: BorderSide(
                              color: Color(0xFF7C5CFF),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Post color',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _postColors.map((hex) {
                          final selected = selectedColor == hex;
                          return GestureDetector(
                            onTap: () => setModalState(() => selectedColor = hex),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _colorFromHex(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected ? Colors.black : Colors.white,
                                  width: selected ? 3 : 1.5,
                                ),
                              ),
                              child: selected
                                  ? Icon(
                                      Icons.check,
                                      color: _idealTextColor(_colorFromHex(hex)),
                                      size: 18,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile(
                        value: includeGenerationMeta,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Include generation settings',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        subtitle: const Text(
                          'Adds the prompt options used to generate the image',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            includeGenerationMeta = value;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: previewColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: previewColor.withOpacity(0.65),
                          ),
                        ),
                        child: Text(
                          previewParts.isEmpty
                              ? 'Your post preview will appear here'
                              : previewParts.join('\n\n'),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: previewParts.isEmpty
                                ? previewTextColor.withOpacity(0.75)
                                : previewTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C5CFF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: const Icon(Icons.post_add_rounded),
                          label: const Text(
                            'Post to Feed',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  if (confirmed != true || !mounted) return;

  try {
    final imageRes = await http.get(Uri.parse(character.resolvedImageUrl));
    if (imageRes.statusCode != 200) {
      throw Exception('Could not fetch generated image (${imageRes.statusCode})');
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/character_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(imageRes.bodyBytes, flush: true);

    final auth = await AuthService.authHeaders;
    final uri = Uri.parse('https://anime-seek.com/fastapi/posts');
    final req = http.MultipartRequest('POST', uri);

    final headers = Map<String, String>.from(auth);
    headers.removeWhere((k, _) => k.toLowerCase() == 'content-type');
    headers['Accept'] = 'application/json';
    req.headers.addAll(headers);

    final parts = <String>[
      if (captionText.trim().isNotEmpty) captionText.trim(),
      if (includeGenerationMeta) _buildGenerationMeta(character),
    ];

    req.fields['text'] = parts.join('\n\n').trim();
    req.fields['bg_color'] = selectedColor;

    req.files.add(
      await http.MultipartFile.fromPath(
        'image',
        file.path,
        contentType: MediaType('image', 'png'),
      ),
    );

    final res = await req.send();

    if (!mounted) return;

    if (res.statusCode == 200 || res.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posted to feed')),
      );
    } else {
      throw Exception('Post failed (${res.statusCode})');
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to post to feed: $e')),
    );
  }
  }
  Future<void> _shareCharacter() async {
    final character = _generatedCharacter;
    if (character == null) return;

    try {
      final response = await http.get(Uri.parse(character.resolvedImageUrl));
      if (response.statusCode != 200) {
        throw Exception('Image download failed (${response.statusCode})');
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'anime_character_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');

      await file.writeAsBytes(response.bodyBytes);

      final text = '''
        Anime Character

        Prompt: ${character.prompt}
        Theme: ${_styleLabel(character.style)}
        Art Style: ${_artStyleLabel(character.artStyle ?? 'modern_anime')}
        Gender: ${character.gender}
        Hair: ${character.hair}
        Eyes: ${character.eyes}
        Outfit: ${character.outfit}
        Mood: ${character.mood}
        ''';
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: $e')),
      );
    }
  }
  
  
  Future<void> _toggleFavorite() async {
    final current = _generatedCharacter;
    if (current == null || current.id == null) return;

    try {
      final updated = await _characterService.updateFavorite(
        characterId: current.id!,
        isFavorite: !current.isFavorite,
      );

      setState(() {
        _generatedCharacter = updated;
        final index = _history.indexWhere((item) => item.id == updated.id);
        if (index != -1) {
          _history[index] = updated;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.isFavorite ? 'Added to favorites' : 'Removed from favorites',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update favorite: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = const LinearGradient(
      colors: [Color(0xFFF3F0FF), Color(0xFFD6E9FF), Color(0xFFBDD8FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Container(
        decoration: BoxDecoration(gradient: bg),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1150),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEAF8),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 30,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 900;
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: _buildHeroLeft()),
                                const SizedBox(width: 18),
                                Expanded(flex: 2, child: _buildHeroRight()),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeroLeft(),
                              const SizedBox(height: 18),
                              _buildHeroRight(),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      _buildHistorySection(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        Widget tabPill({
          required String label,
          required bool selected,
          required VoidCallback onTap,
          bool enabled = true,
        }) {
          return GestureDetector(
            onTap: enabled ? onTap : _showBackstoryLockedMessage,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: enabled ? 1.0 : 0.45,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEDEAF8)
                      : enabled
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF7C5CFF)
                        : const Color(0xFF5A5A5A),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (!enabled) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: selected ? Colors.black54 : Colors.white70,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: compact
              ? Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            tabPill(
                              label: 'Anime generation',
                              selected: !_showBackstoryTab,
                              onTap: () => setState(() => _showBackstoryTab = false),
                            ),
                            const SizedBox(width: 10),
                            tabPill(
                              label: 'Backstory',
                              selected: _showBackstoryTab,
                              enabled: _canUseBackstoryTab,
                              onTap: () => setState(() => _showBackstoryTab = true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.menu, color: Colors.white),
                    ),
                  ],
                )
              : Row(
                  children: [
                    tabPill(
                      label: 'Anime generation',
                      selected: !_showBackstoryTab,
                      onTap: () => setState(() => _showBackstoryTab = false),
                    ),
                    const SizedBox(width: 12),
                    tabPill(
                      label: 'Backstory',
                      selected: _showBackstoryTab,
                      onTap: () => setState(() => _showBackstoryTab = true),
                    ),
                    const Spacer(),
                    _navText('Community'),
                    const SizedBox(width: 26),
                    _navText('Company'),
                    const SizedBox(width: 26),
                    _navText('Contact'),
                  ],
                ),
        );
      },
    );
  }

  Widget _navText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildHeroLeft() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          'CREATION OF ANIME\nCHARACTER',
          style: TextStyle(
            height: 0.92,
            fontSize: 58,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: -2.0,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          height: 410,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: Colors.white,
            border: Border.all(color: Colors.black12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: _generatedCharacter == null
                ? _buildEmptyPreview()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _generatedCharacter!.resolvedImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildEmptyPreview(
                          message: 'Image preview unavailable',
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 18,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            (_generatedCharacter!.name?.trim().isNotEmpty ?? false)
                            ? '${_generatedCharacter!.name!}\n${_generatedCharacter!.prompt}'
                            : _generatedCharacter!.prompt,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroRight() {
  return Column(
    children: [
      Container(
        height: 255,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFD7D2E8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _generatedCharacter == null
              ? _buildEmptySidePortrait()
              : Image.network(
                  _generatedCharacter!.resolvedImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildEmptySidePortrait(),
                ),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FA),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black26),
        ),
        child: _showBackstoryTab
            ? _buildBackstoryPanel()
            : Opacity(
                opacity: _canUseBackstoryTab ? 1.0 : 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crafting Anime Characters',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _canUseBackstoryTab
                          ? 'Generate, favorite, post, and share stylized anime portraits.'
                          : 'Anime generation requires credits, so it is unavailable to watcher tiers.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildPromptBox(),
                    const SizedBox(height: 14),
                    IgnorePointer(
                      ignoring: !_canUseBackstoryTab,
                      child: Opacity(
                        opacity: _canUseBackstoryTab ? 1.0 : 0.6,
                        child: _buildControlsPanel(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildActionRow(),
                  ],
                ),
              ),
      ),
    ],
  );
  }

  Widget _buildBackstoryPanel() {
  if (_isLoadingTier) {
  return const Center(
    child: CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7C5CFF)),
    ),
  );
  }

  if (!_canUseBackstoryTab) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: const Text(
        'This tab requires credits, so it is unavailable to free users.',
        style: TextStyle(
          color: Colors.black87,
          height: 1.45,
        ),
      ),
    );
  }

  final character = _generatedCharacter;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Character Backstory',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: Colors.black,
        ),
      ),
      const SizedBox(height: 10),
      if (character == null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: const Text(
            'Generate a character first to view the name, backstory, and story scene.',
            style: TextStyle(
              color: Colors.black87,
              height: 1.45,
            ),
          ),
        )
      else if ((character.name?.trim().isEmpty ?? true) &&
          (character.backstory?.trim().isEmpty ?? true) &&
          (character.storyScene?.trim().isEmpty ?? true))
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: const Text(
            'No backstory data was returned for this character yet.',
            style: TextStyle(
              color: Colors.black87,
              height: 1.45,
            ),
          ),
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (character.name?.trim().isNotEmpty ?? false) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(
                  character.name!.trim(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (character.backstory?.trim().isNotEmpty ?? false) ...[
              _buildLoreBlock('Backstory', character.backstory!.trim()),
              const SizedBox(height: 12),
            ],
            if (character.storyScene?.trim().isNotEmpty ?? false)
              _buildLoreBlock('Story Scene', character.storyScene!.trim(), initiallyExpanded: true),
          ],
        ),
    ],
  );
  }
  Widget _buildPromptBox() {
    return TextField(
      controller: _promptController,
      enabled: _canUseBackstoryTab,
      maxLines: 3,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        hintText: _canUseBackstoryTab
            ? 'Describe your anime character...'
            : 'Otaku tier or higher required',
        hintStyle: TextStyle(color: Colors.grey.shade600),
        filled: true,
        fillColor: _canUseBackstoryTab
            ? Colors.white
            : Colors.grey.shade200,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }

  Widget _buildControlsPanel() {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFE9E4F4),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.black12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSelectionRow(
          title: 'Style',
          value: _selectedStyle,
          items: _styles.map((e) => e['value']!).toList(),
          onChanged: (v) => setState(() => _selectedStyle = v!),
        ),
        _buildSelectionRow(
          title: 'Art Style',
          value: _selectedArtStyle,
          items: _artStyles.map((e) => e['value']!).toList(),
          onChanged: (v) => setState(() => _selectedArtStyle = v!),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMiniDropdown(
                label: 'Gender',
                value: _selectedGender,
                items: _genders,
                onChanged: (v) => setState(() => _selectedGender = v!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniDropdown(
                label: 'Hair',
                value: _selectedHair,
                items: _hairOptions,
                onChanged: (v) => setState(() => _selectedHair = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMiniDropdown(
                label: 'Eyes',
                value: _selectedEyes,
                items: _eyeOptions,
                onChanged: (v) => setState(() => _selectedEyes = v!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniDropdown(
                label: 'Outfit',
                value: _selectedOutfit,
                items: _outfitOptions,
                onChanged: (v) => setState(() => _selectedOutfit = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildMiniDropdown(
          label: 'Mood',
          value: _selectedMood,
          items: _moodOptions,
          onChanged: (v) => setState(() => _selectedMood = v!),
        ),
      ],
    ),
  );
  }

  Widget _buildSelectionRow({
    required String title,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.black87,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final selected = item == value;
            return GestureDetector(
              onTap: () => onChanged(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? Colors.black : Colors.black12,
                  ),
                ),
                child: Text(
                  title == 'Art Style' ? _artStyleLabel(item) : _styleLabel(item),
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMiniDropdown({
  required String label,
  required String value,
  required List<String> items,
  required ValueChanged<String?> onChanged,
  }) {
  return DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    dropdownColor: Colors.white,
    style: const TextStyle(
      fontSize: 13,
      color: Colors.black87,
      fontWeight: FontWeight.w600,
    ),
    iconEnabledColor: Colors.black87,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontSize: 14,
        color: Color(0xFF4B5563), // darker label
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        fontSize: 14,
        color: Color(0xFF4B5563), // darker floating label
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: const Color(0xFFF7F7FB), // box color
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: Color(0xFF7C5CFF),
          width: 2,
        ),
      ),
    ),
    items: items
        .map(
          (item) => DropdownMenuItem<String>(
            value: item,
            child: Text(
              item,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );
  }
  Widget _buildActionRow() {
  final hasCharacter = _generatedCharacter != null;

  return Wrap(
    spacing: 10,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _roundIconButton(
        icon: Icons.favorite,
        active: _generatedCharacter?.isFavorite == true,
        onTap: !hasCharacter || _generatedCharacter?.id == null
            ? null
            : _toggleFavorite,
      ),
      _roundIconButton(
        icon: Icons.post_add_rounded,
        onTap: hasCharacter ? _postCharacterToFeed : null,
      ),
      _roundIconButton(
        icon: Icons.ios_share_rounded,
        onTap: hasCharacter ? _shareCharacter : null,
      ),
      SizedBox(
        height: 44,
        child: ElevatedButton.icon(
          onPressed: !_canUseBackstoryTab
              ? _showGenerationLockedMessage
              : (_isGenerating ? null : _generateCharacter),
          style: ElevatedButton.styleFrom(
            backgroundColor: !_canUseBackstoryTab
                ? Colors.grey.shade500
                : const Color(0xFF7C5CFF),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          icon: _isGenerating && _canUseBackstoryTab
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
              : Icon(
                  !_canUseBackstoryTab ? Icons.lock_outline : Icons.auto_awesome,
                  size: 18,
                ),
          label: Text(
            !_canUseBackstoryTab
                ? 'Higher tier Required'
                : (_isGenerating ? 'Generating...' : 'Generate'),
          ),
        ),
      ),
    ],
  );
  }

  Widget _roundIconButton({
    required IconData icon,
    VoidCallback? onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.grey.shade300
              : active
                  ? const Color(0xFFFF4D6D)
                  : Colors.black,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.grey.shade600 : Colors.white,
        ),
      ),
    );
  }

  Widget _buildEmptyPreview({String message = 'Generated character will appear here'}) {
    return Container(
      color: const Color(0xFFDCD7EA),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySidePortrait() {
    return Container(
      color: const Color(0xFFD7D2E8),
      alignment: Alignment.center,
      child: const Icon(Icons.auto_awesome, size: 56, color: Colors.black54),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Creations',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        if (_history.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: const Text(
              'No creations yet',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          )
        else
          SizedBox(
            height: 138,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _history.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = _history[index];
                final selected = identical(item, _generatedCharacter) || item.id == _generatedCharacter?.id;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _generatedCharacter = item;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 118,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? const Color(0xFF7C5CFF) : Colors.black12,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                                child: Image.network(
                                  item.resolvedImageUrl,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey.shade300,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.image_not_supported),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _styleLabel(item.style),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _artStyleLabel(item.artStyle ?? 'modern_anime'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (item.isFavorite)
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.favorite,
                                size: 14,
                                color: Color(0xFFFF4D6D),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}