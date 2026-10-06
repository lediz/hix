/*-----------------------------------------------------------
  File ......: hix_csrf.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-27
  Description: CSRF token helpers built on top of hix_token.prg.
               Uses HIX_KeyGet("app_key") as the HMAC secret, loaded
               from config.json via HIX_ConfigAppLoad().
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

// ============================================================
// _HixCsrfSecret -- returns the HMAC secret from HIX_Keys("app_key").
// Falls back to a built-in default if app_key is not configured.
// ============================================================
STATIC FUNCTION _HixCsrfSecret()
RETURN HIX_KeyGet( "csrf", "H!x@CSRF@2026" )

// ============================================================
// HIX_CsrfGenRandom -- delegates to HIX_TokenGenRandom.
// ============================================================
FUNCTION HIX_CsrfGenRandom( nLen )
RETURN HIX_TokenGenRandom( nLen )

// ============================================================
// _HixCsrfCtx -- the current THixContext, whichever thread we are in.
// The action (controller + view) runs in an execution sub-thread, where the
// THREAD STATIC context of HIX_GetContext() is NIL; the dispatcher stores the
// context in oReq:hData["_ctx"] exactly so UContext() works there.
// ============================================================
STATIC FUNCTION _HixCsrfCtx()

   LOCAL oReq := HIX_GetRequest()
   LOCAL oCtx

   IF oReq != NIL

      oCtx := hb_HGetDef( oReq:hData, "_ctx", NIL )

      IF oCtx != NIL
         RETURN oCtx
      ENDIF

   ENDIF

RETURN HIX_GetContext()

// ============================================================
// _HixCsrfBind -- the value every CSRF token is bound to: the session id
// of the request that rendered the form (PENTEST-REPORT.md §5).
// Returns "" when the current context has no session (stateless callers,
// CLI tests, public pages): the binding check is then skipped.
// ============================================================
STATIC FUNCTION _HixCsrfBind()

   LOCAL oCtx := _HixCsrfCtx()

   IF oCtx == NIL
      RETURN ""
   ENDIF

RETURN hb_HGetDef( oCtx:hData, "_sid", "" )

// ============================================================
// HIX_CsrfMakeToken -- signed token using the app_key.
// The payload carries the session id of the request rendering the form, so
// a token is only usable by the session that was served it: it cannot be
// replayed in another session and it cannot be minted offline without both
// the signing key and a live session id.
// ============================================================
FUNCTION HIX_CsrfMakeToken( cData )

   hb_default( @cData, _HixCsrfBind() )

   // No session in this context: fall back to the old unbound random token.
   IF Empty( cData )
      cData := HIX_TokenGenRandom( 16 )
   ENDIF

RETURN HIX_TokenMake( cData, _HixCsrfSecret() )

// ============================================================
// HIX_CsrfBound -- .T. when the token payload is the current session id.
// Always .T. when this request has no session to bind against.
// ============================================================
FUNCTION HIX_CsrfBound( cToken )

   LOCAL cSid := _HixCsrfBind()
   LOCAL cPayload, cData
   LOCAL aParts
   LOCAL nLast, nI

   IF Empty( cSid )
      RETURN .T.
   ENDIF

   hb_default( @cToken, "" )

   aParts := hb_ATokens( cToken, "." )

   IF Len( aParts ) != 2
      RETURN .F.
   ENDIF

   // payload layout (HIX_TokenMake): data "|" unix_ts
   cPayload := hb_base64Decode( aParts[ 1 ] )
   aParts   := hb_ATokens( cPayload, "|" )
   nLast    := Len( aParts )

   IF nLast < 2
      RETURN .F.
   ENDIF

   cData := ""
   FOR nI := 1 TO nLast - 1
      cData += aParts[ nI ]
      IF nI < nLast - 1
         cData += "|"
      ENDIF
   NEXT

RETURN HIX_ConstantEq( cData, cSid )

// ============================================================
// HIX_CsrfValidToken -- validates with the app_key.
// ============================================================
FUNCTION HIX_CsrfValidToken( cToken, nLapsus )
RETURN HIX_TokenValid( cToken, nLapsus, _HixCsrfSecret() )

// ============================================================
// UCsrfToHtml -- hidden <input> ready to embed in forms.
// ============================================================
FUNCTION UCsrfToHtml( cToken )
   LOCAL cHtml 

   hb_default( @cToken, HIX_CsrfMakeToken() )

// @format:off
   cHtml := '<input type="hidden" name="_csrf" value="' + cToken + '">'
// @format:on   
   
RETURN cHtml 
