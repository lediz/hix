/*-----------------------------------------------------------
  File ......: auth.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-10-05
  Version....: 1.2.0
  Description: Login controller — validates credentials and
               starts a session. No middleware on the route;
               session is managed explicitly via USession().

               On success the SID is rotated (USessionRotate) before the
               identity is stored: GET /login issues an anonymous session so
               its CSRF token can be bound to a session id, and that
               pre-login SID must never survive into the authenticated
               session (A1.19, no session fixation).
  Usage      : POST /login  (form fields: username, password)
 -----------------------------------------------------------*/

#include "hbclass.ch"
/*
   Cuando actualicemos via POST (normalmente), nunca devolveremos un html -> Prohibit !!
   Siempre usaremos un redirect tanto si OK/KO. Porque ? Evitaremos el tipico error 
   del F5 que re-ejecuta el post. 
   Esto es el patron PRG !!! :-) => Post/Request/Get -> Esto hace que aunge volvamos 
   hacer un F5 hará un GET !
   
   IMPORTANTE: En un redirect podemos pasar en la url, pero nuestro sistema usará mensajes 
   flash que son mensajes que una vez hecho el redirect podremos recuperar y usarlos 1 vez.
   Es un método muy bueno a nivel web y sesiones para gestionar mensajes, arrastrar 
   errores,... En API no es necesario porque jugaremos con JSON   
*/

function Main()

   LOCAL oVal
   LOCAL oSess, hUser

   // Validate input

      oVal := UValidatePost( { ;
         "username" => { "required|min:3|max:30", "Username", "" }, ;
         "password" => { "required|min:4",        "Password", "" }  ;
      } )

      IF ! oVal:Make()
         UFlash( "login" ):Set( { "error" => oVal:GetFirstError(), "user" => oVal:Get( "username" ) } )
         URedirect( URoute( 'sys.login' ) )
         RETURN
      ENDIF

   // Validte user in data model 

      hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )
  
   // Response.... 

      IF ValType( hUser ) == "H"
      
         // Rotate first: the anonymous SID that GET /login handed out (and that
         // the CSRF token is bound to) is deleted, the authenticated identity
         // is written under a brand new one.
         USessionRotate()
      
         // UMwConfig( "auth", "session_user_key" ) 
         // Recovery config of auth middleware. See : /middlewares/config.json
       
            oSess := USession()
            oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
            oSess:Save()
            
         // -------------------------------------------         
         
         URedirect( UMwConfig( "auth", "redirect_accept" ) )
         
      ELSE
         UFlash( "login" ):Set( { "error" => "Invalid username or password. Please try again.", "user" => oVal:Get( "username" ) } )

         URedirect( UMwConfig( "auth", "redirect_login" ) )    // -> /login 
         
      ENDIF

RETURN

#include 'models/modeluser.prg'
