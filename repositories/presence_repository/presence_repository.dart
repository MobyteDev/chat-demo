import 'dart:async';
import 'package:agora_chat_sdk/agora_chat_sdk.dart';
import 'package:injectable/injectable.dart';
import 'package:marketplace/domain/entities/presence/presence.dart';
import 'package:marketplace/domain/repository/presence/presence_repository.dart';
import 'package:rxdart/rxdart.dart';

@LazySingleton(as: PresenceRepository)
class PresenceRepositoryImpl extends PresenceRepository {
  final ChatClient _chatClient;
  bool _isFirstLaunch = true;
  final int _subscriptionExpiry = 15;
  final Map<String, BehaviorSubject<Presence>> _usersStatusMap =
      <String, BehaviorSubject<Presence>>{};

  PresenceRepositoryImpl(this._chatClient);

  @override
  Future<ValueStream<Presence>> getUserStatusRxStream(String id) async {
    final BehaviorSubject<Presence> subjectController =
        _usersStatusMap.putIfAbsent(
      id,
      () => BehaviorSubject<Presence>(),
    );
    if (_isFirstLaunch) {
      _handleFirstStart(id: id);
      _isFirstLaunch = false;
    } else {
      _chatClient.presenceManager.subscribe(
        members: [id],
        expiry: _subscriptionExpiry,
      );
    }
    return _getStreamWithStatus(subject: subjectController, id: id);
  }

  @override
  Future<void> removeUserFromPresenceRep(String id) async {
    _chatClient.presenceManager.unsubscribe(
      members: [id],
    );
    _usersStatusMap[id]!.close();
    _usersStatusMap.remove(id);
  }
/// adding a state to the rx controller so that it is not empty
  Future<ValueStream<Presence>> _getStreamWithStatus({
    required BehaviorSubject<Presence> subject,
    required String id,
  }) async {
    final stream = subject.stream;
    final ChatPresence chatPresence =
        (await _chatClient.presenceManager.fetchPresenceStatus(members: [id]))
            .first;
    subject.add(
      chatPresence.statusDescription == ""
          ? PresenceMapper.fromMap(chatPresence.statusDetails)
          : PresenceMapper.fromString(chatPresence.statusDescription),
    );
    return stream;
  }

/// Registering a ChatPresenceEventHandler in which states are passed to the rx
/// controller via the map and creating a timer that pre-signs users
/// from the map after the expiration of {_subscriptionExpiry}
  void _handleFirstStart({
    required String id,
  }) async {
    _chatClient.presenceManager.addEventHandler(
      "PRESENCE_EVENT_HANDLER",
      ChatPresenceEventHandler(
        onPresenceStatusChanged: (newStatuses) {
          for (var e in newStatuses) {
            _usersStatusMap[e.publisher]!.add(
              (e.statusDescription == "")
                  ? PresenceMapper.fromMap(e.statusDetails)
                  : PresenceMapper.fromString(e.statusDescription),
            );
          }
        },
      ),
    );
    _chatClient.presenceManager.subscribe(
      members: [id],
      expiry: _subscriptionExpiry,
    );
    Timer.periodic(
      Duration(seconds: _subscriptionExpiry),
      (timer) {
        _chatClient.presenceManager.subscribe(
          members: _usersStatusMap.keys.toList(),
          expiry: _subscriptionExpiry,
        );
      },
    );
  }
}
