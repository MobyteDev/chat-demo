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
