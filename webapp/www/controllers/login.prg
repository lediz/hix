/*-----------------------------------------------------------
  File ......: login.prg
  Author.....: Charly 9000
  Created....: 2026-05-26
  Modified...: 2026-10-05
  Version....: 1.1.0
  Description: GET /login controller — loads session, reads flash
               error and username set by auth.prg on failed login.

               The route now runs MyAppLoginView (SecHeaders + Session) and
               this controller persists that session: the anonymous SID is
               what the @CSRF token in sys/login.html is bound to, so
               POST /auth only accepts a token that was served to this very
               session (PENTEST-REPORT.md §5).  auth.prg rotates the SID on
               success, so the pre-login SID never becomes an authenticated
               one (no session fixation).
  Usage      : GET /login
 -----------------------------------------------------------*/

FUNCTION Main()
   LOCAL oFlash
   LOCAL cError
   LOCAL cUser

   oFlash := UFlash( "login" )
   cError := oFlash:Get( "error" )
   cUser  := oFlash:Get( "user"  )
   oFlash:Save()

   IF Empty( cError )
      oFlash := UFlash( "csrf" )
      cError := oFlash:Get( "error" )
      oFlash:Save()
   ENDIF

   // Persist the anonymous session so its SID survives to POST /auth.
   USession():Save()

return UView( "sys/login.html", cUser, cError )



