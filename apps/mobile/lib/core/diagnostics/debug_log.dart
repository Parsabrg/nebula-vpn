import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// On in test builds (`--dart-define=NEBULA_DEBUG_LOGS=true`): the app writes
/// what it does to the system log (Android: `adb logcat -s flutter`) and the
/// core logs at its most verbose level. Off in releases. Bodies and headers
/// are never written either way: they carry credentials and tokens.
const bool kDebugLogs = bool.fromEnvironment('NEBULA_DEBUG_LOGS');

void debugLog(String message) {
  if (kDebugLogs) debugPrint('nebula: $message');
}

/// A path segment that may be a secret (a subscription token): long and not
/// a UUID, which ids are.
final RegExp _secretSegment = RegExp(r'^[A-Za-z0-9_.~-]{24,}$');
final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

String loggedPath(Uri uri) => uri.pathSegments
    .map(
      (String s) => _secretSegment.hasMatch(s) && !_uuid.hasMatch(s) ? '…' : s,
    )
    .join('/');

/// Each API call: method, host, path (no query), status, time, and the
/// API's error detail.
class DebugLogInterceptor extends Interceptor {
  static const String _started = 'nebula.debugLog.started';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_started] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    debugLog('api ${_line(response.requestOptions)} -> ${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final Object? data = err.response?.data;
    final Object? detail = data is Map ? data['detail'] : null;
    debugLog(
      'api ${_line(err.requestOptions)} -> '
      '${err.response?.statusCode ?? err.type.name}'
      '${detail is String ? ' "$detail"' : ''}',
    );
    handler.next(err);
  }

  static String _line(RequestOptions options) {
    final Object? started = options.extra[_started];
    final String took = started is int
        ? ' ${DateTime.now().millisecondsSinceEpoch - started} ms'
        : '';
    return '${options.method} ${options.uri.host}/${loggedPath(options.uri)}$took';
  }
}
