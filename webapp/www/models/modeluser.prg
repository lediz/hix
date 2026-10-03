// --------------------------------------------------------------------------------
// ModelUser — RDDCDX-backed persistent authentication
// Reads from data/users.dbf (CDX index on NAME tag 'name')
// Complies with DEV-compliance.md: HIX framework only, no SQL, local git
// --------------------------------------------------------------------------------

#include "hbclass.ch"

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
   hEntry[ "roles" ] := ( "USR" )->( FieldGet( FieldPos( "ROLES" ) ) )
   
   // Password comparison (case-sensitive)
   IF hEntry[ "pass" ] != cPass
      ( "USR" )->( DbCloseArea() )
      RETURN NIL
   ENDIF
   
   ( "USR" )->( DbCloseArea() )
   RETURN hEntry
