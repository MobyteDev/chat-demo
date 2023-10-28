import 'dart:collection';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:marketplace/domain/entities/message/chat_item.dart';
import 'package:marketplace/domain/entities/message/custom/media/media_update.dart';
import 'package:marketplace/domain/entities/message/message.dart';
import 'package:marketplace/domain/entities/message/message_direction_entity.dart';
import 'package:marketplace/domain/entities/message/message_status_entity.dart';
import 'package:marketplace/domain/entities/message/message_status_update.dart';
import 'package:marketplace/domain/entities/user/user.dart';
import 'package:marketplace/domain/repository/conversation/conversation_repository.dart';
import 'package:marketplace/domain/repository/message/message_repository.dart';
import 'package:marketplace/domain/repository/user/user_repository.dart';
import 'package:marketplace/pages/chat/bloc/chat_bloc/message_bloc_manager.dart';
import 'package:marketplace/utils/date_time_ext.dart';
import 'package:side_effect_bloc/side_effect_bloc.dart';

part 'chat_bloc.freezed.dart';

part 'chat_command.dart';

part 'chat_event.dart';

part 'chat_state.dart';

@injectable
class ChatBloc extends Bloc<ChatEvent, ChatState>
    with SideEffectBlocMixin<ChatState, ChatCommand> {
  /// amount of fetched messages
  static const _pageSize = 20;

  final MessageRepository _messageRepository;
  final UserRepository _userRepository;
  final MessageBlocManager _messageBlocManager;
  final ConversationRepository _conversationRepository;

  late UserId peerUserId;
  late User currentUser;
  late User peerUser;
  late bool? isCurrentUserExpert;

  final List<ChatItem> _chatItems = [];
  final Set<String> messageLocalIds = {};
  final Set<String> messageGlobalIds = {};
  final HashMap<String, int> _chatListMessageIndexes = HashMap();
  /// unread messages count
  int result = 0;
  bool _isChatActive = true;
  final List<Message> _unreadMessages = [];

  ChatBloc(
    this._messageRepository,
    this._userRepository,
    this._messageBlocManager,
    this._conversationRepository,
  ) : super(ChatState()) {
    on<Started>(_onStarted);
    on<LoadMore>(_onLoadMore);
    on<ReplyMessage>(_onReplyMessage);
    on<ResendMessage>(_onResendMessage);
    on<ReplyPressed>(_onReplyPressed);
    on<FileError>(_fileErrors);
    on<PauseChat>(_onPauseChat);
    on<ResumeChat>(_onResumeChat);
    on<DeleteMessage>(_onDeleteMessage);
  }

  Future<void> _onStarted(Started event, Emitter<ChatState> emit) async {
    peerUserId = event.peerUserId;
    peerUser = await _getUser(peerUserId);
    currentUser = _userRepository.currentUser.valueOrNull!;
    ///if communicating with a tech support account to restrict the creation of sessions and tech support accounts
    if (event.peerUserId == User.support().userId) {
      currentUser = currentUser.copyWith(role: UserRole.client);
    }
    isCurrentUserExpert = currentUser.isExpert;
    result = (await _conversationRepository.fetchConversation(peerUserId))
        .unreadCount;
    await _conversationRepository.readConversation(peerUserId);
    _conversationRepository.allCount
        .add(await _conversationRepository.getCountOfUnreadMessages());
    add(const LoadMore());
    await Future.wait([
      emit.forEach<MessageItem>(
        _messageRepository.getConversationNewMessages(peerUserId).asyncMap(
          (message) async {
            final author = await _getUser(message.metadata.authorId);
            return _mapMessageToItem(message, true, author);
          },
        ),
        onData: (messageItem) {
          _addNewMessage(messageItem);
          produceSideEffect(UpdateList(items: [..._chatItems]));
          return state;
        },
      ),
      emit.forEach<MessageStatusUpdate>(
        _messageRepository.messageStatusUpdates.stream,
        onData: (status) {
          _updateMessage(status);

          produceSideEffect(UpdateList(items: [..._chatItems]));
          return state;
        },
      ),
      emit.forEach<MediaUpdate>(
        _messageRepository.videoMessageUpdates.stream,
        onData: (mediaUpdate) {
          return _updateVideoMessage(mediaUpdate);
        },
      ),
    ]);
  }

  void placeDividerForNewMessages(int unreadCount) {
    ChatItem divider = const ChatItem.newMessagesDivider();
    int indexOfExistingDivider = 0;
    if (_chatItems.contains(divider)) {
      indexOfExistingDivider = _chatItems.indexOf(divider);
      _chatItems.remove(divider);
      _chatListMessageIndexes.updateAll((key, value) {
        if (value >= indexOfExistingDivider) {
          return value = value - 1;
        } else {
          return value;
        }
      });
    }
    if (unreadCount != 0 && unreadCount <= _chatItems.length) {
      _chatListMessageIndexes.updateAll(
        (key, value) {
          if (value >= unreadCount) {
            return value = value + 1;
          } else {
            return value;
          }
        },
      );
      _chatItems.insert(
        unreadCount,
        divider,
      );
      produceSideEffect(UpdateList(items: [..._chatItems]));
    }
  }

  ChatState _updateVideoMessage(MediaUpdate mediaUpdate) {
    Message message = mediaUpdate.message;

    String? localId = message.metadata.localId ?? message.metadata.globalId;
    int _chatItemIndex =
        _videoPreviewChatIndexChange(mediaUpdate, message, localId);
    if (message.metadata.conversationId == peerUserId) {
      if (_chatItems[_chatItemIndex] is MessageItem) {
        final MessageItem currentMessage =
            _chatItems[_chatItemIndex] as MessageItem;
        _chatItems[_chatItemIndex] = currentMessage.copyWith(message: message);
      }
      produceSideEffect(ChatCommand.updateList(items: _chatItems));
      return state;
    } else {
      return state;
    }
  }

  int _videoPreviewChatIndexChange(
    MediaUpdate mediaUpdate,
    Message message,
    String? id,
  ) {
    int _chatItemIndex;
    if (_chatListMessageIndexes.containsKey(message.metadata.localId)) {
      _chatItemIndex = _chatListMessageIndexes[message.metadata.localId]!;
      if (mediaUpdate.localId != null) {
        id = mediaUpdate.localId;
        if (!messageLocalIds.remove(message.metadata.localId)) {
          messageGlobalIds.remove(message.metadata.localId);
        }
        _chatListMessageIndexes.putIfAbsent(
          id!,
          () => _chatItemIndex,
        );
        _chatListMessageIndexes.remove(message.metadata.localId);
        messageLocalIds.add(id);
        _chatItems[_chatItemIndex] =
            (_chatItems[_chatItemIndex] as MessageItem).copyWith(
          message: message.copyWith(
            metadata: message.metadata.copyWith(localId: id),
          ),
        );
      }
    } else if (_chatListMessageIndexes.containsKey(message.metadata.globalId)) {
      _chatItemIndex = _chatListMessageIndexes[message.metadata.globalId]!;
    } else {
      _chatItemIndex = 0;
      if (mediaUpdate.localId != null) {
        id = mediaUpdate.localId;
        messageLocalIds.remove(message.metadata.localId)
            ? _chatListMessageIndexes.putIfAbsent(
                id!,
                () => _chatItemIndex,
              )
            : {};
        _chatListMessageIndexes.remove(message.metadata.localId);
        messageLocalIds.add(id!);
        _chatItems[_chatItemIndex] =
            (_chatItems[_chatItemIndex] as MessageItem).copyWith(
          message: message.copyWith(
            metadata: message.metadata.copyWith(localId: id),
          ),
        );
      }
    }
    return _chatItemIndex;
  }

  void _onReplyMessage(ReplyMessage event, Emitter<ChatState> emit) {
    if (!_ensureSent(event.chatItem)) {
      return;
    }
    produceSideEffect(const ChatCommand.successReplyMessage());
  }

  int? keyIndexCallback(Key key) {
    if (key is ValueKey) {
      final newIndex = _chatListMessageIndexes[key.value];
      if (newIndex != null) {
        return newIndex;
      }
    }
    return null;
  }

  Key keyForItem(ChatItem item) {
    return item.map(
      message: (messageItem) => ValueKey(
        messageItem.message.metadata.globalId ??
            messageItem.message.metadata.localId,
      ),
      dateDivider: (dateItem) => ValueKey(
        dateItem.date.hashCode,
      ),
      newMessagesDivider: (value) => ValueKey(DateTime.now().millisecond),
    );
  }

  /// Loads new page of messages
  ///
  /// Fetched list is reversed because first item is the oldest one
  /// and [ListView] set to displays in reversed order
  Future<void> _onLoadMore(
    LoadMore event,
    Emitter<ChatState> emit,
  ) async {
    final lastMessage =
        _chatItems.lastWhereOrNull((e) => e is MessageItem) as MessageItem?;
    final beforeId = lastMessage?.message.metadata.globalId ??
        lastMessage?.message.metadata.localId;
    final res = await _messageRepository.fetchConversationMessages(
      peerUserId,
      _pageSize,
      beforeId,
    );

    final messages = res.reversed.toList();
    final isLastPage = res.length < _pageSize;
    for (Message mes in res) {
      if (messages.isNotEmpty &&
          mes.metadata.direction == MessageDirectionEntity.received) {
        await _messageRepository.readMessages(
          mes.metadata.authorId,
          mes.metadata.globalId!,
        );
      }
    }

    await _addHistoricalPage(messages, isLastPage);
    produceSideEffect(UpdateList(items: [..._chatItems]));
  }

  Future<void> _onResendMessage(
    ResendMessage event,
    Emitter<ChatState> emit,
  ) async {
    _messageRepository.resendMessage(event.messageLocalId);

    int messageIndex = _chatListMessageIndexes[event.messageLocalId]!;
    _chatListMessageIndexes.remove(event.messageLocalId);
    _chatListMessageIndexes.updateAll((key, value) {
      if (value > messageIndex) {
        value = value - 1;
      }
      return value;
    });

    _chatItems.removeAt(messageIndex);
  }

  Future<void> _onDeleteMessage(
    DeleteMessage event,
    Emitter<ChatState> emit,
  ) async {
    String? attentionLocalId =
        _tryToFindConnectedAttentionId(event.messageLocalId);
    if (attentionLocalId != null) {
      _deleteMessage(
        messageLocalId: attentionLocalId,
        isGlobal: false,
      );
    }
    await _deleteMessage(
      messageLocalId: event.messageLocalId,
      isGlobal: event.isGlobal,
    );
    produceSideEffect(ChatCommand.updateList(items: _chatItems));
  }

  Future<void> _deleteMessage({
    required String messageLocalId,
    required bool isGlobal,
  }) async {
    if (isGlobal) {
      _messageRepository.deleteMessage(messageLocalId);
    }
    int messageIndex = _chatListMessageIndexes[messageLocalId]!;
    _chatListMessageIndexes.remove(messageLocalId);
    _chatListMessageIndexes.updateAll((key, value) {
      if (value > messageIndex) {
        value = value - 1;
      }
      return value;
    });

    _chatItems.removeAt(messageIndex);
  }

  String? _tryToFindConnectedAttentionId(String connectedId) {
    final ChatItem? _attentionMessage = _chatItems.firstWhereOrNull(
      (element) => element.map(
        message: (message) => message.message.map(
          text: (_) => false,
          image: (_) => false,
          video: (_) => false,
          mediaPreview: (_) => false,
          file: (_) => false,
          bill: (_) => false,
          review: (_) => false,
          appointment: (_) => false,
          session: (_) => false,
          voice: (_) => false,
          attention: (attention) => attention.blockedId == connectedId,
        ),
        dateDivider: (_) => false,
        newMessagesDivider: (_) => false,
      ),
    );
    String? attentionLocalId = _attentionMessage?.map(
      message: (message1) => message1.message.metadata.localId,
      dateDivider: (_) => null,
      newMessagesDivider: (_) => null,
    );
    return attentionLocalId;
  }

  Future<void> _addNewMessage(MessageItem messageItem) async {
    placeDividerForNewMessages(0); //removes divider

    final message = messageItem.message;
    bool a = message.metadata.localId != null
        ? messageLocalIds.add(message.metadata.localId!)
        : messageGlobalIds.add(message.metadata.globalId!);

    if (a) {
      if (_chatItems.isNotEmpty) {
        final lastExistedMessage = _chatItems[0];
        if (lastExistedMessage is MessageItem &&
            !lastExistedMessage.message.metadata.timestamp
                .isDateEqual(message.metadata.timestamp)) {
          _chatListMessageIndexes.updateAll(
            (key, value) => value = value + 1,
          );
          _chatItems.insert(
            0,
            ChatItem.dateDivider(date: message.metadata.timestamp),
          );
        }

        if (lastExistedMessage is MessageItem &&
            lastExistedMessage.message.metadata.authorId ==
                message.metadata.authorId &&
            lastExistedMessage.message.metadata.direction ==
                MessageDirectionEntity.received &&
            message.metadata.direction == MessageDirectionEntity.received) {
          _chatItems.removeAt(0);
          _chatItems.insert(0, lastExistedMessage.copyWith(showAvatar: false));
        }
      } else {
        _chatListMessageIndexes.updateAll(
          (key, value) => value = value + 1,
        );
        _chatItems.insert(
          0,
          ChatItem.dateDivider(date: message.metadata.timestamp),
        );
      }
      _chatListMessageIndexes.updateAll(
        (key, value) => value = value + 1,
      );
      if (messageItem.message.metadata.authorId != '') {
        _chatItems.insert(0, messageItem);
      }

      if (message.metadata.direction == MessageDirectionEntity.received) {
        if (_isChatActive) {
          await _conversationRepository.readConversation(peerUserId);
          _conversationRepository.allCount
              .add(await _conversationRepository.getCountOfUnreadMessages());
          if (message.metadata.globalId != null) {
            _messageRepository.readMessages(
              message.metadata.authorId,
              message.metadata.globalId!,
            );
          }
        } else {
          _unreadMessages.add(message);
        }
      }
    }

    message.metadata.localId != null
        ? _chatListMessageIndexes[message.metadata.localId!] = 0
        : _chatListMessageIndexes[message.metadata.globalId!] = 0;
  }

  Future<void> _onReplyPressed(
    ReplyPressed event,
    Emitter<ChatState> emit,
  ) async {
    produceSideEffect(
      ChatCommand.navToChatReplyPage(
        peerUserAvatarUrl: peerUser.avatar.src,
        peerUserId: peerUserId,
        peerUserName: peerUser.name,
        message: event.message,
      ),
    );
  }

  /// [messages] newest -> oldest
  Future<void> _addHistoricalPage(
    List<Message> messages, [
    bool isLastPage = false,
  ]) async {
    if (messages.isNotEmpty) {
      DateTime newestDate = messages[0].metadata.timestamp;
      if (_chatItems.isNotEmpty) {
        final oldestExistedItem = _chatItems.last;
        if (oldestExistedItem is MessageItem) {
          if (!oldestExistedItem.message.metadata.timestamp
              .isDateEqual(newestDate)) {
            _chatItems.add(
              ChatItem.dateDivider(
                date: oldestExistedItem.message.metadata.timestamp,
              ),
            );
          }
        } else if (oldestExistedItem is DateDividerItem) {
          if (oldestExistedItem.date.isDateEqual(newestDate)) {
            _chatItems.remove(oldestExistedItem);
          }
        }
      }

      for (int i = 0; i < messages.length; i++) {
        final messageDate = messages[i].metadata.timestamp;
        if (!messageDate.isDateEqual(newestDate)) {
          _chatItems.add(ChatItem.dateDivider(date: newestDate));
          newestDate = messageDate;
        }
        if (messages[i].metadata.globalId != null) {
          if (messageGlobalIds.add(messages[i].metadata.globalId!)) {
            bool showAvatar = true;
            if (_chatItems.isNotEmpty) {
              if (_chatItems.last is MessageItem) {
                Message lastMessage = (_chatItems.last as MessageItem).message;
                if (messages[i].metadata.authorId ==
                        lastMessage.metadata.authorId &&
                    lastMessage.metadata.direction ==
                        MessageDirectionEntity.received) {
                  showAvatar = false;
                }
              }
            }
            final user = await _getUser(messages[i].metadata.authorId);
            _chatItems.add(
              _mapMessageToItem(
                messages[i],
                showAvatar,
                user,
              ),
            );
            _chatListMessageIndexes[messages[i].metadata.globalId!] =
                _chatItems.length - 1;
          }
        } else {
          if (messageLocalIds.add(messages[i].metadata.localId!)) {
            final user = await _getUser(messages[i].metadata.authorId);
            _chatItems.add(
              _mapMessageToItem(
                messages[i],
                false,
                user,
              ),
            );
            _chatListMessageIndexes[messages[i].metadata.localId!] =
                _chatItems.length - 1;
          }
        }
      }
    }
    if (isLastPage && _chatItems.isNotEmpty) {
      final lastItem = _chatItems.last;
      if (lastItem is MessageItem) {
        _chatItems.add(
          ChatItem.dateDivider(date: lastItem.message.metadata.timestamp),
        );
      }
    }
    placeDividerForNewMessages(result);
  }

  void _updateMessage(MessageStatusUpdate newStatus) {
    int _chatItemIndex;
    if (_chatListMessageIndexes.containsKey(newStatus.messageLocalId)) {
      _chatItemIndex = _chatListMessageIndexes[newStatus.messageLocalId]!;
    } else if (_chatListMessageIndexes.containsKey(newStatus.messageGlobalId)) {
      _chatItemIndex = _chatListMessageIndexes[newStatus.messageGlobalId]!;
    } else {
      return;
    }
    if (newStatus.status == MessageStatusEntity.sent) {
      _chatItemIndex = _chatListMessageIndexes[newStatus.messageLocalId]!;
      _chatListMessageIndexes[newStatus.messageGlobalId!] = _chatItemIndex;
    }
    double? progressIndicator;

    if (newStatus.status == MessageStatusEntity.sent) {
      progressIndicator = 100;
    } else if (newStatus.status == MessageStatusEntity.inProgress) {
      progressIndicator = newStatus.progress / 100;
    } else if (newStatus.status == MessageStatusEntity.notDelivered) {
      progressIndicator = -1;
    } else {}

    if (_chatItems[_chatItemIndex] is MessageItem) {
      final MessageItem message = _chatItems[_chatItemIndex] as MessageItem;
      _chatItems[_chatItemIndex] = message.copyWith(
        progress: progressIndicator ?? message.progress,
        message: message.message.copyWith(
          metadata: message.message.metadata.copyWith(
            status: newStatus.status,
            globalId:
                newStatus.messageGlobalId ?? message.message.metadata.globalId,
            localId:
                newStatus.messageLocalId ?? message.message.metadata.localId,
          ),
        ),
      );
    }
  }

  bool _ensureSent(
    ChatItem chatItem,
  ) {
    if (chatItem is MessageItem) {
      bool hasGlobalId = chatItem.message.metadata.globalId != null;
      if (!hasGlobalId) {
        produceSideEffect(const ChatCommand.showMessageUnsentWarning());
      }
      return hasGlobalId;
    } else {
      return false;
    }
  }

  MessageItem _mapMessageToItem(
    Message message,
    bool showAvatar,
    User user,
  ) {
    double loading = 100;
    if (message.metadata.status ==
        MessageStatusEntity
            .notDelivered /* || message.metadata.status == MessageStatusEntity.inProgress*/) {
      loading = -1;
    } else {
      loading = 100;
    }
    return MessageItem(
      showAvatar: message.metadata.direction == MessageDirectionEntity.sent
          ? false
          : showAvatar,
      progress: loading,
      message: message,
      author: user,
    );
  }

  Future<User> _getUser(String userId) async {
    return _userRepository.getOneUserById(userId);
  }

  T getBlocForMessage<T extends Bloc>(
    Message message,
    String? actualPeerUserId,
  ) {
    return _messageBlocManager.getBlocForMessage<T>(
      message,
      actualPeerUserId ?? peerUserId,
    );
  }

  @override
  Future<void> close() {
    _messageBlocManager.close();
    return super.close();
  }

  void _fileErrors(FileError event, emit) {
    produceSideEffect(const ChatCommand.showFileIsBig());
  }

  void _onPauseChat(PauseChat event, emit) {
    _isChatActive = false;
    _chatItems.add(
      ChatItem.dateDivider(
        date: DateTime.now(),
      ),
    );
    _chatItems.add(
      _chatItems.first,
    );
    produceSideEffect(UpdateList(items: [..._chatItems]));
  }

  void _onResumeChat(ResumeChat event, emit) async {
    _isChatActive = true;
    for (Message unreadElement in _unreadMessages) {
      _messageRepository.readMessages(
        unreadElement.metadata.authorId,
        unreadElement.metadata.globalId!,
      );
    }
    placeDividerForNewMessages(_unreadMessages.length);

    _unreadMessages.clear();
    await _conversationRepository.readConversation(peerUserId);
    _conversationRepository.allCount
        .add(await _conversationRepository.getCountOfUnreadMessages());
  }
}
