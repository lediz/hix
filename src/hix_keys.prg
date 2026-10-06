/*-----------------------------------------------------------
  File ......: hix_keys.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-29
  Modified...: 2026-07-14
  Description: In-memory named key store — single source for every
               HIX engine that needs a secret (JWT, session, token,
               CSRF, resource, future DB creds).

               Loads keys from config.json > "keys" section (hixstyle)
               or from user code via HIX_KeySet (standalone).
               Engines read via HIX_KeyGet — never care about origin.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_CONFIG

#INCLUDE "hix_logger.ch"

STATIC s_hKeys := { => }

// ============================================================
// HIX_KeySet — store or override a named key.
// Call from Main() before oSrv:Start() in standalone deployments.
// ============================================================
FUNCTION HIX_KeySet( cName, cVal )

   s_hKeys[ cName ] := cVal

RETURN NIL

// ============================================================
// HIX_KeyGet — read a named key. Returns cDefault when absent.
// ============================================================
FUNCTION HIX_KeyGet( cName, cDefault )

   hb_default( @cDefault, "" )

RETURN hb_HGetDef( s_hKeys, cName, cDefault )

// ============================================================
// HIX_KeyExists — .T. if a key is in the store.
// ============================================================
FUNCTION HIX_KeyExists( cName )
RETURN hb_HHasKey( s_hKeys, cName )

// ============================================================
// HIX_KeysLoadFromAppConfig — copy config.json > "keys" section
// into the store, then make sure every known slot has a key.
//
// Order of trust (PENTEST-REPORT.md §1):
//   1. HIX_KeySet() from the app bootstrap  — env vars, a file outside
//      paths.root, anything the application controls
//   2. config.json > keys                   — legacy location, INSIDE the
//      document root, kept working for existing installs
//   3. generated in memory                  — never a published default,
//      never written to disk
// Returns the number of keys copied from the app config.
// ============================================================
FUNCTION HIX_KeysLoadFromAppConfig()

   LOCAL hKeys, cName, nCount := 0, nGen := 0
   LOCAL aSlots := { "csrf", "jwt", "session", "token", "resource" }

   hKeys := HIX_ConfigApp( "keys", NIL )

   IF HB_ISHASH( hKeys )

      FOR EACH cName IN hb_HKeys( hKeys )

         // A key the application installed itself wins: config.json lives
         // under paths.root and is served as a static file, so it is the
         // last place to trust a secret from.
         IF hb_HHasKey( s_hKeys, cName ) .AND. ! Empty( s_hKeys[ cName ] )

            lw( "HIX_Keys: '" + cName + "' already set by the application — " + ;
                "config.json value ignored (do not keep keys under paths.root)" )
            LOOP

         ENDIF

         s_hKeys[ cName ] := hKeys[ cName ]
         nCount++

         // Warn loudly when a key still carries the published default pattern.
         // Published defaults are predictable — anyone who reads the source can
         // forge tokens, sessions and CSRF. Replace them (A1.16).
         IF ValType( hKeys[ cName ] ) == "C" .AND. "H!x@" $ hKeys[ cName ]

            lw( "SECURITY: key '" + cName + "' uses a published default — " + ;
                "replace it before deploying to production" )

         ENDIF

      NEXT

   ENDIF

   // No slot may stay empty or fall back to a published default (A1.16).
   // Anything missing is generated in memory only: the app config file is
   // inside the document root, so nothing secret is ever written to it.
   FOR EACH cName IN aSlots

      IF Empty( hb_HGetDef( s_hKeys, cName, "" ) )

         s_hKeys[ cName ] := _HixGenKey()
         nGen++

      ENDIF

   NEXT

   IF nGen > 0

      lw( "HIX_Keys: " + hb_ntos( nGen ) + " key(s) generated in memory and NOT persisted — " + ;
          "every token/session issued dies with the process. Provide them with " + ;
          "HIX_KeySet() (environment variable or a file outside paths.root) " + ;
          "to keep them valid across restarts" )

   ENDIF

   l( "HIX_Keys: " + hb_ntos( nCount ) + " from config.json, " + ;
     hb_ntos( nGen ) + " generated, " + hb_ntos( Len( s_hKeys ) ) + " in store" )

RETURN nCount

// ============================================================
// _HixGenKey — 64 hex chars from 32 bytes of CSPRNG output.
// hb_RandStr() is Harbour core RTL (src/rtl/hbrand.c -> hb_arc4random_buf,
// seeded from /dev/urandom).  Not derived from a timestamp, so two
// installations started at the same millisecond cannot collide.
// ============================================================
STATIC FUNCTION _HixGenKey()
RETURN hb_sha256( hb_RandStr( 32 ) )

// ============================================================
// HIX_KeysAsHash — returns a hash with the key NAMES only
// (values masked). Safe for logging / monitor endpoints.
// ============================================================
FUNCTION HIX_KeysAsHash()

   LOCAL hOut := { => }
   LOCAL cName, cVal

   FOR EACH cName IN hb_HKeys( s_hKeys )

      cVal := s_hKeys[ cName ]

      IF ValType( cVal ) == "C" .AND. Len( cVal ) > 4

         hOut[ cName ] := Left( cVal, 2 ) + "***" + Right( cVal, 2 )
      ELSE
         hOut[ cName ] := "***"

      ENDIF

   NEXT

RETURN hOut

// ============================================================
// HIX_KeysReset — clear the store. Test-only helper.
// ============================================================
FUNCTION HIX_KeysReset()

   s_hKeys := { => }

RETURN NIL
