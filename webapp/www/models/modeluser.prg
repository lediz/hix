// --------------------------------------------------------------------------------
// ModelUser — RDDCDX-backed persistent authentication
// Reads from data/users.dbf (CDX index on NAME tag 'name')
// Complies with DEV-compliance.md: HIX framework only, no SQL, local git
// --------------------------------------------------------------------------------

#include "hbclass.ch"
#include "models/hpassword.prg"

// Parse ROLES string into hash matching CRUD example format
// Input:  "customers:search;show;edit"
// Output: { "customers" => "search;show;edit" }
STATIC FUNCTION _ParseRoles( cRolesStr )
   LOCAL hRoles := hb_Hash()
   LOCAL aParts, aPairs, nI, cRole, cOps
   
   IF Empty( cRolesStr )
      RETURN hRoles
   ENDIF
   
   // Trim trailing spaces (DBF C field padding) before parsing
   cRolesStr := ALLTRIM( cRolesStr )
   
   // Split on "|" to get individual role:ops pairs
   // Format: "role1:op1;op2;op3|role2:op1;op2"
   aPairs := hb_ATokens( cRolesStr, "|" )
   FOR nI := 1 TO Len( aPairs )
      aParts := hb_ATokens( ALLTRIM( aPairs[ nI ] ), ":" )
      IF Len( aParts ) >= 2
         cRole := ALLTRIM( aParts[1] )
         cOps  := ALLTRIM( aParts[2] )
         IF !empty( cRole ) .AND. !empty( cOps )
            hRoles[ cRole ] := cOps
         ENDIF
      ENDIF
   NEXT
   
RETURN hRoles

FUNCTION ModelUser( cUser, cPass )
   LOCAL hEntry
   LOCAL cData
   LOCAL cTag
   LOCAL cSeek
   LOCAL cFound
   LOCAL cStored
   LOCAL cSalt
   
   // Data path (same as customers.dbf)
   cData := hb_dirbase() + UConfig( "paths", "data", "data" ) + "/users"
   
   // D-16: the submitted name is normalised once and reused for the seek and
   // for the exact-match confirmation below.
   cSeek := Lower( AllTrim( cUser ) )
   
   // Open RDDCDX using USE with INDEX (file without extension)
   rddSetDefault( "DBFCDX" )
   USE ( cData ) INDEX ( cData ) ALIAS "USR" SHARED
   ( "USR" )->( DbGoTop() )
   
   // Case-insensitive search: the 'name' tag is keyed on Lower(name), so seek
   // the very same expression (D-16).
   ( "USR" )->( DbSeek( cSeek ) )
   
   // SET EXACT is .F. in www/config.json, so DbSeek can land on a longer key
   // (e.g. "carles" -> "carlesx").  Confirm an exact case-insensitive match.
   cFound := AllTrim( ( "USR" )->( FieldGet( FieldPos( "NAME" ) ) ) )
   
   IF ( "USR" )->( Eof() ) .OR. ! ( Lower( cFound ) == cSeek )
      ( "USR" )->( DbCloseArea() )
      RETURN NIL
   ENDIF
   
   // Read the stored digest + salt before anything is exposed (D-07)
   cStored := AllTrim( ( "USR" )->( FieldGet( FieldPos( "PASS" ) ) ) )
   cSalt   := AllTrim( ( "USR" )->( FieldGet( FieldPos( "SALT" ) ) ) )

   // D-07: users.dbf holds an iterated, salted SHA-256 digest, never the
   // password.  Re-hash the submitted password with the stored salt.
   IF ! _PwMatch( cStored, _PwHash( cPass, cSalt ) )
      ( "USR" )->( DbCloseArea() )
      RETURN NIL
   ENDIF

   // Build the session entry WITHOUT credentials (D-05): the session hash is
   // readable from every authenticated view and middleware.
   hEntry := hb_Hash()
   hEntry[ "id" ]    := ( "USR" )->( FieldGet( FieldPos( "ID" ) ) )
   hEntry[ "name" ]  := AllTrim( ( "USR" )->( FieldGet( FieldPos( "NAME" ) ) ) )
   
   // Parse ROLES string into hash matching CRUD example format
   // ROLES format: "role:ops" (e.g. "customers:search;show;edit")
   // Result: { "customers" => "search;show;edit" }
   hEntry[ "roles" ] := _ParseRoles( ( "USR" )->( FieldGet( FieldPos( "ROLES" ) ) ) )
   
   ( "USR" )->( DbCloseArea() )
   RETURN hEntry
