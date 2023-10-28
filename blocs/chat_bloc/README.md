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
