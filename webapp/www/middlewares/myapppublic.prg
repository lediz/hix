/*-----------------------------------------------------------
  File ......: myapppublic.prg
  Author.....: Charly 9000
  Created....: 2026-10-05
  Version....: 1.0.0
  Description: Public (unauthenticated) route group: security headers only.
               HIX_MwSecHeaders injects X-Frame-Options, X-Content-Type-Options,
               Strict-Transport-Security and the Content-Security-Policy set in
               www/middlewares/config.json -> setup.secheaders.csp.
               HIX's own groups (MW_WEB_ADMIN, MW_API_ADMIN, MW_API_JWT) include
               it; none of this app's groups did, so every response was bare
               (PENTEST-REPORT.md §8).  Used by routes that need no session.
  Usage      : "middleware": "MyAppPublic"
 -----------------------------------------------------------*/

FUNCTION MyAppPublic( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwSecHeaders" ) )

RETURN o:Run()
