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

# Call bloc description 
## Components 
Call bloc contains 

+ CallRepository - responsible for all actions related to the conference
+ MessageRepository - responsible for adding message of end to agora on this bloc 
+ UserRepository - responsible for receiving information about users
+ BookingRepository -  responsible for booking and rating of sessions


## Logic 
when started, it count down a timer and check local time difference with ntp server. This bloc connects buttons and agora`s rtcEngine with handles session. When session ends bloc navigates back to chat 


## Presentation 
+ enter in call

![enter_call](https://github.com/MobyteDev/chat-demo/assets/47796424/c5f0d28e-7e3a-4708-b888-80a341baab1c)

+ ending session
  
![end_call](https://github.com/MobyteDev/chat-demo/assets/47796424/5c66f285-eb85-4500-8889-c14ff1a8b83c)


# Chat bloc description 
## Components 
chat bloc contains 3 repositories 

+ MessageRepository - responsible for sending and receiving messages from the database
+ UserRepository - responsible for receiving user`s information
+ ConversationRepository - responsible for changing information about conversations 

and 1 manager: 

+ MessageBlocManager - manages creation and closing blocs for messages in chat monitors that bloc count not growing more than _maxBlocCount  for avoiding overspending of memory

## Logic of Started event 
on started bloc gets interlocutor`s information in User entity from UserRepository, fethes amount of unread messages(result) places divider for new messages and resets amount in ConversationRepository. After that, we subcribes to receive new messages, message statuses and media updates 

### Updating statuses in the bloc
 We subscribe to messageStatusUpdates from MessageRepository and listen to each new status from_updateStatus. We send this status to the _updateMessage method, where we take the index of our chat message from the map _chatListMessageIndexes via global or local id. 
Next, if our status is sent, then we take the index by the local id of the message and change the element in the map by the global id.
After that, we proceed to update the message in _chatItems, changing its current status to a new one. Checking is MessageItem
is needed just in case any failure occurs and the DateDividerItem gets into the method.
After all these actions, we update the list of messages via ChatCommand.updateList.

### Getting new messages in the bloc
When we receive new message, it is putted in a set, gets timestamp and moved to a list of messages. Then we emit new state with updated list.
### Getting media update in the bloc
When new media sends, we fetch a preview of media from MessageRepository. When media is loaded we receive a media message with id equal to preview id. Bloc deletes preview message and insert media message. 

## Logic of deactivated chat
when application is paused, we add divider of current date, deactivate reading of new messages and add it in a new list of unread messages. If user resumes app, we read new messages in a list, otherwise messages remain unread

## Presentation 
+ get messege
  
![get_message](https://github.com/MobyteDev/chat-demo/assets/47796424/8e2bae8e-35c3-4d8c-83e1-5c26537e525d)

+ update status

![get_status](https://github.com/MobyteDev/chat-demo/assets/47796424/e5097d40-e8b3-485d-8641-4db37f81c5fb)

# Confirm phone bloc description 
## Components 
Confirm phone bloc contains 

+ SignInUseCase & SignUpUseCase - responsible for sending codes and verifying codes 
+ FirebaseAnalytic - responsible for receiving sending events to firebaase 
+ ProfileRepository - responsible for receiving information about users
+ SnackBarManager -  responsible for showing snackbars 


## Logic 
when started, it tries to send code and if is fails, snackbar is showed. When user enters new code, this code is checked by useCases. When user request new code, we init a timer that prohibiting a new request.


## Presentation 
+ wrong code
  
![wrong_code](https://github.com/MobyteDev/chat-demo/assets/47796424/7a640c50-e96d-4ba6-bda5-f28e9b36fb26)

+ send again
  
![send_again](https://github.com/MobyteDev/chat-demo/assets/47796424/eaa78469-2df9-432d-9f09-874eeae1035f)

+ successful login

  ![suc_enter](https://github.com/MobyteDev/chat-demo/assets/47796424/de44d8fe-112f-4587-9b41-9f8166448ac7)

# Interceptor description
In Auth interceptor we check expiration of expiration of agora`s token in every request. If token is expired we log out and navigate to anboarding screen

# Booking repository desription

## Components 
Call bloc contains 

+ BookingDataSource - data source that sends bookings to server  
+ MessageRepository - repository that sends messages to agora 
+ FirebaseAnalytic - responsible for receiving sending events to firebaase 


## Information  
The repository is responsible for sending new booking to the server and sending a special type of messages to the agora server when the client writes to the session

## Presentation 
+ Booking example
  
  <img width="239" alt="image" src="https://github.com/MobyteDev/chat-demo/assets/47796424/05696b3a-31f7-491e-8c44-be9f142a7ff2">


# Presence repository desription

## Components 
Call bloc contains 

+ ChatClient - agora`s entry point of the Chat SDK. 


## Information  
The repository is responsible for providing streams of users presence streams. When we try to get a stream, repository checks if it is placed in status map. If there is no stream, then a new stream from the agora sdk is requested and the current status of the user is requested.

## Presentation 
+ Change of status

![change_status](https://github.com/MobyteDev/chat-demo/assets/47796424/9dc9c3de-2954-4b51-a747-a3391c88def2)

# Chat page description 

## Initialization   
After navigation we insert into element tree blocs and riverpod and insert BlocSideEffectListener(analog of BlocBuilder wich supports additional type of event called command)  and Consumer beforе page

## Connection of riverpod and bloc 
To connect riverpod and bloc we get entity from riverpod and update it, when command is called

## Presentation 
+ Chat page

<img width="245" alt="image" src="https://github.com/MobyteDev/chat-demo/assets/47796424/3b95af79-e050-4a22-9305-6990d104b6ce">

