import 'package:bloc/bloc.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';
import 'package:marketplace/domain/entities/errors/error.dart';
import 'package:marketplace/domain/entities/profile/profile.dart';
import 'package:marketplace/domain/repository/profile/profile_repository.dart';
import 'package:marketplace/domain/repository/user/user_repository.dart';
import 'package:marketplace/domain/snackbar_manager/snackbar_manager.dart';
import 'package:marketplace/domain/usecases/sign_in_usecase.dart';
import 'package:marketplace/domain/usecases/sign_up_usecase.dart';
import 'package:marketplace/utils/constants.dart';
import 'package:marketplace/utils/firebase_analytic.dart';
import 'package:side_effect_bloc/side_effect_bloc.dart';
import 'package:marketplace/di/locator.dart';
import 'package:url_launcher/url_launcher.dart';

part 'confirm_phone_bloc.freezed.dart';

part 'confirm_phone_command.dart';

part 'confirm_phone_event.dart';

part 'confirm_phone_state.dart';

@injectable
class ConfirmPhoneBloc extends Bloc<ConfirmPhoneEvent, ConfirmPhoneState>
    with SideEffectBlocMixin<ConfirmPhoneState, ConfirmPhoneCommand> {
  final SignInUseCase _signInUseCase;
  final SignUpUseCase _signUpUseCase;
  final FirebaseAnalytic _analytic;
  final ProfileRepository _profileRepository;
  static const _countDownPeriod = Duration(seconds: 1);
  Duration myDuration = const Duration(minutes: 1);
  bool firstAuthorization = false;
  final SnackBarManager _snackBarManager;

  ConfirmPhoneBloc(
    this._signInUseCase,
    this._signUpUseCase,
    this._profileRepository,
    this._snackBarManager,
    this._analytic,
  ) : super(const OpenPage()) {
    on<PageOpened>(_onPageOpened);
    on<CodeChanged>(_codeChanged);
    on<RestartTimer>(_restartTimer);
    on<OnResendCode>(_onResendCode);
    on<OnConfirmClicked>(_onConfirmClicked);
    on<OnHelpClicked>(_onHelpClicked);
  }

  Future<void> _requestCode(bool isSignIn, Emitter<ConfirmPhoneState> emit) async {
    try {
      if (!firstAuthorization) {
        isSignIn
            ? await _signInUseCase.signIn()
            : await _signUpUseCase.signUp();
        firstAuthorization = true;
      }
    } catch (e) {
      if (e is DioError &&
          e.response?.data["errors"][0] ==
              "Пользователь с таким номером телефона уже существует") {
        produceSideEffect(ConfirmPhoneCommand.navToPhoneEnter());
      }
      emit(state.copyWith(error: "Не получилось отправить код"));
    }
  }

  void _onPageOpened(PageOpened event, Emitter<ConfirmPhoneState> emit) async {
    await Future.wait([
      _requestCode(event.signIn, emit),
      emit.forEach(
        Stream.periodic(_countDownPeriod),
        onData: (data) {
          final seconds = myDuration.inSeconds - _countDownPeriod.inSeconds;
          if (myDuration.inSeconds == 0) {
            return state.copyWith(timer: "", isSignIn: event.signIn);
          } else {
            myDuration = Duration(seconds: seconds);
            return state.copyWith(
              timer:
                  "00:${myDuration.inSeconds < 10 ? "0" + myDuration.inSeconds.toString() : myDuration.inSeconds.toString()}",
              isSignIn: event.signIn,
            );
          }
        },
      ),
    ]);
  }

  void _codeChanged(CodeChanged event, Emitter<ConfirmPhoneState> emit) async {
    if (event.value.length == 6) {
      emit(state.copyWith(codeFilled: true, value: event.value, error: null));
    } else {
      emit(state.copyWith(codeFilled: false, value: event.value, error: null));
    }
  }

  Future<void> _onResendCode(
    OnResendCode event,
    Emitter<ConfirmPhoneState> emit,
  ) async {
    if (state.timer.isEmpty) {
      try {
        state.isSignIn
            ? await _signInUseCase.resendCode()
            : await _signUpUseCase.resendCode();
        emit(state.copyWith(value: '', codeFilled: false));
        produceSideEffect(ConfirmPhoneCommand.resentedCode());
      } catch (_) {
        emit(state.copyWith(error: "Не получилось отправить код"));
      }
    } else {
      _snackBarManager.addNewError(
        error: const Error(
          uri: "XXXXX:XXXXX/XXXXX",
          statusCode: 400,
          title: 'Невозможно запросить код',
          errors: ['Запросить код можно раз в минуту'],
        ),
      );
      produceSideEffect(ConfirmPhoneCommand.notYet());
    }
  }

  Future<void> _onConfirmClicked(
    OnConfirmClicked event,
    Emitter<ConfirmPhoneState> emit,
  ) async {
    if (event.profile != null && event.newPhone != null) {
      String phone = event.newPhone!
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll('(', '')
          .replaceAll(')', '');
      String birthday = event.profile!.birthday == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(event.profile!.birthday!);
      await _profileRepository.editPhone(
        event.profile!.id,
        event.profile!.name,
        birthday,
        event.profile!.gender ?? '',
        phone,
        event.profile!.avatar.id,
      );
      try {
        await _signInUseCase.verifyNewCode(int.parse(state.value), phone);
        produceSideEffect(ConfirmPhoneCommand.navToSettings());
      } catch (_) {
        emit(state.copyWith(error: "Не получилось отправить код"));
      }
    } else {
      try {
        state.isSignIn
            ? await _signInUseCase.verify(int.parse(state.value))
            : await _signUpUseCase.verify(int.parse(state.value));
        await getIt.popScope();
        state.isSignIn ? _analytic.logLogin() : _analytic.logSignUp();
        produceSideEffect(
          ConfirmPhoneCommand.navToNextPage(),
        );
      } catch (_) {
        emit(
          state.copyWith(
            error: "Неверный код",
          ),
        );
      }
    }
  }

  void _onHelpClicked(event, emit) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      query: encodeQueryParameters(<String, String>{
        'subject': 'Обращение в техподдержку Magmarket',
        'body': ''
      }),
    );

    if (await canLaunchUrl(emailUri)) {
      launchUrl(emailUri);
    } else {
      _snackBarManager.addNewError(
        error: const Error(
          statusCode: 400,
          title: 'Невозможно открыть почтовый клиент',
          errors: ['Проверьте, установлено ли на телефоне приложение почты'],
          uri: 'XXXXX:XXXXX/XXXXX',
        ),
      );
    }
  }

  String? encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  void _restartTimer(event, Emitter<ConfirmPhoneState> emit) async {
    myDuration = const Duration(minutes: 1);
    emit(state);
  }
}
