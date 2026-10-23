import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';

/// A download record (`GET /downloads`).
///
/// The two-phase model matters: the client asks for a download to be *created* (which reserves it and
/// returns a signed URL plus a licence expiry), fetches the bytes, then *completes* it. Only the
/// completion bumps the server-side counters, which is why the download count is accurate rather than
/// optimistic.
class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.song,
    this.deviceId,
    this.status = 'PENDING',
    this.bitrateKbps,
    this.sizeBytes,
    this.downloadUrl,
    this.licenceExpiresAt,
    this.downloadedAt,
    this.createdAt,
  });

  factory DownloadRecord.fromJson(Map<String, dynamic> json) {
    return DownloadRecord(
      id: json['id'] as String? ?? '',
      song: Song.fromJson((json['song'] as Map<String, dynamic>?) ?? const <String, dynamic>{}),
      deviceId: json['deviceId'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      bitrateKbps: (json['bitrateKbps'] as num?)?.toInt(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      downloadUrl: json['downloadUrl'] as String?,
      licenceExpiresAt: DateTime.tryParse(json['licenceExpiresAt'] as String? ?? '')?.toUtc(),
      downloadedAt: DateTime.tryParse(json['downloadedAt'] as String? ?? '')?.toUtc(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String id;
  final Song song;
  final String? deviceId;
  final String status;
  final int? bitrateKbps;
  final int? sizeBytes;
  final String? downloadUrl;
  final DateTime? licenceExpiresAt;
  final DateTime? downloadedAt;
  final DateTime? createdAt;

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isPending => status.toUpperCase() == 'PENDING';
}

final FutureProvider<PagedResponse<DownloadRecord>> downloadsProvider =
    FutureProvider<PagedResponse<DownloadRecord>>(
  (Ref ref) => ref.watch(apiClientProvider).getPaged<DownloadRecord>(
        ApiEndpoints.downloads,
        size: 50,
        itemMapper: DownloadRecord.fromJson,
      ),
  name: 'downloads',
);

/// Download lifecycle actions.
class DownloadActions {
  const DownloadActions(this._ref);

  final Ref _ref;

  /// Reserves a download and returns the signed URL the client should fetch.
  Future<DownloadRecord> start(Song song, {String? deviceId, int? bitrateKbps}) async {
    final Map<String, dynamic> data = await _ref.read(apiClientProvider).post(
      ApiEndpoints.downloads,
      body: <String, dynamic>{
        'songId': song.id,
        if (deviceId != null) 'deviceId': deviceId,
        if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
      },
    );
    final DownloadRecord record = DownloadRecord.fromJson(data);
    _ref.invalidate(downloadsProvider);
    return record;
  }

  /// Marks a reserved download as finished.
  Future<DownloadRecord> complete(String downloadId) async {
    final Map<String, dynamic> data =
        await _ref.read(apiClientProvider).post(ApiEndpoints.downloadComplete(downloadId));
    _ref.invalidate(downloadsProvider);
    return DownloadRecord.fromJson(data);
  }

  Future<void> remove(String downloadId) async {
    await _ref.read(apiClientProvider).delete(ApiEndpoints.download(downloadId));
    _ref.invalidate(downloadsProvider);
  }
}

final Provider<DownloadActions> downloadActionsProvider = Provider<DownloadActions>(
  (Ref ref) => DownloadActions(ref),
  name: 'downloadActions',
);
