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

+ send again

+ successful login