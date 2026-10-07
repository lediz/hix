/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-10-05
  Version....: 2.0.0
  Description: HIX CRUD app bootstrap.

               Secrets: signing keys must never live inside the document
               root.  paths.root is www/, and HIX serves root-level files of
               the docroot, so a www/config.json that carries the "keys"
               section is downloadable by anyone (PENTEST-REPORT.md §1): the
               five HMAC secrets behind CSRF, sessions, tokens and resource
               ids were public over HTTPS.

               Now, in this order:
                 1. environment  HIX_KEY_CSRF / HIX_KEY_JWT / HIX_KEY_SESSION
                                 / HIX_KEY_TOKEN / HIX_KEY_RESOURCE
                 2. hix.keys.json  - outside the docroot, 0600, gitignored
                                     (created by ./gen_keys.sh)
                 3. freshly generated with hb_RandStr() (Harbour core RTL ->
                    hb_arc4random_buf, seeded from /dev/urandom) and written
                    to hix.keys.json
               Each resolved key is handed to HIX with HIX_KeySet() before
               Start(), so HIX never has to read a key from the docroot.  Any
               legacy "keys" section found in www/config.json is deleted on
               startup (it is already compromised: rotating is mandatory).

               Belt and braces: /config.json is answered with 404 by a route
               (routes are matched before static file serving).

               Keys are persisted, so tokens stay valid across restarts.
               Changing a key invalidates every token issued before it.

               Surface: the HIX admin panel is disabled in hix.json, /hix-slow
               is overridden, and no docroot directory is served or granted
               script execution unless app.env == "dev".

               Credentials: admin/1234  carles/1234  maria/1234
                            John/5678    jane/9012abcd   (seeded into users_users by
                            ./seed_users_mysql - the store is the MySQL table in
                            sql/hix_users.sql, not data/users.dbf)
 -----------------------------------------------------------*/

#include "hbclass.ch"
//  hbsocket.ch is for the P2.4 reachability probe (hb_socketOpen /
//  hb_socketConnect / HB_SOCKET_AF_INET), not for anything else here.
#include "hbsocket.ch"

#DEFINE HIX_APP_CONFIG      "www/config.json"
#DEFINE HIX_MW_CONFIG       "www/middlewares/config.json"
#DEFINE HIX_SERVER_CONFIG   "hix.json"
#DEFINE HIX_KEY_MIN_LEN     32
#DEFINE HIX_KEY_NAMES       { "csrf", "jwt", "session", "token", "resource" }
// Outside paths.root (www/), so no URL can reach it.  ./gen_keys.sh creates
// it with 0600; gitignored.
#DEFINE HIX_KEY_STORE       "hix.keys.json"

// P2 of webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md: the MySQL/MariaDB
// pool key. www/config.json's "databases" block stays EMPTY on purpose -
// that file sits inside paths.root (www/), so a password declared there is
// a document-root file (PENTEST-REPORT.md section 1 is the same finding for
// the signing keys). The pool is built here, from the environment.
#DEFINE HIX_DB_POOL_KEY     "mysql"

FUNCTION Main()

   LOCAL oServer
   LOCAL lDbPool := .F.

   // Signing keys must be in the HIX key store before Start() loads
   // www/config.json and before HIX_MwSessionSetup() resolves keys.session.
   _AppKeysEnsure( HIX_APP_CONFIG, HIX_KEY_STORE )

   // HIX only builds the SSL context per connection, so a missing certificate
   // does not stop the server: it starts happily and then fails every request.
   IF ! _TlsGuard()
      RETURN NIL
   ENDIF

   oServer := THixServer():New()

   // In HIXSTYLE mode, the root folder is protected.
   // Our application test is located within the /test folder, and it is only
   // reachable when this installation is explicitly a development one
   // (hix.json -> app.env = "dev").  In production the harness - its
   // endpoints and expected payloads - is not served at all
   // (PENTEST-REPORT.md §9).
   IF _AppEnv() == "dev"
      oServer:AllowDir( "test", .F. )
   ENDIF
   // AllowDir( cDir, lAllowExec ) grants EXECUTION of files in that directory,
   // bypassing www/routes/web.json and its middleware/scope.  Nothing here
   // needs it, so it is never requested.

   // ---------------------------------------------------------

   // Middleware setup (required by MyAppAuthRoleEdit / MyAppLogin).
   // No secret here: HIX_MwCsrfCheck reads it from the key store, which
   // _AppKeysEnsure() has already populated.
   // Redirect on CSRF failure -> /login.  Token TTL 3600 s.
   HIX_MwCsrfSetup( "/login", NIL, NIL, NIL, 3600 )
   HIX_MwRateLimitSetup( _MwCfgNum( "ratelimit", "ip_per_min", 300 ), ;
                         _MwCfgNum( "ratelimit", "window_s",    60  ) )
   // Security headers for every application route (PENTEST-REPORT.md §8).
   HIX_MwSecHeadersSetup( _MwCfgStr( "secheaders", "csp", _CspDefault() ) )

   // Neutralise the framework surface this application does not use.
   // HIX_LoadConfig() is idempotent and must run first: THixServer():Start()
   // loads hix.json only later, and HIX_RoutesLoad() decides from
   // UConfig("admin","enabled") whether the 13 admin routes exist at all.
   // Without this call the router would be built from HIX's built-in defaults
   // and the admin panel would be registered despite admin.enabled = false.
   HIX_LoadConfig()

   _GuardSurface()

   // P2: the MySQL/MariaDB pool. Credentials come from the environment
   // (DB_PWD / DB_USER / DB_NAME / DB_HOST / DB_PORT), never from
   // www/config.json. Absent DB_PWD there is no pool and the app keeps
   // running on its DBF state - Step 0.2 (Option A: MySQL replaces DBFCDX)
   // has not been taken, so the DBF DAL is still what ships.
   lDbPool := _DbPoolEnsure()

   oServer:Start()

   // P2.4: nothing here aborts. HIX's own abort path for a declared pool
   // (src/wdo/wdo_config.prg) prints "==> Fatal ..." and then waits on
   // Inkey( 0 ) before QUIT - a non-interactive start hangs there. The
   // pool is closed on exit instead, and a handler that needs it answers
   // 503 with WDO_PoolStats diagnostics (P3.6's error mapping).
   IF lDbPool
      WDO_EndPoolMySql()
   ENDIF

RETURN NIL


// ============================================================
// _GuardSurface - system routes HIX registers by itself, overridden
// from the application.  HIX_RoutesLoad() is idempotent ("already
// initialized - idempotent to allow calling before Start()") and is
// called here so these HIX_RouteAdd( ..., lReplace := .T. ) calls replace
// the framework entries instead of racing with Start().
//
//   /config.json  root-level docroot file -> 404 (§1)
//   /hix-slow     unauthenticated hb_idleSleep( 3 ) per GET, pins one of
//                 the 64 HTTP workers -> 404 (§3)
// ============================================================
STATIC PROCEDURE _GuardSurface()

   HIX_RoutesLoad()

   HIX_RouteAdd( "deny.config", "/config.json", ;
      {| oReq | oReq:Respond( hb_jsonEncode( { "error" => "not found" } ), 404, "json" ) }, ;
      "GET,HEAD", "", "", NIL, .T. )

   HIX_RouteAdd( "hix.slow", "/hix-slow", ;
      {| oReq | oReq:Respond( hb_jsonEncode( { "error" => "not found" } ), 404, "json" ) }, ;
      "GET", "", "", NIL, .T. )

RETURN


// ============================================================
// APP_MYSQL_BERROR - P3.6: the pool's error handler, reached through
// hParams["berror"] (a NAME, resolved by _WdoResolveBErrorFromName).
// Non-STATIC on purpose: hb_isFunction() has to find it in the symbol
// table. It logs the server's words and returns nothing usable to the
// client - the response text is the SRS banner, decided by the DAL
// (www/models/tdalmysql.prg Errors()), never by the server (SRS 5.3).
// ============================================================
FUNCTION APP_MYSQL_BERROR( oErr, oConn )

   LOCAL cMsg := ""

   IF ValType( oErr ) == 'O'
      cMsg := hb_defaultValue( oErr:description, "" )
   ELSE
      cMsg := hb_defaultValue( oErr, "" )
   ENDIF

   _l( "mysql berror: " + cMsg, 4, "mysql" )

RETURN NIL


// ============================================================
// _EnvOr - an environment value with a default. hb_getEnv() answers
// "" (an empty string, not NIL) for a variable that is not in the
// environment, and hb_defaultValue() only substitutes through a by-
// reference argument, so hb_defaultValue( hb_getEnv( ... ), d ) hands
// back the empty string: DB_POOL came out as Val( "" ) = 0 and the
// driver got dll="" -> "Cannot load MySql DLL". Explicit here.
// ============================================================
STATIC FUNCTION _EnvOr( cName, cDefault )

   LOCAL cVal := hb_getEnv( cName )

   IF cVal == NIL .OR. Empty( cVal )
      RETURN cDefault
   ENDIF

RETURN cVal


// ============================================================
// _DbReachable - P2.4: is anything listening on that host:port, before
// the pool is built.
//
//  The WDO MySQL driver has its own TCP preflight (src/wdo/mysql/
//  wdo_mysql.prg, _WdoMySqlTcpProbe -> _WdoMySqlReportDown). When it
//  fails the driver prints "==> Error: Mysql not running", then
//  Inkey( 0 ) and QUIT - so a pool built against a dead server does not
//  fail, it BLOCKS the start forever and the accept loop is never
//  reached (observed: the app printed the message and never bound 9090).
//  Probing here means the driver is never asked, and the app starts with
//  no pool: /health/db answers 503 and a handler that needs the pool
//  answers 503 with WDO_PoolStats diagnostics. That is the plan's
//  dev-friendly branch of P2.4, reached without touching the framework.
//
//  Same shape as the driver's probe, including the localhost remap: on
//  Windows "localhost" often resolves to ::1 and AF_INET would block
//  instead of failing fast.
// ============================================================
STATIC FUNCTION _DbReachable( cHost, nPort )

   LOCAL hSock, lOk
   LOCAL cResolved := hb_defaultValue( cHost, "" )

   IF Empty( cResolved )
      RETURN .F.
   ENDIF

   IF Lower( AllTrim( cResolved ) ) == "localhost"
      cResolved := "127.0.0.1"
   ENDIF

   hSock := hb_socketOpen()
   IF hSock == NIL
      RETURN .F.
   ENDIF

   lOk := hb_socketConnect( hSock, ;
          { HB_SOCKET_AF_INET, cResolved, nPort }, 1500 )
   hb_socketClose( hSock )

RETURN lOk


// ============================================================
// _DbDllDefault - the client library to pin. The driver's compiled-in
// default names a Debian multiarch path (/usr/lib/x86_64-linux-gnu/)
// that does not exist on this distro, so the pool is pinned explicitly
// exactly as ./probe_mysql and ./create_mysql_sql do (DllSource() must
// report "override"). Windows needs no pin: the DLL ships in the repo
// (resources/wdo/mysql/dll/).
// ============================================================
STATIC FUNCTION _DbDllDefault()

   LOCAL aTry := { "/usr/lib/libmysqlclient.so", ;
                   "/usr/lib/libmariadb.so",     ;
                   "/usr/lib/libmariadb.so.3" }
   LOCAL nI

   FOR nI := 1 TO Len( aTry )
      IF File( aTry[ nI ] )
         RETURN aTry[ nI ]
      ENDIF
   NEXT

RETURN NIL


// ============================================================
// _DbPoolEnsure - P2.1..P2.3 + P2.5 of INVENTREE-MYSQL-PLAN.md.
//
//  P2.1 the pool the plan says to declare in www/config.json is built
//       here instead, with the same fields, because P2.5 says the
//       credentials must not live in a document-root file. WDO_InitPool
//       MySqlEx( cKey, hParams ) takes exactly the config.json entry as
//       a hash (src/wdo/mysql/wdo_mysql_pool.prg:88), so the two paths
//       differ only in where the values come from.
//  P2.2 read_timeout_s 45 > hix.json -> server.exec_timeout_ms 30000 ms.
//       Left at the 30 s default, MySQL kills a 30 s query before the
//       dispatcher does and the slot never returns to the pool.
//  P2.3 pool_size 8 against hix.json -> pool_http.workers 64; Little's
//       Law says 500 req/s x 10 ms = 5 slots, so 8 is the margin. The
//       server side of the cascade (max_connections = pool + 30) is set
//       by ./gen_mysql_db.sh on the host under .mysql/.
//  P2.5 DB_PWD / DB_USER / DB_NAME / DB_HOST / DB_PORT / DB_DLL from the
//       environment, the same precedence HIX_KEY_* already has.
//
//  No password is ever printed. Absent DB_PWD, no pool is started and
//  the app runs as it did before P1.
//
//  TRUE = a pool with at least one connection is registered.
// ============================================================
STATIC FUNCTION _DbPoolEnsure()

   LOCAL cHost, cUser, cPwd, cDb, cDll, cDriver
   LOCAL hParams
   LOCAL nPort, nPool, nRead, nConnect, nOk

   cPwd := hb_getEnv( "DB_PWD" )

   IF Empty( cPwd )
      ? "app.prg: DB_PWD is not set - no MySQL/MariaDB pool is started."
      ? "app.prg: the app runs on its DBF state; a handler that needs the"
      ? "app.prg: pool answers 503 with WDO_PoolStats diagnostics."
      RETURN .F.
   ENDIF

   cHost    := _EnvOr( "DB_HOST",              "127.0.0.1" )
   nPort    := Val( _EnvOr( "DB_PORT",         "3306" ) )
   cUser    := _EnvOr( "DB_USER",              "harbour" )
   cDb      := _EnvOr( "DB_NAME",              "inventree" )
   cDriver  := Lower( _EnvOr( "DB_DRIVER",     "mariadb" ) )
   nPool    := Val( _EnvOr( "DB_POOL",         "8" ) )
   nRead    := Val( _EnvOr( "DB_READ_TIMEOUT_S",   "45" ) )
   nConnect := Val( _EnvOr( "DB_CONNECT_TIMEOUT_S", "10" ) )
   cDll     := _EnvOr( "DB_DLL",              NIL )

   IF cDll == NIL
      cDll := _DbDllDefault()
   ENDIF

   //  P2.4, decided here rather than discovered by watching the app
   //  refuse to start: no abort, no Inkey. Dead server -> no pool.
   IF ! _DbReachable( cHost, nPort )
      ? "app.prg: nothing is listening on " + cHost + ":" + hb_NToS( nPort ) ;
        + " - no pool is started."
      ? "app.prg: the app starts anyway; /health/db answers 503 and any"
      ? "app.prg: handler that needs the pool answers 503 too."
      ? "app.prg: start the host (./gen_mysql_db.sh start) and restart the"
      ? "app.prg: app to get the pool."
      RETURN .F.
   ENDIF

   hParams := { => }
   hParams[ "driver" ]           := cDriver
   hParams[ "host" ]             := cHost
   hParams[ "user" ]             := cUser
   hParams[ "pwd" ]              := cPwd
   hParams[ "db" ]               := cDb
   hParams[ "port" ]             := nPort
   hParams[ "pool_size" ]        := nPool
   hParams[ "timeout_ms" ]       := 5000
   hParams[ "ping" ]             := .T.
   hParams[ "read_timeout_s" ]   := nRead
   hParams[ "connect_timeout_s" ] := nConnect
   hParams[ "dll" ]              := cDll
   //  P3.6: the pool's error handler. berror is a Harbour function NAME -
   //  _WdoResolveBErrorFromName (src/wdo/wdo_config.prg) builds
   //  {|oErr, oConn| NAME( oErr, oConn ) } and hb_isFunction() probes the
   //  symbol table first, so the function has to be statically linked and
   //  NOT static in this file. Absent this, a MySQL error surfaces
   //  wherever the driver puts it, and the server's words name tables.
   hParams[ "berror" ]           := "APP_MYSQL_BERROR"

   //  P2.2, stated where it is set: the read timeout has to exceed the
   //  dispatcher's exec_timeout_ms or the slot becomes a zombie.
   IF nRead * 1000 <= 30000
      ? "app.prg: DB_READ_TIMEOUT_S is not above exec_timeout_ms (30000) -"
      ? "app.prg: a long query would be killed server-side and the slot"
      ? "app.prg: would never return to the pool. Raising it to 45."
      nRead := 45
      hParams[ "read_timeout_s" ] := nRead
   ENDIF

   ? "app.prg: MySQL/MariaDB pool '" + HIX_DB_POOL_KEY + "'"
   ? "app.prg:   " + cUser + "@" + cHost + ":" + hb_NToS( nPort ) + "/" + cDb ;
     + " driver=" + cDriver
   ? "app.prg:   pool_size=" + hb_NToS( nPool ) + " read_timeout_s=" ;
     + hb_NToS( nRead ) + " connect_timeout_s=" + hb_NToS( nConnect )
   IF cDll != NIL
      ? "app.prg:   client library pinned: " + cDll
   ENDIF

   nOk := WDO_InitPoolMySqlEx( HIX_DB_POOL_KEY, hParams )

   IF ! nOk
      ? "app.prg: the pool opened no connection - the app still starts,"
      ? "app.prg: and every handler that needs it answers 503."
      RETURN .F.
   ENDIF

RETURN .T.
STATIC FUNCTION _AppEnv()

   LOCAL hCfg := _JsonRead( HIX_SERVER_CONFIG )
   LOCAL hSec

   IF hCfg == NIL
      RETURN "prod"
   ENDIF

   hSec := hb_HGetDef( hCfg, "app", NIL )

   IF ! ValType( hSec ) == 'H'
      RETURN "prod"
   ENDIF

RETURN Lower( hb_HGetDef( hSec, "env", "prod" ) )


// ============================================================
// _CspDefault - CSP that matches what the views actually load:
// Bootstrap 5 + Bootstrap Icons from cdn.jsdelivr.net, local /public
// assets and the inline <script> blocks of the CRUD views.
// Overridable from www/middlewares/config.json -> setup.secheaders.csp.
// ============================================================
STATIC FUNCTION _CspDefault()

RETURN "default-src 'self'; " + ;
       "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; " + ;
       "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; " + ;
       "font-src 'self' https://cdn.jsdelivr.net; " + ;
       "img-src 'self' data:; " + ;
       "connect-src 'self'; " + ;
       "form-action 'self'; " + ;
       "frame-ancestors 'none'; " + ;
       "base-uri 'self'"


// ============================================================
// _RandKey -- 64 hex chars from 32 bytes of CSPRNG output.
// hb_RandStr() is Harbour core (src/rtl/hbrand.c -> hb_arc4random_buf),
// verified by test/probe_entropy.prg.
// ============================================================
STATIC FUNCTION _RandKey()

RETURN hb_sha256( hb_RandStr( 32 ) )


// ============================================================
// _JsonRead / _JsonWrite -- minimal JSON file helpers (Harbour core).
// ============================================================
STATIC FUNCTION _JsonRead( cFile )

   LOCAL cJson := hb_MemoRead( cFile )
   LOCAL xVal

   IF Empty( cJson )
      RETURN NIL
   ENDIF

   // hix.json opens with a /* ... */ banner and Harbour's JSON decoder
   // rejects it, so strip a leading block comment before decoding.
   xVal := hb_jsonDecode( _StripLeadComment( cJson ) )

   IF ! ValType( xVal ) == 'H'
      RETURN NIL
   ENDIF

RETURN xVal


STATIC FUNCTION _StripLeadComment( cText )

   LOCAL nPos

   IF Left( cText, 2 ) == "//"
      nPos := At( Chr( 10 ), cText )
      IF nPos > 0
         cText := SubStr( cText, nPos + 1 )
      ENDIF
   ELSEIF Left( cText, 2 ) == "/*"
      nPos := At( "*/", cText )
      IF nPos > 0
         cText := SubStr( cText, nPos + 2 )
      ENDIF
   ENDIF

RETURN cText


STATIC FUNCTION _JsonWrite( cFile, hData )

RETURN hb_MemoWrit( cFile, hb_jsonEncode( hData, .T. ) )


// ============================================================
// _KeyUsable -- long enough to be unguessable and not one of the
// published HIX defaults.
// ============================================================
STATIC FUNCTION _KeyUsable( cVal )

   IF ! ValType( cVal ) == 'C'
      RETURN .F.
   ENDIF

   IF Len( cVal ) < HIX_KEY_MIN_LEN
      RETURN .F.
   ENDIF

   IF "H!x@" $ cVal
      RETURN .F.
   ENDIF

RETURN .T.


// ============================================================
// _AppKeysEnsure - resolve the five signing keys and register them
// in the HIX key store (HIX_KeySet) before Start().  Nothing is ever
// written inside the document root.
//
// Precedence: environment variable > hix.keys.json > freshly generated.
//
// A legacy "keys" section found in www/config.json is DELETED, and its
// values are never reused: they were downloadable over HTTPS
// (PENTEST-REPORT.md §1), so they are compromised and must rotate.
//
// Returns the number of keys created.
// ============================================================
STATIC FUNCTION _AppKeysEnsure( cAppCfg, cStore )

   LOCAL hApp   := _JsonRead( cAppCfg )
   LOCAL hStore := _JsonRead( cStore )
   LOCAL hKeys
   LOCAL aNames := HIX_KEY_NAMES
   LOCAL cName, cVal, cEnv, nNew := 0, nI

   // 0. Legacy location.  www/config.json sits inside paths.root and HIX
   //    serves root-level docroot files, so a key stored there is public.
   IF ValType( hApp ) == 'H' .AND. hb_HHasKey( hApp, "keys" )

      hb_HDel( hApp, "keys" )

      IF _JsonWrite( cAppCfg, hApp )
         ? "app.prg: deleted the 'keys' section from " + cAppCfg + ;
           " - it is inside the document root and was readable over HTTP"
      ENDIF

   ENDIF

   IF hStore == NIL
      hStore := { => }
   ENDIF

   hKeys := hb_HGetDef( hStore, "keys", NIL )

   IF ! ValType( hKeys ) == 'H'
      hKeys := { => }
      hStore[ "keys" ] := hKeys
   ENDIF

   FOR nI := 1 TO Len( aNames )

      cName := aNames[ nI ]

      // 1. explicit override, e.g. for a container or a CI runner
      cEnv := hb_getEnv( "HIX_KEY_" + Upper( cName ) )
      cVal := iif( _KeyUsable( cEnv ), cEnv, NIL )

      // 2. whatever this installation already has, outside the docroot
      IF cVal == NIL
         cVal := hb_HGetDef( hKeys, cName, NIL )
         IF ! _KeyUsable( cVal )
            cVal := NIL
         ENDIF
      ENDIF

      // 3. nothing usable yet -> generate once and persist it outside www/
      IF cVal == NIL
         cVal     := _RandKey()
         hKeys[ cName ] := cVal
         nNew++
      ENDIF

      // Hand the key to HIX directly: no engine has to read a file for it.
      HIX_KeySet( cName, cVal )

   NEXT

   IF nNew > 0

      IF ! _JsonWrite( cStore, hStore )
         ? "app.prg: could not write signing keys to " + cStore
      ELSE
         ? "app.prg: generated " + hb_ntos( nNew ) + " signing key(s) in " + cStore
         ? "app.prg: run chmod 600 " + cStore + " (./gen_keys.sh does it)"
      ENDIF

   ENDIF

RETURN nNew


// ============================================================
// _TlsGuard -- refuse to start when server.ssl is on but the certificate
// pair is not there.  THixSocket:New() builds the SSL context per
// connection, so without this check the server binds the port, prints its
// banner, and then fails every single request.
// ============================================================
STATIC FUNCTION _TlsGuard()

   LOCAL hCfg := _JsonRead( HIX_SERVER_CONFIG )
   LOCAL hSrv, cCerts, cCert, cKey

   IF hCfg == NIL
      RETURN .T.
   ENDIF

   hSrv := hb_HGetDef( hCfg, "server", NIL )

   IF ! ValType( hSrv ) == 'H' .OR. ! hb_HGetDef( hSrv, "ssl", .F. )
      RETURN .T.
   ENDIF

   hCfg := hb_HGetDef( hCfg, "paths", NIL )
   cCerts := hb_DirSepAdd( hb_HGetDef( hCfg, "certs", "certs" ) )

   cCert := cCerts + hb_HGetDef( hSrv, "cert_public", "" )
   cKey  := cCerts + hb_HGetDef( hSrv, "cert_private", "" )

   IF File( cCert ) .AND. File( cKey )
      RETURN .T.
   ENDIF

   ? "app.prg: server.ssl is true but the certificate pair is missing:"
   ? "app.prg:   " + cCert
   ? "app.prg:   " + cKey
   ? "app.prg: run ./gen_cert.sh first (it is idempotent), then start the server."

RETURN .F.


// ============================================================
// _MwCfgNum -- read a numeric value from the middleware config before
// HIX_LoadMiddleware() runs (it only runs inside Start()).  The previous
// call passed UConfig( "setup", "ratelimit", "ip_per_min" ), which returns
// the whole hash or the default string, so HIX_MwRateLimitSetup silently
// ignored it and the global limiter kept HIX's built-in 60/60.
// ============================================================
STATIC FUNCTION _MwCfgNum( cSection, cKey, nDefault )

   LOCAL xVal := _MwCfgVal( cSection, cKey )

   IF ! ValType( xVal ) == 'N'
      RETURN nDefault
   ENDIF

RETURN xVal


// ============================================================
// _MwCfgStr -- same as _MwCfgNum for a string value (CSP policy).
// ============================================================
STATIC FUNCTION _MwCfgStr( cSection, cKey, cDefault )

   LOCAL xVal := _MwCfgVal( cSection, cKey )

   IF ! ValType( xVal ) == 'C' .OR. Empty( xVal )
      RETURN cDefault
   ENDIF

RETURN xVal


STATIC FUNCTION _MwCfgVal( cSection, cKey )

   LOCAL hCfg := _JsonRead( HIX_MW_CONFIG )
   LOCAL hSec

   IF hCfg == NIL
      RETURN NIL
   ENDIF

   hSec := hb_HGetDef( hCfg, "setup", NIL )

   IF ! ValType( hSec ) == 'H'
      RETURN NIL
   ENDIF

   hSec := hb_HGetDef( hSec, cSection, NIL )

   IF ! ValType( hSec ) == 'H'
      RETURN NIL
   ENDIF

RETURN hb_HGetDef( hSec, cKey, NIL )
