import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/swipe_tab_page.dart';
import 'package:anime_finder/services/audio_service.dart';
import 'package:anime_finder/models/favorites_model.dart';
import 'package:anime_finder/screens/main_recognition_page.dart';
import 'package:anime_finder/models/playlist_model.dart';
import 'package:flutter/foundation.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlaylistsModel>(
      future: _initPlaylistsModel(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AudioService()),
            ChangeNotifierProvider(create: (_) => FavoritesModel()),
            ChangeNotifierProvider<PlaylistsModel>.value(value: snapshot.data!),
          ],
          child: MaterialApp(
            title: 'Anime OP Finder',
            home: const MainRecognitionPage(),
            routes: {
              '/tabs': (_) => const SwipeTabPage(),
            },
          ),
        );
      },
    );
  }

  Future<PlaylistsModel> _initPlaylistsModel() async {
    final model = PlaylistsModel();
    await model.load();
    return model;
  }
}
