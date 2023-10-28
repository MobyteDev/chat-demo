import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:marketplace/di/locator.dart';
import 'package:marketplace/domain/repository/auth/auth_repository.dart';
import 'package:marketplace/domain/snackbar_manager/snackbar_manager.dart';

import 'package:marketplace/data/model/errors/error_dto.dart';
import 'package:marketplace/navigation/auto_router.gr.dart';

@injectable
class AuthInterceptor extends Interceptor {
  final AuthRepository _authRepository;

  final SnackBarManager _snackBarManager;
  final Dio _dio;

  AuthInterceptor(
    this._authRepository,
    @Named('new_dio') this._dio,
    this._snackBarManager,
  );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _authRepository.getAccessToken();
    if (token != null) {
      options.headers["Authorization"] = "Bearer $token ";
    }
    super.onRequest(options, handler);
  }

  bool _isServerDown(DioError error) {
    return (error.error is SocketException) ||
        (error.type == DioErrorType.other);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    super.onResponse(response, handler);
  }

  final socketError = const ErrorDto(
    uri: "xxxxx:xxxxx/xxxxx",
    statusCode: 500,
    title: "Нет Сигнала",
    errors: ['Проверьте соединение с Интернетом'],
  );

  @override
  void onError(DioError err, ErrorInterceptorHandler handler) async {
    //current request
    if (_isServerDown(err)) {
      _snackBarManager.addNewError(error: socketError.toModel());
    }
    log(err.requestOptions.path);
    bool isReviewError = err.requestOptions.path.contains('/review') &&
        err.requestOptions.path.contains('bookings/');
    if (err.response != null &&
        err.response!.statusCode != 401 &&
        !isReviewError) {
      final networkError = ErrorDto.fromJson(
        err.response!.data,
        err.requestOptions.uri.toString(),
      );
      _snackBarManager.addNewError(error: networkError.toModel());
    }

    // check that the request error is related to the token
    if (err.response != null && err.response!.statusCode == 401) {
      // updating access Token with refresh Token
      try {
        await _authRepository.refreshToken();
      } on DioError catch (e) {
        await _authRepository.signOut(signOutOnServer: false);
        getIt<AppRouter>().pushAndPopUntil(
          const OnboardingRoute(),
          predicate: (_) => false,
        );
        return handler.next(
          RefreshTokenExpiredException(requestOptions: e.requestOptions),
        );
      }

      // repeat the original request
      final retry = await _dio.request(
        err.requestOptions.path,
        cancelToken: err.requestOptions.cancelToken,
        data: err.requestOptions.data,
        onReceiveProgress: err.requestOptions.onReceiveProgress,
        onSendProgress: err.requestOptions.onSendProgress,
        queryParameters: err.requestOptions.queryParameters,
        options: Options(
          method: err.requestOptions.method,
          headers: err.requestOptions.headers,
        ),
      );

      return handler.resolve(retry);
    }
    return super.onError(err, handler);
  }
}

class RefreshTokenExpiredException extends DioError {
  RefreshTokenExpiredException({required super.requestOptions});

  @override
  String toString() {
    return 'Refresh token expired, you have to log in again';
  }
}
