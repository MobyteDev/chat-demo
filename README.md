# chat-demo
## A repository containing examples for implementing chats
## Table of contents: 
all examples contains README.md
+ blocs
  + call_bloc
  + chat_bloc
  + confirm_phone_bloc
+ interceptors
  + auth_interceptor
+ repositories
  + booking_repository
  + presence_repository
+ screens
  + chat_page


## Packages and services in chat-demo 
+ for handling navigation uses autoRoute package
+ for adapting screen and font size uses sreenUtils 
+ for handling dependency injection uses get_it
+ for handling local storage  uses shared_preferences and flutter_secure_storage
+ for separating logic and state management   uses bloc and riverpod combined with freezed
+ for handling analytics  uses firebase 
+ agora is used as message service 
