import 'package:flutter/material.dart';
import 'package:anime_finder/models/position.dart';
import 'package:anime_finder/services/api_service.dart';
import 'position_detail_page.dart';

class MyPositionsPage extends StatefulWidget {
  const MyPositionsPage({super.key});

  @override
  State<MyPositionsPage> createState() => _MyPositionsPageState();
}

class _MyPositionsPageState extends State<MyPositionsPage> {
  late Future<List<Position>> positions;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<List<Position>> _fetch() async {
    // ✅ correct backend route
    final json = await ApiService.instance.getJson("/markets/me/positions");
    if (json is List) {
      return json.map((e) => Position.fromJson(e)).toList();
    }
    return [];
  }

  void _reload() {
    positions = _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Positions")),
      body: FutureBuilder<List<Position>>(
        future: positions,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No positions yet"));
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _reload());
            },
            child: ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final p = snapshot.data![index];
                return ListTile(
                  title: Text("Market #${p.marketId}"),
                  subtitle: Text("Stake: ${p.stake} coins"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PositionDetailPage(position: p),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
