import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marketplace/di/locator.dart';
import 'package:marketplace/domain/entities/message/chat_item.dart';
import 'package:marketplace/domain/entities/user/user.dart';
import 'package:marketplace/pages/chat/bloc/chat_bloc/chat_bloc.dart';
import 'package:marketplace/pages/chat/bloc/message_panel_bloc/message_panel_bloc.dart';
import 'package:marketplace/pages/chat/widgets/chat_app_bar.dart';
import 'package:marketplace/pages/chat/widgets/chat_body.dart';
import 'package:side_effect_bloc/side_effect_bloc.dart';
import 'bloc/chat_user_bloc/chat_user_bloc.dart';

final chatMessagesProvider = StateProvider<List<ChatItem>>((e) => []);

class ChatPage extends StatelessWidget {
  final UserId peerUserId;

  const ChatPage({
    Key? key,
    required this.peerUserId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [chatMessagesProvider.overrideWith((ref) => [])],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) =>
                getIt<ChatUserBloc>()..add(ChatUserEvent.started(peerUserId)),
          ),
          BlocProvider(
            create: (context) =>
                getIt<ChatBloc>()..add(ChatEvent.started(peerUserId)),
          ),
          BlocProvider(
            create: (context) => getIt<MessagePanelBloc>()
              ..add(MessagePanelEvent.pageOpened(peerUserId)),
          ),
          BlocProvider(
            create: (context) => getIt<MessagePanelBloc>()
              ..add(MessagePanelEvent.pageOpened(peerUserId)),
          ),
        ],
        child: Scaffold(
          appBar: const ChatAppBar(),
          // хак для соединения блока и riverpod'а
          // todo: переехать полностью на riverpod
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              final a = ref.read(chatMessagesProvider.notifier);
              return BlocSideEffectListener<ChatBloc, ChatCommand>(
                listener: (BuildContext context, sideEffect) {
                  sideEffect.whenOrNull(
                    updateList: (List<ChatItem> items) {
                      a.state = items;
                    },
                  );
                },
                child: const ChatBody(),
              );
            },
          ),
        ),
      ),
    );
  }
}