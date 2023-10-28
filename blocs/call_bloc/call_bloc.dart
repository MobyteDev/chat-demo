import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:marketplace/domain/entities/call/call_action.dart';
import 'package:marketplace/domain/entities/message/booking/booking_entity.dart';
import 'package:marketplace/domain/entities/service/service_category.dart';
import 'package:marketplace/domain/entities/user/user.dart';
import 'package:marketplace/domain/entities/call/call_states.dart';
import 'package:marketplace/domain/entities/message/booking/booking_status.dart';
import 'package:marketplace/domain/entities/message/message.dart';
import 'package:marketplace/domain/repository/call/call_repository.dart';
import 'package:marketplace/domain/repository/message/booking_repository.dart';
import 'package:marketplace/domain/repository/message/message_repository.dart';
import 'package:marketplace/domain/repository/user/user_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:side_effect_bloc/side_effect_bloc.dart';
import 'package:marketplace/utils/date_time_ext.dart';

part 'call_bloc.freezed.dart';

part 'call_command.dart';

part 'call_event.dart';

part 'call_state.dart';

@injectable
class CallBloc extends Bloc<CallEvent, CallState>
    with SideEffectBlocMixin<CallState, CallCommand> {
  final CallRepository _callRepository;
  final UserRepository _userRepository;

  final MessageRepository _messageRepository;
  final BookingRepository _bookingRepository;
  final SessionMessage _sessionMessage;
  late Duration remainedDuration;
  CallBloc(
    this._callRepository,
    this._userRepository,
    this._messageRepository,
    this._bookingRepository,
    @factoryParam this._sessionMessage,
  ) : super(
          Call(
            isMicrophoneOff: false,
            isCameraOn: true,
            isFrontCamera: true,
            remoteUser: _userRepository.currentUser.value,
            remoteId: 0,
            // remoteId=0 in the documentation it means the ID of the local user
            channelName: "",
            serviceArea: ServiceAreaOld.tarology,
            callState: CallStates.waiting,
            isRemoteMicrophoneOff: false,
            isRemoteCameraOn: true,
            callDuration: Duration.zero,
            remainedDuration: Duration.zero,
          ),
        ) {
    on<Started>(_onStarted);
    on<VideoSwitched>(_onVideoSwitched);
    on<AudioSwitched>(_onAudioSwitched);
    on<CameraFlipped>(_onCameraFlipped);
    on<ReenterButtonPressed>(_onReenterButtonPressed);
    on<LeaveButtonPressed>(_onLeaveButtonPressed);
    on<Finished>(_onFinished);
  }

  late final BookingEntity session;
  late final UserId remoteUserId;
  late final User remoteUser;
  final endAfterReconnectingState = StreamController<CallAction>();

  _onStarted(
    Started event,
    Emitter<CallState> emit,
  ) async {
    remoteUserId = event.remoteUserId;
    remoteUser = await _getUser(remoteUserId);
    session = event.session;

    final bool isFrontCamera = await _callRepository.isCameraFront();
    final ntpTimeDiff = await DateTime.now().getDifferenceWithNtp();
    remainedDuration = session.finish.difference(
          DateTime.now().add(DateTime.now().timeZoneOffset),
        ) +
        ntpTimeDiff;

    emit(
      state.copyWith(
        remainedDuration:
            remainedDuration > Duration.zero ? remainedDuration : Duration.zero,
        serviceArea:
            ServiceAreaMapper.fromTitle(session.service.category.title),
        remoteUser: remoteUser,
        isFrontCamera: isFrontCamera,
      ),
    );

    await [Permission.microphone, Permission.camera].request();
    await joinCall(emit);
  }

  Future<void> joinCall(Emitter<CallState> emit) async {
    if (await checkEndOfSession(emit)) {
      return;
    }

    bool resultJoin = await _callRepository.joinConference(
      channelName: session.bookingId,
      isCameraOn: state.isCameraOn,
      isMicroOn: !state.isMicrophoneOff,
    );
    if (resultJoin) {
      await Future.wait(
        [
          emit.forEach(
            _callRepository.callActions(),
            onData: (CallAction action) {

              if (state.callState == CallStates.finished) {
                return state;
              }

              return action.map(
                onJoinChannelSuccess: (_) {
                  endAfterReconnectingState.add(action);
                  return state;
                },
                onUserJoined: (data) => state.copyWith(
                  remoteId: data.uid,
                  channelName: data.channelName,
                  callState: CallStates.active,
                ),
                onUserOffline: (data) {
                  endAfterReconnectingState.add(action);
                  return state.copyWith(
                    remoteId: 0,
                    callState: CallStates.waiting,
                  );
                },
                onUserMuteAudio: (data) => state.copyWith(
                  isRemoteMicrophoneOff: data.muted,
                ),
                onUserMuteVideo: (data) => state.copyWith(
                  isRemoteCameraOn: !data.muted,
                ),
                onConnectionLost: (_) => state.copyWith(
                  callState: CallStates.lostConnection,
                ),
                onReconnectingState: (_) {
                  if (state.remoteId != 0) {
                    return state.copyWith(callState: CallStates.connecting);
                  }
                  return state;
                },
                onReconnectedState: (_) {
                  endAfterReconnectingState.add(action);
                  if (state.remoteId == 0) {
                    return state.copyWith(callState: CallStates.waiting);
                  }
                  return state.copyWith(callState: CallStates.active);
                },
              );
            },
          ),
          emit.forEach(
            Stream.periodic(
              const Duration(seconds: 1),
            ),
            onData: (_) => state.copyWith(
              callDuration: session.finish.difference(session.start),
              remainedDuration: session.finish.difference(
                  DateTime.now().add(DateTime.now().timeZoneOffset)),
            ),
          ),
          emit.forEach(
            _messageRepository
                .getCustomMessageUpdates(_sessionMessage.metadata.globalId!)
                .asyncMap(
                  (_) => _bookingRepository.fetchSession(
                    sessionId: _sessionMessage.bookingId,
                  ),
                )
                .where((event) => event.status == BookingStatus.past)
                .asyncMap(
              (event) {
                _callRepository.leaveConference();
              },
            ),
            onData: (_) => state.copyWith(callState: CallStates.finished),
          ),
          emit.forEach(
            endAfterReconnectingState.stream
                .asyncMap(
                  (_) => _bookingRepository.fetchSession(
                    sessionId: _sessionMessage.bookingId,
                  ),
                )
                .where((event) => event.status == BookingStatus.past)
                .asyncMap(
              (event) {
                _callRepository.leaveConference();
              },
            ),
            onData: (_) => state.copyWith(callState: CallStates.finished),
          ),
        ],
      );
    } else {
      emit(state.copyWith(
        callState: CallStates.lostConnection,
      ));
    }
  }

  Future<bool> checkEndOfSession(Emitter<CallState> emit) async {
    try {
      final session = await _bookingRepository.fetchSession(
          sessionId: _sessionMessage.bookingId);
      if (session.status == BookingStatus.past) {
        await _callRepository.leaveConference();
        emit(
          state.copyWith(callState: CallStates.finished),
        );
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<User> _getUser(String userId) async {
    return _userRepository.getOneUserById(userId);
  }

  Future<void> _onFinished(
    Finished event,
    Emitter<CallState> emit,
  ) async {
    await _callRepository.leaveConference();
    emit(state.copyWith(callState: CallStates.finished));
  }

  Future<void> _onAudioSwitched(
    AudioSwitched event,
    Emitter<CallState> emit,
  ) async {
    final bool isMicrophoneOff = !state.isMicrophoneOff;
    emit(state.copyWith(isMicrophoneOff: isMicrophoneOff));
    isMicrophoneOff
        ? await _callRepository.audioTurnOff()
        : await _callRepository.audioTurnOn();
  }

  Future<void> _onVideoSwitched(
    VideoSwitched event,
    Emitter<CallState> emit,
  ) async {
    final bool isCameraOn = !state.isCameraOn;
    emit(state.copyWith(isCameraOn: isCameraOn));
    isCameraOn
        ? await _callRepository.videoTurnOn()
        : await _callRepository.videoTurnOff();
  }

  Future<void> _onCameraFlipped(
    CameraFlipped event,
    Emitter<CallState> emit,
  ) async {
    final bool isFrontCamera = !state.isFrontCamera;
    emit(state.copyWith(isFrontCamera: isFrontCamera));
    await _callRepository.cameraFlipped();
  }

  void _onLeaveButtonPressed(
    LeaveButtonPressed event,
    Emitter<CallState> emit,
  ) {
    produceSideEffect(const CallCommand.leaveConference());
  }

  void _onReenterButtonPressed(
    ReenterButtonPressed event,
    Emitter<CallState> emit,
  ) async {
    await _callRepository.leaveConference();
    await joinCall(emit);
  }
}
