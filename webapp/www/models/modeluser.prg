// --------------------------------------------------------------------------------
// ModelUser — the login identity, read from the MySQL credential store
//
// P4.8 of webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md (Step 0.2, Option A for
// `users`): the store that owns the login identity is users_users, shipped in
// webapp/sql/hix_users.sql and seeded by ./seed_users_mysql. The DBF store this
// replaces (data/users.dbf, CDX tag keyed on Lower(NAME)) is gone; the customer
// module keeps its RDDCDX store on purpose, as the proof-of-concept.
//
// What is preserved from the audited DBF module, and how it is done now:
//   D-05  the session entry carries NO credentials - id, name, roles only
//   D-07  the store holds a salted, iterated SHA-256 digest (hpassword.prg),
//         never the password; the submitted password is re-hashed with the
//         stored salt and compared with _PwMatch
//   D-16  the submitted name is normalised once and reused; the match is
//         confirmed exactly, case-insensitively. The CDX tag keyed on
//         Lower(name) is replaced by the server's utf8mb4_unicode_ci
//         collation (P0.4) plus the confirmation below, which is what a
//         collated equality can get wrong (a longer key matching a prefix)
//   D-17  the full work factor is paid even when the name does not exist, so
//         response time is not a user-enumeration oracle
//   +     ROLES is parsed into a hash (the middlewares read scopes from it)
//
// One pool slot per login (P3.4): acquired here and closed here, on every path.
// Complies with DEV-compliance.md: HIX framework only (SQL under the exception
// recorded 2026-10-07 for the MySQL DAL phases), tools inside the project folder.
// --------------------------------------------------------------------------------

#include "hbclass.ch"
#include "models/hpassword.prg"
#include "models/tdalmysql.prg"

// Parse ROLES string into hash matching the CRUD example's format
// Input:  "customers:search;show|users:search"
// Output: { "customers" => "search;show", "users" => "search" }
STATIC FUNCTION _ParseRoles( cRolesStr )
   LOCAL hRoles := hb_Hash()
   LOCAL aParts, aPairs, nI, cRole, cOps

   IF Empty( cRolesStr )
      RETURN hRoles
   ENDIF

   // Trim trailing padding before parsing
   cRolesStr := ALLTRIM( cRolesStr )

   // Split on "|" to get individual role:ops pairs
   // Format: "role1:op1;op2;op3|role2:op1;op2" (pipe separates role pairs)
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

//  The columns the login needs. `pass` and `salt` are in here because
//  verifying a digest needs them - and they stop at this function: the
//  session entry is built field by field below, never from the row.
#DEFINE LOGIN_COLS  { "name", "pass", "salt", "roles" }

FUNCTION ModelUser( cUser, cPass )
   LOCAL hRow, hEntry, hRoles
   LOCAL cSeek, cFound, cStored, cSalt
   LOCAL oConn, oDal, aRows

   // D-16: the submitted name is normalised once and reused for the seek and
   // for the exact-match confirmation below.
   cSeek := Lower( AllTrim( cUser ) )

   //  one slot per login (P3.4). Absent the pool there is no store to
   //  check, and the answer must not be distinguishable from a wrong
   //  password - so the work factor is paid and NIL is returned.
   oConn := WDO_Get( "mysql" )
   IF oConn == NIL
      _PwHash( cPass, PW_DUMMY_SALT )
      RETURN NIL
   ENDIF

   oDal := TDalMySql():New( "users_users", LOGIN_COLS )
   oDal:Attach( oConn )

   //  the name is bound, never concatenated (P3.2); the collation makes the
   //  equality case-insensitive, which is what the CDX tag on Lower(NAME)
   //  used to do
   aRows := oDal:FetchAll( { "name" => cSeek }, NIL )

   oDal:Close()
   //  ModelUser owns the slot: the DAL only borrowed it (Attach), so the
   //  connection is returned here, once, before anything is answered
   oConn:Close()

   IF EMPTY( aRows )
      // D-17 (PENTEST-REPORT.md §6): pay the full work factor even when the
      // name does not exist. Skipping it made an unknown username ~4 ms
      // cheaper than a real one, which is a user-enumeration oracle even
      // though the error message is generic.
      _PwHash( cPass, PW_DUMMY_SALT )
      RETURN NIL
   ENDIF

   //  a collated equality can answer for a longer key, so the match is
   //  confirmed here - the same confirmation the DBF path needed because
   //  SET EXACT is .F. in www/config.json
   hRow   := aRows[ 1 ]
   cFound := AllTrim( hb_HGetDef( hRow, "name", "" ) )

   IF Lower( cFound ) != cSeek
      _PwHash( cPass, PW_DUMMY_SALT )
      RETURN NIL
   ENDIF

   // Read the stored digest + salt before anything is exposed (D-07)
   cStored := AllTrim( hb_HGetDef( hRow, "pass", "" ) )
   cSalt   := AllTrim( hb_HGetDef( hRow, "salt", "" ) )

   // D-07: the store holds an iterated, salted SHA-256 digest, never the
   // password.  Re-hash the submitted password with the stored salt.
   IF ! _PwMatch( cStored, _PwHash( cPass, cSalt ) )
      RETURN NIL
   ENDIF

   // Build the session entry WITHOUT credentials (D-05): the session hash is
   // readable from every authenticated view and middleware.
   hEntry := hb_Hash()
   hEntry[ "id" ]    := hb_HGetDef( hRow, "id", 0 )
   hEntry[ "name" ]  := cFound

   // Parse ROLES string into hash matching CRUD example format
   // ROLES format: "role:op1;op2;op3|role2:op1;op2"
   hEntry[ "roles" ] := _ParseRoles( hb_HGetDef( hRow, "roles", "" ) )

RETURN hEntry
