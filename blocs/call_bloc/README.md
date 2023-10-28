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

+ example of session

+ ending session