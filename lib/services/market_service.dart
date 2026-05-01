// lib/services/market_service.dart
import 'package:anime_finder/services/api_service.dart';

class MarketService {
  static Future<void> enterMarket({
    required int marketId,
    required int outcomeId,
    required int stakeAmount,
  }) async {
    await ApiService.instance.postJson(
      "/markets/$marketId/enter",
      {
        "outcome_id": outcomeId,
        "stake_amount": stakeAmount,
      },
    );
  }
}
