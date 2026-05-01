import 'package:anime_finder/services/api_service.dart';
import 'package:anime_finder/models/position.dart';

class PositionsService {
  static Future<List<Position>> fetchMyPositions() async {
    final data = await ApiService.instance.getJsonList("/markets/me/positions");
    return data
        .map((p) => Position.fromJson(p as Map<String, dynamic>))
        .toList();
  }
}