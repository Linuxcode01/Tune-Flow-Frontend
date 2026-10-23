import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/features/player/domain/entities/stream_url.dart';

/// HTTP access to streaming and history endpoints.
class PlaybackRemoteDataSource {
  const PlaybackRemoteDataSource(this._client);

  final ApiClient _client;

  Future<StreamUrl> getStreamUrl(String songId) async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.songStream(songId));
    return StreamUrl.fromJson(data);
  }

  Future<void> recordPlayback({
    required String songId,
    required String sessionId,
    required int playedSeconds,
    required bool completed,
    required bool finalUpdate,
  }) async {
    await _client.post(
      ApiEndpoints.history,
      body: <String, dynamic>{
        'songId': songId,
        'sessionId': sessionId,
        'playedSeconds': playedSeconds,
        'completed': completed,
        'finalUpdate': finalUpdate,
      },
    );
  }
}
