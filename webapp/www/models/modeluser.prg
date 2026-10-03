// --------------------------------------------------------------------------------
// ModelUser — RDDCDX-backed persistent authentication
// Reads from data/users.dbf (CDX index on NAME tag 'name')
// Complies with DEV-compliance.md: HIX framework only, no SQL, local git
// --------------------------------------------------------------------------------

#include "hbclass.ch"

// Parse ROLES string into hash matching CRUD example format
// Input:  "customers:search;show;edit"
// Output: { "customers" => "search;show;edit" }
STATIC FUNCTION _ParseRoles( cRolesStr )
   LOCAL hRoles := hb_Hash()
   LOCAL aParts
   
   IF Empty( cRolesStr )
      RETURN hRoles
   ENDIF
   
   // Trim trailing spaces (DBF C field padding) before parsing
   cRolesStr := ALLTRIM( cRolesStr )
   
   // Split on ":" to get role name and ops
   aParts := hb_ATokens( cRolesStr, ":" )
   IF Len( aParts ) >= 2
      hRoles[ aParts[1] ] := aParts[2]
   ENDIF
   
RETURN hRoles

FUNCTION ModelUser( cUser, cPass )
   LOCAL hEntry
   LOCAL cData
   LOCAL cTag
   
   // Data path (same as customers.dbf)
   cData := hb_dirbase() + UConfig( "paths", "data", "data" ) + "/users"
   
   // Open RDDCDX using USE with INDEX (file without extension)
   rddSetDefault( "DBFCDX" )
   USE ( cData ) INDEX ( cData ) ALIAS "USR" SHARED
   ( "USR" )->( DbGoTop() )
   
   // Case-insensitive search: seek on Lower(name) via index
   ( "USR" )->( DbSeek( Lower( cUser ) ) )
   
   IF ( "USR" )->( Eof() )
      ( "USR" )->( DbCloseArea() )
      RETURN NIL
   ENDIF
   
   // Build entry from current record
   hEntry := hb_Hash()
   hEntry[ "id" ] := ( "USR" )->( FieldGet( FieldPos( "ID" ) ) )
   hEntry[ "name" ] := ( "USR" )->( FieldGet( FieldPos( "NAME" ) ) )
   hEntry[ "pass" ] := ( "USR" )->( FieldGet( FieldPos( "PASS" ) ) )
   
   // Parse ROLES string into hash matching CRUD example format
   // ROLES format: "role:ops" (e.g. "customers:search;show;edit")
   // Result: { "customers" => "search;show;edit" }
   hEntry[ "roles" ] := _ParseRoles( ( "USR" )->( FieldGet( FieldPos( "ROLES" ) ) ) )
   
   // Password comparison (case-sensitive)
   IF hEntry[ "pass" ] != cPass
      ( "USR" )->( DbCloseArea() )
      RETURN NIL
   ENDIF
   
   ( "USR" )->( DbCloseArea() )
   RETURN hEntry
