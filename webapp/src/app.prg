/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-10-05
  Version....: 2.0.0
  Description: HIX CRUD app bootstrap.

               Secrets: HIX reads its signing keys from www/config.json
               ("keys" section) at Start().  They used to be fixed literals
               committed to this repository, which is the same exposure as the
               published HIX defaults - anyone with repo access can forge CSRF
               tokens, session ids and @RESOURCE ids.

               Now: www/config.json is gitignored and this bootstrap guarantees
               a strong, per-installation key set before the server starts.
               Each key is taken from the environment first
               (HIX_KEY_CSRF / HIX_KEY_JWT / HIX_KEY_SESSION / HIX_KEY_TOKEN /
               HIX_KEY_RESOURCE), then from the file, and only generated when
               neither supplies a usable value.  Generation uses hb_RandStr()
               (Harbour core RTL -> hb_arc4random_buf, seeded from
               /dev/urandom), so no hbct contrib and no change to app.hbp.

               Keys are persisted, so tokens stay valid across restarts.
               Changing a key invalidates every token issued before it.

               Credentials: admin/1234  carles/1234  maria/1234
                            John/5678    jane/9012abcd   (see regenerate_users.prg)
 -----------------------------------------------------------*/

#include "hbclass.ch"

#DEFINE HIX_APP_CONFIG      "www/config.json"
#DEFINE HIX_MW_CONFIG       "www/middlewares/config.json"
#DEFINE HIX_KEY_MIN_LEN     32
#DEFINE HIX_KEY_NAMES       { "csrf", "jwt", "session", "token", "resource" }

FUNCTION Main()

   LOCAL oServer

   // Signing keys must exist before HIX loads www/config.json in Start().
   _AppKeysEnsure( HIX_APP_CONFIG )

   oServer := THixServer():New()

   // In HIXSTYLE mode, the root folder is protected.
   // Our application test is located within the /test folder,
   // and we need to enable it to be run directly from our
   // browser: https://localhost:9090/test/index.html

   oServer:AllowDir( "test", .F. )
   oServer:AllowDir( "customer", .T. )

   // ---------------------------------------------------------

   // Middleware setup (required by MyAppAuthRoleEdit / MyAppLogin).
   // No secret here: HIX_MwCsrfCheck reads it from the key store, which
   // _AppKeysEnsure() has already populated from www/config.json.
   // Redirect on CSRF failure -> /login.  Token TTL 3600 s.
   HIX_MwCsrfSetup( "/login", NIL, NIL, NIL, 3600 )
   HIX_MwRateLimitSetup( _MwCfgNum( "ratelimit", "ip_per_min", 300 ), ;
                         _MwCfgNum( "ratelimit", "window_s",    60  ) )

   oServer:Start()

RETURN NIL


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

   xVal := hb_jsonDecode( cJson )

   IF ! ValType( xVal ) == 'H'
      RETURN NIL
   ENDIF

RETURN xVal


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
// _AppKeysEnsure -- guarantee www/config.json carries a strong key set
// before THixServer():New() loads it.  Returns the number of keys created.
//
// Precedence: environment variable > file value > freshly generated.
// ============================================================
STATIC FUNCTION _AppKeysEnsure( cFile )

   LOCAL hCfg  := _JsonRead( cFile )
   LOCAL hKeys
   LOCAL aNames := HIX_KEY_NAMES
   LOCAL cName, cVal, cEnv, nNew := 0, nI

   IF hCfg == NIL
      hCfg := { => }
   ENDIF

   hKeys := hb_HGetDef( hCfg, "keys", NIL )

   IF ! ValType( hKeys ) == 'H'
      hKeys := { => }
      hCfg[ "keys" ] := hKeys
   ENDIF

   FOR nI := 1 TO Len( aNames )

      cName := aNames[ nI ]

      // 1. explicit override, e.g. for a container or a CI runner
      cEnv := hb_getEnv( "HIX_KEY_" + Upper( cName ) )
      cVal := iif( _KeyUsable( cEnv ), cEnv, NIL )

      // 2. whatever this installation already has
      IF cVal == NIL
         cVal := hb_HGetDef( hKeys, cName, NIL )
         IF ! _KeyUsable( cVal )
            cVal := NIL
         ENDIF
      ENDIF

      // 3. nothing usable yet -> generate once and persist it
      IF cVal == NIL
         cVal     := _RandKey()
         hKeys[ cName ] := cVal
         nNew++
      ENDIF

   NEXT

   IF nNew > 0

      IF ! _JsonWrite( cFile, hCfg )
         ? "app.prg: could not write signing keys to " + cFile
      ELSE
         ? "app.prg: generated " + hb_ntos( nNew ) + " signing key(s) in " + cFile
      ENDIF

   ENDIF

RETURN nNew


// ============================================================
// _MwCfgNum -- read a numeric value from the middleware config before
// HIX_LoadMiddleware() runs (it only runs inside Start()).  The previous
// call passed UConfig( "setup", "ratelimit", "ip_per_min" ), which returns
// the whole hash or the default string, so HIX_MwRateLimitSetup silently
// ignored it and the global limiter kept HIX's built-in 60/60.
// ============================================================
STATIC FUNCTION _MwCfgNum( cSection, cKey, nDefault )

   LOCAL hCfg := _JsonRead( HIX_MW_CONFIG )
   LOCAL hSec, xVal

   IF hCfg == NIL
      RETURN nDefault
   ENDIF

   hSec := hb_HGetDef( hCfg, "setup", NIL )

   IF ! ValType( hSec ) == 'H'
      RETURN nDefault
   ENDIF

   hSec := hb_HGetDef( hSec, cSection, NIL )

   IF ! ValType( hSec ) == 'H'
      RETURN nDefault
   ENDIF

   xVal := hb_HGetDef( hSec, cKey, NIL )

   IF ! ValType( xVal ) == 'N'
      RETURN nDefault
   ENDIF

RETURN xVal
