/*-----------------------------------------------------------
  File ......: create_mysql_sql.prg
  Author.....: Charles 9000
  Created....: 2026-10-07
  Modified...: 2026-10-07
  Version....: 1.0.0
  Description: P1.5 of INVENTREE-MYSQL-PLAN.md - load the shipped
               schema (sql/inventree.sql) into the MariaDB host P0
               started, and report per statement.

               A CLI tool in the project folder, the pattern the
               corpus already uses (create_dbf_ntx.prg, migrate_
               users.prg). WDO_MySql():New() is legitimate here and
               not in a handler: site-docs/en/wdo/mysql/index.md,
               "When to use New() directly".

               Deviation from the plan, recorded: P1.5 says feed each
               statement to oConn:Exec(). Exec() raises a DynCall
               "Argument error" for the account statements (P0-MYSQL-
               HOST-RESULTS-2026-10-07.md section 3), so every call
               here goes through Query() + FetchAll(.F.) + Free(),
               which P0 proved. Same TRY/CATCH/FINALLY discipline:
               an uncaught Harbour error opens the interactive "Quit"
               dialog and hangs a non-interactive run.

  Usage      : ./create_mysql_sql [load|recreate|verify]
               load      create the tables (default)
               recreate  drop the tables the file names, then create
               verify    SELECT COUNT(*) and SHOW INDEX per table, no writes
               Defaults: 127.0.0.1:3306  inventree  harbour
               Password: MYSQL_PWD (see .mysql/credentials, 0600)
 -----------------------------------------------------------*/

//  hix_const.ch is what gives Harbour 3.x TRY / CATCH / FINALLY:
//  they are #xcommand macros there (src/include/hix_const.ch:13-16),
//  not built-ins. Without this header the compiler rejects TRY.
#include "hix_const.ch"

#DEFINE SCHEMA_SQL  "sql/inventree.sql"

FUNCTION Main( cModeArg )

   LOCAL oErr := NIL, nRc := 1

   //  Nothing here may reach Harbour's interactive "Quit" dialog: a
   //  non-interactive run would hang (P0-MYSQL-HOST-RESULTS section 3).
   TRY
      nRc := _Main( cModeArg )
   CATCH oErr
      ? "create_mysql_sql: uncaught -", oErr:description
      nRc := 1
   END

RETURN nRc

STATIC FUNCTION _Main( cModeArg )

   LOCAL cMode := "load"
   LOCAL cHost := "127.0.0.1", cDb := "inventree", cUser := "harbour"
   LOCAL nPort := 3306
   LOCAL cDll, cPwd, oConn, aStmts, aTables, cText, nRc := 0, oErr

   ? "create_mysql_sql - P1.5 loader"

   //  Harbour passes each command-line argument as its own parameter,
   //  not as an array: Main( cModeArg ) receives "load". (LEN() of it
   //  returned 4 and aArg[ 1 ] raised "Argument error: array access" -
   //  the same class of surprise as P0's hb_MemoWrite / Q() / FPutS.)
   IF ! EMPTY( cModeArg )
      cMode := LOWER( cModeArg )
   ENDIF

   ? "  mode    :", cMode

   IF ! ( cMode == "load" .OR. cMode == "recreate" .OR. cMode == "verify" )
      ? "create_mysql_sql: unknown mode", cModeArg
      RETURN 2
   ENDIF

   cDll := _LibPath()
   IF cDll == NIL
      ? "FAIL: no MySQL/MariaDB client library under /usr/lib"
      RETURN 1
   ENDIF

   cPwd := hb_GetEnv( "MYSQL_PWD" )
   IF EMPTY( cPwd )
      ? "FAIL: MYSQL_PWD not set - read it from .mysql/credentials"
      RETURN 1
   ENDIF

   IF ! hb_FileExists( SCHEMA_SQL )
      ? "FAIL:", SCHEMA_SQL, "not found - run it from webapp/"
      RETURN 1
   ENDIF

   cText := hb_MemoRead( SCHEMA_SQL )
   IF cText == NIL
      ? "FAIL:", SCHEMA_SQL, "read back NIL"
      RETURN 1
   ENDIF
   ? "  bytes   :", LEN( cText )
   aStmts  := _SplitStmts( cText )
   aTables := _TableNames( aStmts )

   ? "  host    :", cHost, nPort
   ? "  library :", cDll
   ? "  schema  :", SCHEMA_SQL
   ? "  tables  :", LEN( aTables ), "(expected 38)"
   ? "  stmts   :", LEN( aStmts )

   IF EMPTY( aStmts ) .OR. LEN( aTables ) != 38
      ? "FAIL: the schema does not yield 38 CREATE TABLE statements"
      RETURN 1
   ENDIF

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
   ? "  P0.2    :", oConn:DllSource(), oConn:DllPath()

   IF cMode == "recreate"
      nRc += _DropAll( oConn, aTables )
   ENDIF

   IF cMode != "verify"
      nRc += _LoadAll( oConn, aStmts )
   ENDIF

   nRc += _Verify( oConn, aTables )

   oConn:Close()

   IF nRc > 0
      ? "RESULT :", nRc, "problem(s)"
      RETURN 1
   ENDIF

   ? "RESULT : ok"
RETU 0

// ---------------------------------------------------------- //
//  Client library: same pin as probe_mysql / gen_mysql_db.sh.
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
//  Strip comments, split on ';'.
//
//  A naive split is wrong here: the shipped file carries "-- DECISION
//  ..." lines inside the CREATE TABLE bodies, /* FK -> ... */ block
//  comments, back-quoted identifiers, and the DEFAULT '' literals the
//  P1.1 policy adds. The scanner knows all of it.
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
//  Table names, from the CREATE TABLE statements only.
// ---------------------------------------------------------- //

STATIC FUNCTION _TableNames( aStmts )

   LOCAL aOut := {}, i, cRest, nPos

   FOR i := 1 TO LEN( aStmts )
      IF SUBSTR( UPPER( aStmts[i] ), 1, 12 ) == "CREATE TABLE"
         nPos  := _PosIn( aStmts[i], CHR( 96 ) )
         IF nPos > 0
            cRest := SUBSTR( aStmts[i], nPos + 1 )
            nPos  := _PosIn( cRest, CHR( 96 ) )
            IF nPos > 0
               AADD( aOut, SUBSTR( cRest, 1, nPos - 1 ) )
            ENDIF
         ENDIF
      ENDIF
   NEXT

RETU aOut

// ---------------------------------------------------------- //
//  Substring position. Harbour's RTL on this build has no POS(),
//  and hb_Pos() is not either - the same class of surprise P0 hit
//  with hb_MemoWrite / Q() / FPutS. Own helper, no dependency.
// ---------------------------------------------------------- //

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
//  One statement. "" = it ran; anything else is the server's words
//  for why it did not. Query(), not Exec() - see the header.
//  oStmt:Free() in FINALLY: prepared.md's danger box.
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
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
   END

RETU cErr

// ---------------------------------------------------------- //
//  recreate: drop only what the file names. The database itself is
//  never dropped - it also holds MariaDB's own tables (P0 record:
//  test, performance_schema, sys).
// ---------------------------------------------------------- //

STATIC FUNCTION _DropAll( oConn, aTables )

   LOCAL i, cErr, nBad := 0

   FOR i := 1 TO LEN( aTables )
      cErr := _Sql( oConn, "DROP TABLE " + CHR( 96 ) + aTables[i] + CHR( 96 ) )
      IF ! EMPTY( cErr ) .AND. ! _IsAbsent( cErr )
         ? "  !! drop", aTables[i], ":", cErr
         nBad++
      ENDIF
   NEXT

RETU nBad

STATIC FUNCTION _IsAbsent( cErr )

   LOCAL cL := UPPER( cErr )

RETU _PosIn( cL, "NOT FOUND" ) > 0 .OR. _PosIn( cL, "DOES NOT EXIST" ) > 0

// ---------------------------------------------------------- //
//  Load: one CREATE TABLE per statement, errors named per statement.
// ---------------------------------------------------------- //

STATIC FUNCTION _LoadAll( oConn, aStmts )

   LOCAL i, cErr, nBad := 0

   FOR i := 1 TO LEN( aStmts )
      cErr := _Sql( oConn, aStmts[i] )
      IF ! EMPTY( cErr )
         ? "  !! statement", i, ":", cErr
         nBad++
      ENDIF
   NEXT

   IF nBad == 0
      ? "  loaded  :", LEN( aStmts ), "statements, 0 errors"
   ENDIF

RETU nBad

// ---------------------------------------------------------- //
//  Verify: P1.5's "SELECT COUNT(*) = 0 per table" and P1.4's
//  "SHOW INDEX per table", read back from the server.
// ---------------------------------------------------------- //

STATIC FUNCTION _Verify( oConn, aTables )

   LOCAL i, aRows, oStmt, cErr, nBad := 0, nIdx, nCol, j, oErr

   FOR i := 1 TO LEN( aTables )
      oStmt := NIL
      aRows := NIL
      cErr  := ""
      TRY
         oStmt := oConn:Query( "SELECT COUNT(*) FROM " + CHR( 96 ) + ;
            aTables[i] + CHR( 96 ) )
         aRows := oStmt:FetchAll( .F. )
         IF oStmt:lError
            cErr := oStmt:cError
         ENDIF
      CATCH oErr
         cErr := oErr:description
      END
      IF oStmt != NIL ; oStmt:Free() ; ENDIF

      IF EMPTY( aRows )
         IF EMPTY( cErr )
            cErr := "no row back"
         ENDIF
         ? "  !! count", aTables[i], ":", cErr
         nBad++
      ELSE
         ? "  count", aTables[i], "=", aRows[ 1 ][ 1 ]
      ENDIF

      //  P1.4's "verify by" row says SHOW INDEX. This MariaDB build
      //  rejects SHOW INDEX / SHOW KEY / SHOW KEY STATISTICS / SHOW
      //  COLUMNS through the driver; DESCRIBE is the form that parses,
      //  and its 4th field is the key flag (PRI / UNI / MUL). Counted
      //  here as keyed columns, which is what P1.4 actually adds.
      oStmt := NIL
      aRows := NIL
      cErr  := ""
      TRY
         oStmt := oConn:Query( "DESCRIBE " + aTables[i] )
         aRows := oStmt:FetchAll( .F. )
         IF oStmt:lError
            cErr := oStmt:cError
         ENDIF
      CATCH oErr
         cErr := oErr:description
      END
      IF oStmt != NIL ; oStmt:Free() ; ENDIF

      IF EMPTY( cErr )
         nCol := LEN( aRows )
         nIdx := 0
         FOR j := 1 TO nCol
            IF ! EMPTY( aRows[ j ][ 4 ] )
               nIdx++
            ENDIF
         NEXT
         ? "  index", aTables[i], "=", nIdx, "keyed of", nCol, "cols"
      ELSE
         ? "  !! index", aTables[i], ":", cErr
         nBad++
      ENDIF
   NEXT

RETU nBad
