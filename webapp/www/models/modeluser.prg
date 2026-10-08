/* ---------------------------------------------------------
 File.......: modeluser.prg
 Description: The login identity, read from the RDDCDX credential
              store (data/users.dbf, www/models/tusers.prg).

              What is preserved from the audited module, and how it
              is done now:

                D-05  the session entry carries NO credentials - id,
                      name, roles only. The session hash is readable
                      from every authenticated view and middleware, so
                      the digest and the salt stop at this function:
                      the entry is built field by field below, never
                      copied from the row.
                D-07  the store holds a salted, iterated SHA-256
                      digest, never the password. The submitted
                      password is re-hashed with the STORED salt and
                      compared with _PwMatch, so a wrong password and
                      a wrong salt both fail the same way.
                D-16  the submitted name is normalised once and reused
                      for the seek and for the exact-match confirmation
                      below. The CDX tag keyed on Lower(NAME) is what
                      makes the lookup case-insensitive by construction;
                      the confirmation is what a PREFIX key can still
                      get wrong - CDX is prefix-key only, so a longer
                      name would match a shorter key.
                D-17  the full work factor is paid even when the name
                      does not exist, so response time is not a
                      user-enumeration oracle. The error message is
                      generic; the timing is the only other channel.
                +     ROLES is parsed into a hash - the middlewares
                      read scopes from it.

              One store per login: opened here and closed here, on
              every path. hix.json's auto_close_dbf logs a handle this
              function forgot rather than leaking it.

              Complies with DEV-compliance.md: HIX framework and Harbour
              only. No SQL, no engine - the store is a DBF.
 -----------------------------------------------------------*/

#include "hbclass.ch"
#include "models/hpassword.prg"
#include "models/tusers.prg"

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
         IF !Empty( cRole ) .AND. !Empty( cOps )
            hRoles[ cRole ] := cOps
         ENDIF
      ENDIF
   NEXT

RETURN hRoles

FUNCTION ModelUser( cUser, cPass )
   LOCAL hRow, hEntry, hRoles
   LOCAL cSeek, cFound, cStored, cSalt
   LOCAL oUsers, lFound

   // D-16: the submitted name is normalised once and reused for the seek
   // and for the exact-match confirmation below.
   cSeek := Lower( AllTrim( cUser ) )

   //  one store per login. Absent the store there is nothing to check, and
   //  the answer must not be distinguishable from a wrong password - so the
   //  work factor is paid and NIL is returned.
   oUsers := TUsers()
   IF ! oUsers:lConnect
      _PwHash( cPass, PW_DUMMY_SALT )
      RETURN NIL
   ENDIF

   //  the seek lands on the CDX tag keyed on Lower(NAME): that is what makes
   //  the match case-insensitive by construction, and it is a prefix key, so
   //  the confirmation below is what closes the prefix
   lFound := oUsers:GetId( cSeek, @hRow, NIL, .F. )

   IF ! lFound
      // D-17 (PENTEST-REPORT.md §6): pay the full work factor even when the
      // name does not exist. Skipping it made an unknown username ~4 ms
      // cheaper than a real one, which is a user-enumeration oracle even
      // though the error message is generic.
      _PwHash( cPass, PW_DUMMY_SALT )
      oUsers:Close()
      RETURN NIL
   ENDIF

   //  a prefix key answers for a longer name too, so the match is confirmed
   //  here. The confirmation must NOT use = or !=: www/config.json sets
   //  "exact": false, and with SET EXACT OFF Harbour compares strings only to
   //  the length of the RIGHT operand - so "carlesx" != "carle" is FALSE, which
   //  would let a PREFIX of a username authenticate. That is a real security
   //  defect (D-16), not a style choice. Len() closes the prefix; the
   //  case-insensitive compare then does the rest.
   cFound := AllTrim( hb_HGetDef( hRow, "NAME", "" ) )

   IF Len( cFound ) != Len( cSeek ) .OR. Upper( cFound ) <> Upper( cSeek )
      _PwHash( cPass, PW_DUMMY_SALT )
      oUsers:Close()
      RETURN NIL
   ENDIF

   // Read the stored digest + salt before anything is exposed (D-07)
   cStored := AllTrim( hb_HGetDef( hRow, "PASS", "" ) )
   cSalt   := AllTrim( hb_HGetDef( hRow, "SALT", "" ) )

   // D-07: the store holds an iterated, salted SHA-256 digest, never the
   // password. Re-hash the submitted password with the stored salt.
   IF ! _PwMatch( cStored, _PwHash( cPass, cSalt ) )
      oUsers:Close()
      RETURN NIL
   ENDIF

   oUsers:Close()

   // Build the session entry WITHOUT credentials (D-05): the session hash is
   // readable from every authenticated view and middleware, so the digest and
   // the salt never leave this function.
   hEntry := hb_Hash()
   hEntry[ "id" ]    := hb_HGetDef( hRow, "ID", 0 )
   hEntry[ "name" ]  := cFound

   // Parse ROLES string into hash matching CRUD example format
   // ROLES format: "role:op1;op2;op3|role2:op1;op2"
   hEntry[ "roles" ] := _ParseRoles( hb_HGetDef( hRow, "ROLES", "" ) )

RETURN hEntry
