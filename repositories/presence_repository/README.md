# Presence repository  

## Components 
Call bloc contains 

+ ChatClient - agora`s entry point of the Chat SDK. 


## Desription  
The repository is responsible for providing streams of users presence streams. When we try to get a stream, repository checks if it is placed in status map. If there is no stream, then a new stream from the agora sdk is requested and the current status of the user is requested.

## Presentation 
+ Change of status

