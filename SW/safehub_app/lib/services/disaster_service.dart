import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class DisasterService {
  static const int _rowsPerPage = 20;
  static const int _edgeValidationInterval = 8;

  int _lastKnownPage = 1;
  int _requestCycle = 0;

  Future<Map<String, dynamic>?> fetchLatest() async {
    final requestedPage = _lastKnownPage;
    final primaryResponse = await _request(
      pageNo: requestedPage,
    );

    final candidates = <dynamic>[
      ..._extractBody(primaryResponse),
    ];

    final totalCount = _parseNumber(
      primaryResponse['totalCount'],
    );

    final actualLastPage =
        totalCount <= 0 ? 1 : (totalCount / _rowsPerPage).ceil();

    _lastKnownPage = actualLastPage;
    _requestCycle += 1;

    // 데이터 증가로 새 마지막 페이지가 만들어졌다면 즉시 조회한다.
    if (actualLastPage != requestedPage) {
      final latestPageResponse = await _request(
        pageNo: actualLastPage,
      );

      candidates.addAll(
        _extractBody(latestPageResponse),
      );
    }

    // API 정렬 방향이 바뀌는 상황에 대비해 주기적으로
    // 반대쪽 첫 페이지도 검증한다.
    final shouldValidateFirstPage =
        _requestCycle % _edgeValidationInterval == 0 &&
            requestedPage != 1 &&
            actualLastPage != 1;

    if (shouldValidateFirstPage) {
      final firstPageResponse = await _request(
        pageNo: 1,
      );

      candidates.addAll(
        _extractBody(firstPageResponse),
      );
    }

    return selectLatest(candidates);
  }

  static List<dynamic> _extractBody(Map<String, dynamic> response) {
    final body = response['body'];

    if (body is! List) {
      return const [];
    }

    return body;
  }

  static String? identifierOf(Map<String, dynamic> disaster) {
    final value = disaster['SN'];

    if (value == null) {
      return null;
    }

    final identifier = value.toString().trim();
    return identifier.isEmpty ? null : identifier;
  }

  static bool isNewerThan(
    Map<String, dynamic> candidate,
    Map<String, dynamic> current,
  ) {
    return _compareDisasters(candidate, current) > 0;
  }

  static Map<String, dynamic>? selectLatest(List<dynamic> items) {
    Map<String, dynamic>? latest;

    for (final item in items) {
      if (item is! Map) {
        continue;
      }

      final candidate = Map<String, dynamic>.from(item);

      if (latest == null || _compareDisasters(candidate, latest) > 0) {
        latest = candidate;
      }
    }

    return latest;
  }

  static int _compareDisasters(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final dateComparison =
        _dateKey(left['CRT_DT']).compareTo(_dateKey(right['CRT_DT']));

    if (dateComparison != 0) {
      return dateComparison;
    }

    return _parseNumber(left['SN']).compareTo(_parseNumber(right['SN']));
  }

  static String _dateKey(dynamic value) {
    return value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  }

  static int _parseNumber(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString().trim() ?? '') ?? -1;
  }

  Future<Map<String, dynamic>> _request({
    required int pageNo,
  }) async {
    final uri = Uri.parse(
      AppConfig.disasterApiUrl,
    ).replace(
      queryParameters: {
        'serviceKey': AppConfig.disasterApiKey,
        'returnType': 'json',
        'pageNo': pageNo.toString(),
        'numOfRows': _rowsPerPage.toString(),
      },
    );

    final response = await http.get(uri).timeout(
          const Duration(seconds: 10),
        );

    if (response.statusCode != 200) {
      throw Exception(
        '재난 API HTTP 오류: ${response.statusCode}',
      );
    }

    final responseText = utf8.decode(response.bodyBytes);

    print('[재난 API] request page=$pageNo');
    print('[재난 API STATUS] ${response.statusCode}');

    final decoded = jsonDecode(responseText);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('재난 API 응답 형식 오류');
    }

    final header = decoded['header'];

    if (header is Map<String, dynamic>) {
      final resultCode = header['resultCode']?.toString();

      if (resultCode != '00') {
        throw Exception(
          '재난 API 오류: ${header['resultMsg']}',
        );
      }
    }

    return decoded;
  }
}
