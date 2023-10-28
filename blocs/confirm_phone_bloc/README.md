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
