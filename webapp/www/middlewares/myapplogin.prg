/*-----------------------------------------------------------
  File ......: myapplogin.prg
  Author.....: Charly 9000
  Created....: 2026-05-27
  Modified...: 2026-10-05
  Version....: 2.1.0
  Description: Middleware group for unauthenticated login POST.
               MyAppLogin = Session + LoginRateLimit + CsrfCheck.

               D-07: the global HIX_MwRateLimit (60 req/min, set in
               src/app.prg) is far too loose for a credential endpoint.
               This route now applies its own sliding window via
               HIX_MwRateLimitFactory, so /auth cannot be used for password
               spraying while the rest of the app keeps the global limit.

               N-01 follow-up: the window now defaults to the audit value
               (5 attempts / 60 s) and is overridable from
               www/middlewares/config.json -> setup.ratelimit.login_max /
               login_window_s, so a test build can widen it without editing
               source.  test/verify-users-fixes.sh is rate-limit aware: it
               waits for a free slot instead of failing.
  Usage      : "middleware": "MyAppLogin"   (POST /auth)
 -----------------------------------------------------------*/

#define LOGIN_MAX_ATTEMPTS 5
#define LOGIN_WINDOW_SECS  60

FUNCTION MyAppLogin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( MyAppLoginLimit(), "login-rate-limit" ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )

RETURN o:Run()


// Per-route limiter for the credential endpoint.
// HIX_MwRateLimitFactory shares one sliding-window bucket per client IP, so
// this must stay the only limiter applied to /auth.
STATIC FUNCTION MyAppLoginLimit()

   LOCAL nMax, nWindow

   nMax    := UMwConfig( "ratelimit", "login_max",    LOGIN_MAX_ATTEMPTS )
   nWindow := UMwConfig( "ratelimit", "login_window", LOGIN_WINDOW_SECS  )

   IF ! ValType( nMax ) == 'N' .OR. nMax < 1
      nMax := LOGIN_MAX_ATTEMPTS
   ENDIF

   IF ! ValType( nWindow ) == 'N' .OR. nWindow < 1
      nWindow := LOGIN_WINDOW_SECS
   ENDIF

RETURN HIX_MwRateLimitFactory( nMax, nWindow )
