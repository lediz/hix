/*-----------------------------------------------------------
  File ......: myappauthedit.prg
  Author.....: Charly 9000
  Created....: 2026-05-27
  Modified...: 2026-07-17
  Version....: 1.5.0
  Description: Middleware group for authenticated CRUD POST routes.
               MyAppAuthRoleEdit = SecHeaders + Session + IsAuth + HasRole + CsrfCheck.
               Uses HIX_MwCsrfCheck: the token is HMAC-signed AND (since the
               framework now puts the session id in the token payload) bound to
               the session that rendered the form - a token issued to one
               session is rejected in every other one (PENTEST-REPORT.md §5).
               HIX_MwSecHeaders first in the chain: X-Frame-Options,
               X-Content-Type-Options, Strict-Transport-Security and the CSP
               set from www/middlewares/config.json -> setup.secheaders.csp
               (PENTEST-REPORT.md §8).
               TTL is set globally via HIX_MwCsrfSetup( ..., 3600 ) in src/app.prg.
  Usage      : "middleware": "MyAppAuthRoleEdit", "scope": "customers:edit"
 -----------------------------------------------------------*/

FUNCTION MyAppAuthRoleEdit( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )
   
   o:Add( UMiddleware():New( "HIX_MwSecHeaders"  ) )
   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"    ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole"   ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
   
RETURN o:Run()
