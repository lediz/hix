/*-----------------------------------------------------------
  File ......: seed_users_mysql.prg
  Author.....: Charles 9000
  Created....: 2026-10-07
  Version....: 1.0.0
  Description: P4.8 of INVENTREE-MYSQL-PLAN.md (Step 0.2, Option A for
               `users`): the credential store the login path reads.

               The artefact's auth_user was dropped by P1.2a because
               HIX owns users, roles and scopes - so the table that
               carries the login identity is HIX's, and it lives in
               sql/hix_users.sql rather than in the InvenTree schema
               file, which stays byte-faithful to the artefact.

               Same CLI pattern as create_mysql_sql.prg / seed_inventree
               .prg: WDO_MySql():New() is legitimate in a tool and not
               in a handler (site-docs/en/wdo/mysql/index.md, "When to
               use New() directly").

               Passwords are hashed at run time by www/models/hpassword
               .prg, so no digest and no salt is ever committed: this is
               why there is no sql/fixtures/users_users.csv like the
               inventory corpus has.

  Usage      : ./seed_users_mysql [create|seed|verify|check|dump]
               create   load sql/hix_users.sql (idempotent)
               seed     replace the seed accounts (default: create+seed+verify)
               verify   the accounts are there, digests and salts are the
                        right shape
               check    no plaintext seed password anywhere in the store (D-07)
               dump     id | name | roles, never pass or salt
               Defaults: 127.0.0.1:3306  inventree  harbour
               Password: MYSQL_PWD (see .mysql/credentials, 0600)
 -----------------------------------------------------------*/

#include "hix_const.ch"

#DEFINE USERS_SQL    "sql/hix_users.sql"
#DEFINE USERS_TABLE  "users_users"

//  The seed accounts, the same five regenerate_users.prg used for the
//  DBF store: "John" is mixed-case on purpose (D-16, the name is typed
//  differently from how it is stored) and jane's password is longer than
//  four characters (the prefix-login probe).
STATIC aName := { "admin", "carles", "maria", "John", "jane" }
STATIC aPass := { "1234", "1234", "1234", "5678", "9012abcd" }
STATIC aRole := { "customers:search;show;edit;delete;recall;create|users:search;show;edit;delete;create|parts:search;show;create;edit;delete|sys:fkcheck|bom:search;show;create;edit;delete|build:search;show;create;edit;delete|company:search;show;create;edit;delete|note:search;show;create;edit;delete|order:search;show;create;edit;delete|project:search;show;create;edit;delete|stock:search;show;create;edit;delete|supplier:search;show;create;edit;delete|test:search;show;create;edit;delete", "customers:search;show", "customers:search;show;edit", "customers:search;show", "customers:search;show;edit" }

//  hpassword.prg brings in functions, and a file-level STATIC may not
//  follow them - so the include sits below the seed data, not above it
//  (regenerate_users.prg keeps its seed lists inside a function, which
//  is the other way round).
#include "models/hpassword.prg"

FUNCTION Main( cModeArg )

   LOCAL oErr := NIL, nRc := 1

   //  Nothing here may reach Harbour's interactive "Quit" dialog: a
   //  non-interactive run would hang (P0-MYSQL-HOST-RESULTS section 3).
   TRY
      nRc := _Main( cModeArg )
   CATCH oErr
      ? "seed_users_mysql: uncaught -", oErr:description
      nRc := 1
   END

RETURN nRc

STATIC FUNCTION _Main( cModeArg )

   LOCAL cMode := "seed"
   LOCAL cHost := "127.0.0.1", cDb := "inventree", cUser := "harbour"
   LOCAL nPort := 3306
   LOCAL cDll, cPwd, oConn := NIL, oErr := NIL
   LOCAL nRc := 0

   IF ! EMPTY( cModeArg )
      cMode := LOWER( cModeArg )
   ENDIF

   IF ! ( cMode == "create" .OR. cMode == "seed" .OR. cMode == "verify" ;
          .OR. cMode == "check" .OR. cMode == "dump" .OR. cMode == "drop" )
      ? "seed_users_mysql: unknown mode", cModeArg
      RETURN 2
   ENDIF

   cDll := _LibPath()
   IF cDll == NIL
      ? "FAIL: no MySQL/MariaDB client library under /usr/lib"
      RETURN 1
   ENDIF

   cPwd := hb_getEnv( "MYSQL_PWD" )
   IF EMPTY( cPwd )
      ? "FAIL: MYSQL_PWD not set - read it from .mysql/credentials"
      RETURN 1
   ENDIF

   IF ! hb_FileExists( USERS_SQL )
      ? "FAIL:", USERS_SQL, "not found - run it from webapp/"
      RETURN 1
   ENDIF

   ? "seed_users_mysql - P4.8 credential store"
   ? "  mode    :", cMode
   ? "  host    :", cHost, nPort
   ? "  library :", cDll
   ? "  schema  :", USERS_SQL

   oConn := NIL
   TRY
      oConn := WDO_MySql():New( cHost, cUser, cPwd, cDb, nPort, .T., cDll, "MYSQL" )
   CATCH oErr
      ? "FAIL: connection refused -", oErr:description
      RETURN 1
   END

   IF oConn == NIL
      ? "FAIL: no connection"
      RETURN 1
   ENDIF

   oConn:nConnectTimeout := 10
   oConn:nReadTimeout    := 60

   ? "  server  :", oConn:ServerInfo()

   IF cMode == "create" .OR. cMode == "seed" .OR. cMode == "drop"
      nRc += _EnsureTable( oConn )
   ENDIF

   DO CASE
   CASE cMode == "drop"
      nRc += _Drop( oConn )
      nRc += _Verify( oConn )
   CASE cMode == "seed"
      nRc += _Seed( oConn )
      nRc += _Verify( oConn )
   CASE cMode == "create"
      nRc += _Verify( oConn )
   CASE cMode == "verify"
      nRc += _Verify( oConn )
   CASE cMode == "check"
      nRc += _Check( oConn )
   CASE cMode == "dump"
      _Dump( oConn )
   ENDCASE

   oConn:Close()

   IF nRc > 0
      ? "RESULT :", nRc, "problem(s)"
      RETURN 1
   ENDIF

   ? "RESULT : ok"
RETURN 0

// ---------------------------------------------------------- //
//  Client library: same pin as probe_mysql / create_mysql_sql.
// ---------------------------------------------------------- //

STATIC FUNCTION _LibPath()

   LOCAL aTry := { "/usr/lib/libmysqlclient.so", ;
                   "/usr/lib/libmariadb.so",     ;
                   "/usr/lib/libmariadb.so.3" }
   LOCAL i

   FOR i := 1 TO LEN( aTry )
      IF hb_FileExists( aTry[i] )
         RETU aTry[i]
      ENDIF
   NEXT

RETU NIL

// ---------------------------------------------------------- //
//  One statement, no parameters. "" = it ran; anything else is the
//  server's words for why it did not. Query(), not Exec() - the
//  driver raises a DynCall "Argument error" for Exec() here (P0
//  record, section 3).
// ---------------------------------------------------------- //

STATIC FUNCTION _Sql( oConn, cSql )

   LOCAL oStmt := NIL
   LOCAL aRows := NIL
   LOCAL cErr := ""
   LOCAL oErr := NIL

   TRY
      oStmt := oConn:Query( cSql )
      aRows := oStmt:FetchAll( .F. )
      IF oStmt:lError
         cErr := oStmt:cError
      ENDIF
   CATCH oErr
      cErr := oErr:description
   FINALLY
      //  prepared.md's danger box: freed on every path
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
   END

RETU cErr

// ---------------------------------------------------------- //
//  One statement WITH parameters. Every value is bound, never
//  concatenated (P3.2) - a name typed into a form is external input.
//  Returns { rows, error }; the rows are read while the statement is
//  still alive and it is freed before returning.
// ---------------------------------------------------------- //

STATIC FUNCTION _Run( oConn, cSql, aVals )

   LOCAL oStmt := NIL
   LOCAL aRows := NIL
   LOCAL cErr := ""
   LOCAL oErr := NIL
   LOCAL nI

   TRY
      oStmt := oConn:Prepare( cSql )

      IF ValType( aVals ) == 'A'
         FOR nI := 1 TO LEN( aVals )
            oStmt:BindParam( nI, aVals[ nI ][ 1 ], aVals[ nI ][ 2 ] )
         NEXT
      ENDIF

      IF ! oStmt:Execute()
         cErr := oStmt:cError
      ELSE
         aRows := oStmt:FetchAll( .T. )
      ENDIF
   CATCH oErr
      cErr := oErr:description
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
   END

RETU { aRows, cErr }

// ---------------------------------------------------------- //
//  The table. Loading the file twice is not an error: MariaDB answers
//  that the name is taken, and that is the state we want, so the
//  answer is checked rather than the file being skipped.
// ---------------------------------------------------------- //

STATIC FUNCTION _EnsureTable( oConn )

   LOCAL aStmt, cErr, nI, nBad := 0

   aStmt := _SplitStmts( hb_MemoRead( USERS_SQL ) )
   IF EMPTY( aStmt )
      ? "FAIL:", USERS_SQL, "yields no statement"
      RETURN 1
   ENDIF

   FOR nI := 1 TO LEN( aStmt )
      cErr := _Sql( oConn, aStmt[ nI ] )
      IF EMPTY( cErr )
         ? "  created", USERS_TABLE, "(statement", nI, "of", LEN( aStmt ), ")"
      ELSEIF _IsThere( cErr )
         ? "  the table is there already (statement", nI, ")"
      ELSE
         ? "  !! statement", nI, ":", cErr
         nBad++
      ENDIF
   NEXT

RETU nBad

STATIC FUNCTION _IsThere( cErr )

   LOCAL cL := UPPER( cErr )

RETU _PosIn( cL, "ALREADY EXISTS" ) > 0 .OR. _PosIn( cL, "ALREADY DEFINED" ) > 0

STATIC FUNCTION _PosIn( cHay, cNeedle )

   LOCAL nLen := LEN( cNeedle ), i

   IF EMPTY( cNeedle )
      RETU 0
   ENDIF

   FOR i := 1 TO LEN( cHay ) - nLen + 1
      IF SUBSTR( cHay, i, nLen ) == cNeedle
         RETU i
      ENDIF
   NEXT

RETU 0

// ---------------------------------------------------------- //
//  Statement splitter, the one create_mysql_sql.prg uses: line and
//  block comments out, quoted identifiers kept verbatim, split on
//  ";". The schema file is source, so it is read the same way the
//  inventory schema is read.
// ---------------------------------------------------------- //

STATIC FUNCTION _SplitStmts( cText )

   LOCAL aOut := {}, cCur := ""
   LOCAL n := LEN( cText ), i := 1, c, c2, j

   WHILE i <= n
      c  := SUBSTR( cText, i, 1 )
      c2 := SUBSTR( cText, i + 1, 1 )

      //  line comment: to end of line
      IF c == "-" .AND. c2 == "-"
         j := i
         WHILE j <= n .AND. SUBSTR( cText, j, 1 ) != CHR( 10 )
            j++
         END
         i := j
         LOOP
      ENDIF

      //  block comment: to */
      IF c == "/" .AND. c2 == "*"
         j := i + 2
         WHILE j + 1 <= n
            IF SUBSTR( cText, j, 1 ) == "*" .AND. SUBSTR( cText, j + 1, 1 ) == "/"
               j += 2
               EXIT
            ENDIF
            j++
         END
         i := j
         LOOP
      ENDIF

      //  quoted identifier or literal: copied verbatim, delimiters inside
      IF c == CHR( 96 ) .OR. c == "'" .OR. c == '"'
         j := i + 1
         WHILE j <= n
            IF SUBSTR( cText, j, 1 ) == CHR( 92 ) .AND. c != CHR( 96 )
               j += 2
               LOOP
            ENDIF
            IF SUBSTR( cText, j, 1 ) == c
               EXIT
            ENDIF
            j++
         END
         IF j > n ; j := n ; ENDIF
         cCur += SUBSTR( cText, i, j - i + 1 )
         i := j + 1
         LOOP
      ENDIF

      IF c == ";"
         cCur := ALLTRIM( cCur )
         IF ! EMPTY( cCur )
            AADD( aOut, cCur )
         ENDIF
         cCur := ""
         i++
         LOOP
      ENDIF

      cCur += c
      i++
   END

   cCur := ALLTRIM( cCur )
   IF ! EMPTY( cCur )
      AADD( aOut, cCur )
   ENDIF

RETU aOut

// ---------------------------------------------------------- //
//  Seed. Idempotent: the account is deleted by name and rewritten, so
//  a repeated run leaves five accounts and not ten. The name is bound,
//  never concatenated (P3.2).
// ---------------------------------------------------------- //

STATIC FUNCTION _Seed( oConn )

   LOCAL nI, cSalt, aRes, aBind, nBad := 0

   FOR nI := 1 TO LEN( aName )

      aRes := _Run( oConn, "DELETE FROM " + CHR( 96 ) + USERS_TABLE + CHR( 96 ) + ;
                    " WHERE name = ?", { { aName[ nI ], "s" } } )
      IF ! EMPTY( aRes[ 2 ] )
         ? "  !! delete", aName[ nI ], ":", aRes[ 2 ]
         nBad++
      ENDIF

      cSalt   := _PwSalt()
      aBind   := { { aName[ nI ], "s" }, ;
                   { _PwHash( aPass[ nI ], cSalt ), "s" }, ;
                   { cSalt, "s" }, ;
                   { aRole[ nI ], "s" } }

      aRes := _Run( oConn, "INSERT INTO " + CHR( 96 ) + USERS_TABLE + CHR( 96 ) + ;
                    " ( name, pass, salt, roles ) VALUES ( ?, ?, ?, ? )", ;
                    aBind )
      IF ! EMPTY( aRes[ 2 ] )
         ? "  !! seed", aName[ nI ], ":", aRes[ 2 ]
         nBad++
      ELSE
         ? "  seeded", aName[ nI ]
      ENDIF
   NEXT

RETU nBad

// ---------------------------------------------------------- //
//  Drop what the seed does not know. A functional suite creates and
//  deletes its own account, but a run that stops half way leaves one
//  behind, and "the store is at its seeded base" is only meaningful
//  after the leftovers are gone. The seed names are bound, never
//  concatenated (P3.2).
// ---------------------------------------------------------- //

STATIC FUNCTION _Drop( oConn )

   LOCAL aRes, cSql, cIn := "", nI, nBad := 0

   //  the placeholders and the bound values must be in the same order
   FOR nI := 1 TO LEN( aName )
      IF nI > 1
         cIn += ", "
      ENDIF
      cIn += "?"
   NEXT

   cSql := "DELETE FROM " + CHR( 96 ) + USERS_TABLE + CHR( 96 ) + ;
          " WHERE name NOT IN ( " + cIn + " )"

   aRes := _Run( oConn, cSql, _SeedBinds() )
   IF ! EMPTY( aRes[ 2 ] )
      ? "  !! drop:", aRes[ 2 ]
      nBad++
   ENDIF

RETU nBad

STATIC FUNCTION _SeedBinds()

   LOCAL aOut := {}, nI

   FOR nI := 1 TO LEN( aName )
      AADD( aOut, { aName[ nI ], "s" } )
   NEXT

RETU aOut

// ---------------------------------------------------------- //
//  Verify: the accounts are there AND the digests and salts are the
//  shape hpassword.prg says they are. A count alone would pass on a
//  store of plaintext passwords, which is what B1 warns about.
// ---------------------------------------------------------- //

STATIC FUNCTION _Verify( oConn )

   LOCAL nI, aRes, aRows, nBad := 0, nGot, cPass, cSalt

   aRes  := _Run( oConn, "SELECT COUNT(*) FROM " + CHR( 96 ) + USERS_TABLE + ;
                  CHR( 96 ), NIL )
   aRows := aRes[ 1 ]
   IF EMPTY( aRows )
      ? "  !! count", USERS_TABLE, ":", iif( EMPTY( aRes[ 2 ] ), "no row back", aRes[ 2 ] )
      RETURN 1
   ENDIF

   nGot := _FirstNum( aRows[ 1 ] )
   IF nGot != LEN( aName )
      ? "  !! count", USERS_TABLE, "=", nGot, "expected", LEN( aName )
      nBad++
   ELSE
      ? "  count", USERS_TABLE, "=", nGot
   ENDIF

   FOR nI := 1 TO LEN( aName )
      aRes := _Run( oConn, "SELECT name, pass, salt FROM " + CHR( 96 ) + ;
                    USERS_TABLE + CHR( 96 ) + " WHERE name = ?", ;
                    { { aName[ nI ], "s" } } )
      aRows := aRes[ 1 ]
      IF EMPTY( aRows )
         ? "  !! account", aName[ nI ], ": absent (", aRes[ 2 ], ")"
         nBad++
      ELSE
         cPass := hb_HGetDef( aRows[ 1 ], "pass", "" )
         cSalt := hb_HGetDef( aRows[ 1 ], "salt", "" )
         IF ValType( cPass ) != "C" .OR. Len( cPass ) != 64
            ? "  !! digest of", aName[ nI ], "is not 64 hex (", ;
              ValType( cPass ), Len( cPass ), ")"
            nBad++
         ENDIF
         IF ValType( cSalt ) != "C" .OR. Len( cSalt ) != 32
            ? "  !! salt of", aName[ nI ], "is not 32 (", ;
              ValType( cSalt ), Len( cSalt ), ")"
            nBad++
         ENDIF
      ENDIF
   NEXT

RETU nBad

// ---------------------------------------------------------- //
//  D-07 over the new store: the password must not appear in the clear
//  anywhere in pass or salt.
// ---------------------------------------------------------- //

STATIC FUNCTION _Check( oConn )

   LOCAL aRes, aRows, nI, nJ, nBad := 0, cPass, cSalt, cWant

   aRes  := _Run( oConn, "SELECT name, pass, salt FROM " + CHR( 96 ) + ;
                  USERS_TABLE + CHR( 96 ) + " ORDER BY id", NIL )
   aRows := aRes[ 1 ]
   IF EMPTY( aRows )
      ? "  !! no rows to check (", aRes[ 2 ], ")"
      RETURN 1
   ENDIF

   FOR nI := 1 TO LEN( aRows )
      cPass := _Text( hb_HGetDef( aRows[ nI ], "pass", "" ) )
      cSalt := _Text( hb_HGetDef( aRows[ nI ], "salt", "" ) )
      FOR nJ := 1 TO LEN( aPass )
         cWant := aPass[ nJ ]
         IF _PosIn( cPass, cWant ) > 0 .OR. _PosIn( cSalt, cWant ) > 0 ;
          .OR. _PosIn( Upper( cPass ), Upper( cWant ) ) > 0 ;
          .OR. _PosIn( Upper( cSalt ), Upper( cWant ) ) > 0
            ? "  !! plaintext password in the store:", hb_HGetDef( aRows[ nI ], "name", "?" )
            nBad++
            EXIT
         ENDIF
      NEXT
   NEXT

   ? "  checked", LEN( aRows ), "accounts for a plaintext password"

RETU nBad

STATIC FUNCTION _Text( xVal )

   IF ValType( xVal ) == "C"
      RETU xVal
   ENDIF

RETU ""

//  A SELECT row comes back as a hash keyed by column name (FetchAll(.T.)),
//  and COUNT(*)'s key is the expression itself - so the value is taken by
//  walking the keys, the way the DAL's _DalRowNum does it.
STATIC FUNCTION _FirstNum( hRow )

   LOCAL cKey, xVal := 0

   FOR EACH cKey IN hb_HKeys( hRow )
      xVal := hb_HGetDef( hRow, cKey, 0 )
      EXIT
   NEXT

   IF VALTYPE( xVal ) == "C"
      xVal := VAL( xVal )
   ENDIF

RETU xVal

STATIC FUNCTION _KeyList( hRow )

   LOCAL cKey, cOut := ""

   FOR EACH cKey IN hb_HKeys( hRow )
      IF ! EMPTY( cOut )
         cOut += ","
      ENDIF
      cOut += cKey
   NEXT

RETU cOut

//  What may be printed: the identity and the scopes. pass and salt never
//  leave the terminal, let alone a view.
STATIC FUNCTION _Dump( oConn )

   LOCAL aRes, aRows, nI, cOut := ""

   aRes  := _Run( oConn, "SELECT id, name, roles FROM " + CHR( 96 ) + ;
                  USERS_TABLE + CHR( 96 ) + " ORDER BY id", NIL )
   aRows := aRes[ 1 ]
   IF EMPTY( aRows )
      ? "  (no accounts)", aRes[ 2 ]
      RETURN NIL
   ENDIF

   //  one machine-readable line: the console driver lays the ? output out
   //  with cursor addressing, so anything the suites parse has to be
   //  greppable in a single stream rather than line by line
   FOR nI := 1 TO LEN( aRows )
      IF nI == 1
         //  what the server actually calls the columns - printed once, so a
         //  later change of the SELECT is visible rather than silently empty
         QOut( "keys:" + _KeyList( aRows[ 1 ] ) )
      ENDIF
      cOut += hb_HGetDef( aRows[ nI ], "name", "" )
      IF nI < LEN( aRows )
         cOut += ","
      ENDIF
   NEXT

   //  QOut, not ?: the ? command goes through HIX's console driver, which
  //  lays the line out with cursor addressing and loses characters at the
  //  wrap - a machine-readable line must survive a pipe intact
   QOut( "dump:" + cOut + ":end" )

RETU NIL
