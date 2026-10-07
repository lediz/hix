/*-----------------------------------------------------------
  File ......: seed_inventree.prg
  Author.....: Charles 9000
  Created....: 2026-10-07
  Modified...: 2026-10-07
  Version....: 1.0.0
  Description: P1.6 of INVENTREE-MYSQL-PLAN.md - seed the shipped
               schema with InvenTree's own fixtures, bulk-INSERT
               style: ONE Prepare outside the loop, N Execute
               inside, ONE Free after (site-docs/en/wdo/mysql/
               prepared.md, "Bulk INSERT - reuse the same Prepare"
               and its antipattern table).

               The corpus is InvenTree's own Django fixtures
               (src/backend/InvenTree/<app>/fixtures/*.yaml at the
               same commit the schema artefact was derived from),
               rendered to their CSV equivalent by fixtures_to_csv.py
               into sql/fixtures/<table>.csv. The YAML itself is not
               on this checkout and Harbour does not read it, so the
               CSV is the source that ships; the converter's report
               says which models it dropped and why.

               ids are inserted EXPLICITLY, from the fixtures' pk:
               the fixtures' FK values (category: 8) are pks, so
               letting AUTO_INCREMENT decide would break every
               reference in the corpus. Step 0.3 of the plan says the
               create flow must read Last_Insert_Id(); the seed flow
               must not.

               Tables are visited in the schema file's order, which is
               FK dependency order, not the directory's alphabetical
               order. MySQL/MariaDB enforces no FK here (P1.1), so the
               order is not required for the INSERTs to succeed - it is
               what keeps the FK-orphan check (P7.2) meaningful.

  Usage      : ./seed_inventree [seed|verify]
               seed    INSERT the fixtures (default)
               verify  SELECT COUNT(*) per table vs the CSV row counts
               Defaults: 127.0.0.1:3306  inventree  harbour
               Password: MYSQL_PWD (see .mysql/credentials, 0600)
 -----------------------------------------------------------*/

//  hix_const.ch is what gives Harbour 3.x TRY / CATCH / FINALLY:
//  they are #xcommand macros there (src/include/hix_const.ch:13-16),
//  not built-ins. Without this header the compiler rejects TRY.
#include "hix_const.ch"

#DEFINE SCHEMA_SQL   "sql/inventree.sql"
#DEFINE FIXTURE_DIR  "sql/fixtures"

FUNCTION Main( cModeArg )

   LOCAL cMode := "seed"
   LOCAL cHost := "127.0.0.1", cDb := "inventree", cUser := "harbour"
   LOCAL nPort := 3306
   LOCAL cDll, cPwd, oConn, aTables, nRc := 0, oErr

   IF ! EMPTY( cModeArg )
      cMode := LOWER( cModeArg )
   ENDIF

   IF ! ( cMode == "seed" .OR. cMode == "verify" )
      ? "seed_inventree: unknown mode", cModeArg
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

   //  order comes from the schema, not from the directory
   aTables := _TableNames( _SplitStmts( hb_MemoRead( SCHEMA_SQL ) ) )
   IF LEN( aTables ) != 38
      ? "FAIL:", SCHEMA_SQL, "does not yield 38 tables"
      RETURN 1
   ENDIF

   ? "seed_inventree - P1.6 seeder"
   ? "  mode    :", cMode
   ? "  host    :", cHost, nPort
   ? "  library :", cDll
   ? "  corpus  :", FIXTURE_DIR, " (CSV equivalent of InvenTree's fixtures)"
   ? "  tables  :", LEN( aTables )

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

   IF cMode == "seed"
      nRc += _SeedAll( oConn, aTables )
   ENDIF

   nRc += _Verify( oConn, aTables )

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
//  Strip comments, split on ';'. Same scanner as create_mysql_sql:
//  the shipped file carries -- DECISION lines, /* */ blocks, and
//  back-quoted identifiers. A literal backtick in Harbour source is
//  eaten by the preprocessor (P0 record), hence CHR( 96 ).
// ---------------------------------------------------------- //

STATIC FUNCTION _SplitStmts( cText )

   LOCAL aOut := {}, cCur := ""
   LOCAL n := LEN( cText ), i := 1, c, c2, j

   WHILE i <= n
      c  := SUBSTR( cText, i, 1 )
      c2 := SUBSTR( cText, i + 1, 1 )

      IF c == "-" .AND. c2 == "-"
         j := i
         WHILE j <= n .AND. SUBSTR( cText, j, 1 ) != CHR( 10 )
            j++
         END
         i := j
         LOOP
      ENDIF

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
//  CSV reader. Quoted fields carry commas and doubled quotes -
//  the fixture descriptions do ("M2x4 LPHS, fine thread").
// ---------------------------------------------------------- //

STATIC FUNCTION _CsvRows( cText )

   LOCAL aRows := {}, aRow := {}, cCur := ""
   LOCAL n := LEN( cText ), i := 1, c, c2, lQ := .F.

   WHILE i <= n
      c := SUBSTR( cText, i, 1 )

      IF lQ
         IF c == '"'
            c2 := SUBSTR( cText, i + 1, 1 )
            IF c2 == '"'
               cCur += '"'
               i += 2
               LOOP
            ENDIF
            lQ := .F.
            i++
            LOOP
         ENDIF
         cCur += c
         i++
         LOOP
      ENDIF

      IF c == '"'
         lQ := .T.
         i++
         LOOP
      ENDIF

      IF c == ","
         AADD( aRow, cCur )
         cCur := ""
         i++
         LOOP
      ENDIF

      IF c == CHR( 13 )
         i++
         LOOP
      ENDIF

      IF c == CHR( 10 )
         AADD( aRow, cCur )
         AADD( aRows, aRow )
         aRow := {}
         cCur := ""
         i++
         LOOP
      ENDIF

      cCur += c
      i++
   END

   IF LEN( aRow ) > 0 .OR. ! EMPTY( cCur )
      AADD( aRow, cCur )
      AADD( aRows, aRow )
   ENDIF

RETU aRows

// ---------------------------------------------------------- //
//  Value type for BindParam. The CSV is all text; the column type
//  is what the server wants. prepared.md's type table: "i" integer,
//  "n" decimal, "d" date, "t" timestamp, "s" string. Empty is NULL,
//  and an empty STRING would be '' - the difference P3.5 is about,
//  so NIL is passed explicitly.
// ---------------------------------------------------------- //

STATIC FUNCTION _Coerce( cVal, cType )

   //  The CSV is explicit: CHR( 92 ) + "N" is MariaDB's own spelling of
   //  NULL, and an empty cell is an empty string (the schema's DEFAULT
   //  '' rendered out). They are not the same thing, and P3.5 is about
   //  exactly this difference, so nothing here guesses between them.
   IF cVal == CHR( 92 ) + "N"
      RETU NIL
   ENDIF

   DO CASE
   CASE cType == "i"
      RETU VAL( cVal )
   CASE cType == "n"
      RETU VAL( cVal )
   CASE cType == "b"
      RETU VAL( cVal )
   OTHER
      RETU cVal
   ENDCASE

RETU NIL

STATIC FUNCTION _GuessType( cVal )

   LOCAL n := LEN( cVal ), i, c, nDot := 0, lNum := .T.

   IF cVal == CHR( 92 ) + "N"
      RETU "s"                      //  bound as NIL, the type is not used
   ENDIF

   IF EMPTY( cVal )
      RETU "s"
   ENDIF

   //  date: 2018-01-01
   IF n == 10 .AND. SUBSTR( cVal, 5, 1 ) == "-" .AND. ;
      SUBSTR( cVal, 8, 1 ) == "-" .AND. _IsDigit( SUBSTR( cVal, 1, 1 ) )

      RETU "d"
   ENDIF

   //  timestamp: 2018-01-01 12:00:00 or 2018-01-01T12:00:00
   IF n >= 19 .AND. SUBSTR( cVal, 5, 1 ) == "-" .AND. SUBSTR( cVal, 8, 1 ) == "-"
      RETU "t"
   ENDIF

   FOR i := 1 TO n
      c := SUBSTR( cVal, i, 1 )
      IF c == "-" .OR. c == "+"
         LOOP
      ENDIF
      IF c == "."
         nDot++
         LOOP
      ENDIF
      IF ! _IsDigit( c )
         lNum := .F.
         EXIT
      ENDIF
   NEXT

   IF lNum
      IF nDot == 0
         RETU "i"
      ENDIF
      RETU "n"
   ENDIF

RETU "s"

//  ISDIGIT() is not in the RTL this build links - same class of
//  surprise as P0's hb_MemoWrite / Q() / FPutS. Own helper.
STATIC FUNCTION _IsDigit( c )

RETU c >= "0" .AND. c <= "9"

// ---------------------------------------------------------- //
//  One table. ONE Prepare, N Execute, ONE Free.
//  Returns the number of problems.
// ---------------------------------------------------------- //

STATIC FUNCTION _SeedTable( oConn, cTable )

   LOCAL cFile  := FIXTURE_DIR + "/" + cTable + ".csv"
   LOCAL aCsv, aCols, aRow, cSql, oStmt := NIL
   LOCAL i, k, nIns := 0, nBad := 0, cErr := "", oErr := NIL, cBad := .F.
   LOCAL cCol, cVal, cType, aVals := {}

   IF ! hb_FileExists( cFile )
      ? "  fixtures:", cTable, "- none (no such model in InvenTree's fixtures)"
      RETU 0
   ENDIF

   aCsv  := _CsvRows( hb_MemoRead( cFile ) )
   IF LEN( aCsv ) < 2
      ? "  fixtures:", cTable, "- header only or empty"
      RETU 0
   ENDIF

   aCols := aCsv[ 1 ]

   cSql := "INSERT INTO " + CHR( 96 ) + cTable + CHR( 96 ) + " ( "
   FOR i := 1 TO LEN( aCols )
      cSql += CHR( 96 ) + aCols[i] + CHR( 96 )
      IF i < LEN( aCols )
         cSql += ", "
      ENDIF
   NEXT
   cSql += " ) VALUES ( "
   FOR i := 1 TO LEN( aCols )
      cSql += "?"
      IF i < LEN( aCols )
         cSql += ", "
      ENDIF
   NEXT
   cSql += " )"

   TRY
      oStmt := oConn:Prepare( cSql )

      FOR i := 2 TO LEN( aCsv )
         aRow := aCsv[ i ]
         FOR k := 1 TO LEN( aCols )
            cVal := ""
            IF k <= LEN( aRow )
               cVal := aRow[ k ]
            ENDIF
            cType := _GuessType( cVal )
            oStmt:BindParam( k, _Coerce( cVal, cType ), cType )
         NEXT

         IF ! oStmt:Execute()
            //  no EXIT here: EXIT inside BEGIN SEQUENCE (TRY) breaks
            //  the sequence and skips the rest of the corpus. Flag it,
            //  count it, keep going.
            cBad := .T.
            ? "  !! row", i, "of", cTable, ":", oStmt:cError
            nBad++
         ELSE
            nIns++
         ENDIF
      NEXT

   CATCH oErr
      ? "  !! prepare", cTable, ":", oErr:description
      nBad++
   FINALLY
      //  MANDATORY before the connection is handed back (prepared.md's
      //  danger box): a statement left alive on a pooled connection
      //  shows up in SHOW PREPARED STATEMENTS forever
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
   END

   ? "  seeded", cTable, "=", nIns, "rows (", LEN( aCsv ) - 1, "in the CSV )"
   IF nIns != LEN( aCsv ) - 1 .AND. nBad == 0
      RETU 1
   ENDIF

RETU nBad

STATIC FUNCTION _SeedAll( oConn, aTables )

   LOCAL i, nBad := 0

   FOR i := 1 TO LEN( aTables )
      nBad += _SeedTable( oConn, aTables[i] )
   NEXT

RETU nBad

// ---------------------------------------------------------- //
//  Verify: P1.6's "row counts match the fixture files". The count
//  is read back from the server, and compared with the CSV.
//  DESCRIBE, not SHOW INDEX - see create_mysql_sql: this MariaDB
//  build rejects every SHOW KEY spelling through the driver.
// ---------------------------------------------------------- //

STATIC FUNCTION _Verify( oConn, aTables )

   LOCAL i, aRows, oStmt, cErr, cFile, aCsv, nBad := 0, nWant, nGot, oErr

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

      cFile := FIXTURE_DIR + "/" + aTables[i] + ".csv"
      nWant := 0
      IF hb_FileExists( cFile )
         aCsv  := _CsvRows( hb_MemoRead( cFile ) )
         nWant := MAX( 0, LEN( aCsv ) - 1 )
      ENDIF

      IF EMPTY( aRows )
         IF EMPTY( cErr )
            cErr := "no row back"
         ENDIF
         ? "  !! count", aTables[i], ":", cErr
         nBad++
      ELSE
         //  COUNT(*) comes back numeric or textual depending on the
         //  server's field type; comparing a string with a number is
         //  BASE/1072 "Argument error: <>", so both sides are numbers
         nGot := aRows[ 1 ][ 1 ]
         IF VALTYPE( nGot ) == "C"
            nGot := VAL( nGot )
         ENDIF
         IF nGot != nWant
            ? "  !! count", aTables[i], "=", nGot, "expected", nWant
            nBad++
         ELSE
            ? "  count", aTables[i], "=", nGot
         ENDIF
      ENDIF
   NEXT

RETU nBad
