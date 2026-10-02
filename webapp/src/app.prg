/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-05-24
  Version....: 1.0.0
  Description: Fenix web app — session-based auth example.
               /main is protected: redirects to /login if not
               authenticated. Login redirects back to /main.
  Usage      : go.bat -> compiles and starts server on port 80
               Credentials: admin/admin123  carles/1234
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION Main()

   LOCAL oServer := THixServer():New()

      // In HIXSTYLE mode, the root folder is protected.
      // Our application test is located within the /test folder,
      // and we need to enable it to be run directly from our
      // browser: http://localhost/test/index.html
      
         oServer:AllowDir( "test", .F. )
         oServer:AllowDir( "customer", .T. )
         
      // ---------------------------------------------------------

      // Middleware setup (required by MyAppAuthRoleEdit / MyAppLogin)
         // Redirect on CSRF failure -> /login (was NIL = blank 403)
         // TTL = 3600s (1 hour) for token validity
         HIX_MwCsrfSetup( "/login",   ;
                          NIL, NIL, "e7f3a9c2b1d8f4a6c5e9d2b1f8a4c7e3d6b9f2a5c8e1d4b7", 3600 )
         HIX_MwRateLimitSetup( UConfig( "setup", "ratelimit", "ip_per_min" ), ;
                               UConfig( "setup", "ratelimit", "window_s" ) )

   oServer:Start()

RETURN NIL 