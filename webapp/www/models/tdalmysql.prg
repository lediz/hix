/*-----------------------------------------------------------
  File ......: tdalmysql.prg
  Author.....: Charles 9000
  Created....: 2026-10-07
  Modified...: 2026-10-07
  Version....: 1.0.0
  Description: P3 of INVENTREE-MYSQL-PLAN.md - the DAL: one object,
               pool-backed, the verbs the SRS names rather than the
               verbs MySQL names.

                 P3.1  Open/Close, Count, FetchPaged, FetchAll, Show,
                       Insert, Update, Delete, Orphans, Errors.
                 P3.2  every value that came from a form, a URL, JSON
                       or a session goes through Prepare + BindParam
                       - nothing is concatenated. Query() is used only
                       for SQL built entirely in code with no external
                       value (prepared.md's decision tree).
                 P3.3  oStmt:Free() before oConn:Close(), always: each
                       verb frees its own statement in FINALLY, and the
                       handler closes the slot in its own FINALLY.
                 P3.4  one WDO_Get per handler - Open() acquires once,
                       Close() returns it. Never WDO_MySql():New() in a
                       handler; the driver warns when one does.
                 P3.5  one predicate for "not supplied": a key absent
                       from the field hash is SQL NULL, a key present
                       with an empty string is ''. Different, and the
                       seed corpus already writes them differently.
                 P3.6  Errors() answers the SRS banner. The server's
                       words, which name tables and columns, go to the
                       log only.
                 P3.7  Update matches on the version column the shipped
                       schema carries: UPDATE ... WHERE id = ? AND
                       version = ? plus Affected_Rows(); 0 rows is a
                       conflict the caller turns into 409, never a
                       blind overwrite.

               Two deviations from the plan, recorded in
               P3-DAL-RESULTS-2026-10-07.md:

               * New() takes a column whitelist. The KEYS of a field
                 hash are external input as well - they become column
                 names in the SQL - so unknown keys are dropped and
                 logged, never quoted into a statement.
               * the FK columns and their targets are read from the
                 shipped schema (sql/inventree.sql) rather than carried
                 here, so this object cannot drift from what loaded.

  Usage      : LOCAL oDal := TDalMySql():New( "part_part", ;
                         { "name", "description", "IPN" } )
               IF oDal:Open()
                  hRow := oDal:Show( nId )
                  ...
               ENDIF
               oDal:Close()
 -----------------------------------------------------------*/

#include 'hbclass.ch'

#define DAL_POOL_KEY   "mysql"
#define DAL_SCHEMA     "sql/inventree.sql"
#define DAL_BANNER     "System temporarily unavailable. Please try again later."
#define DAL_IDCOL      "id"
#define DAL_VERSION    "version"

CLASS TDalMySql

   METHOD New( cTable, aCols )      CONSTRUCTOR
   METHOD Open()
   METHOD Close()
   METHOD Count( hFilter )
   METHOD FetchAll( hFilter )
   METHOD FetchPaged( nLimit, nOffset, hFilter )
   METHOD Show( nId )
   METHOD Insert( hFields )
   METHOD Update( nId, nVersion, hFields )
   METHOD Delete( nId, hOverride )
   METHOD Cascade( nId, hOverride )
   METHOD Orphans()
   METHOD Attach( oConn )
   METHOD Errors()
   METHOD Destroy()

   DATA oConn          INIT NIL
   DATA lOwn           INIT .F.
   DATA cTable         INIT ""
   DATA aCols          INIT {}
   DATA cErrSafe       INIT ""
   DATA cErrRaw        INIT ""
   DATA cLastReason    INIT ""
   DATA nLastId        INIT 0
   DATA nRowAffected   INIT 0
   DATA lBorrow        INIT .F.

ENDCLASS


METHOD New( cTable, aCols ) CLASS TDalMySql

   ::cTable      := hb_defaultValue( cTable, "" )
   ::aCols       := hb_defaultValue( aCols, {} )
   ::oConn       := NIL
   ::lOwn        := .F.
   ::cErrSafe    := ""
   ::cErrRaw     := ""
   ::cLastReason := ""
   ::lBorrow     := .F.

RETU SELF


// -------------------------------------------------------------- //
//  P3.4: one WDO_Get per handler.
// -------------------------------------------------------------- //

METHOD Open() CLASS TDalMySql

   //  P3.4: one WDO_Get per HANDLER, not per DAL object. A module that
   //  touches several tables attaches to the handler's slot (Attach)
   //  instead of taking one each - twelve tables against a pool of eight
   //  would block on the ninth WDO_Get against the pool timeout rather
   //  than fail.
   IF ::lBorrow
      RETU ::oConn != NIL
   ENDIF

   IF ::lOwn .AND. ::oConn != NIL
      RETU .T.
   ENDIF

   ::oConn := WDO_Get( DAL_POOL_KEY )

   IF ::oConn == NIL
      _DalFail( SELF, "no pool slot", "WDO_Get(" + DAL_POOL_KEY + ") = NIL" )
      RETU .F.
   ENDIF

   ::lOwn := .T.

RETU .T.


METHOD Attach( oConn ) CLASS TDalMySql

   //  borrow the handler's slot: this object uses the connection but
   //  never returns it to the pool - the handler that acquired it does,
   //  once, in its own FINALLY
   ::oConn   := oConn
   ::lBorrow := .T.
   ::lOwn    := .F.

RETU NIL


METHOD Close() CLASS TDalMySql

   //  only an owned slot is returned. A borrowed connection is left as
   //  it is: closing it here would hand the pool slot back while the
   //  handler still holds other DAL objects on it
   IF ::oConn != NIL .AND. ::lOwn
      ::oConn:Close()
      ::oConn := NIL
      ::lOwn  := .F.
   ENDIF

   ::lBorrow := .F.

RETU NIL


METHOD Destroy() CLASS TDalMySql

   ::Close()

RETU NIL


// -------------------------------------------------------------- //
//  P3.6: the safe words go to the caller, the real ones to the log.
//  The server's message names tables and columns, so it must never be
//  the response body (SRS 5.3: one banner, always the same words).
// -------------------------------------------------------------- //

STATIC FUNCTION _DalFail( oDal, cSafe, cRaw )

   oDal:cErrSafe    := cSafe
   oDal:cErrRaw     := cRaw
   oDal:cLastReason := cSafe

   //  the framework logger, called directly: le() is a #xtranslate in
   //  hix_logger.ch, and a runtime-loaded model must not depend on that
   //  header being on the runtime include path
   _l( "tdalmysql " + oDal:cTable + ": " + cRaw, 4, "tdalmysql" )

RETU NIL


METHOD Errors() CLASS TDalMySql

   IF Empty( ::cErrSafe )
      RETU NIL
   ENDIF

RETU { "banner" => DAL_BANNER, ;
       "reason" => ::cLastReason, ;
       "detail" => ::cErrSafe }


// -------------------------------------------------------------- //
//  P3.5: one predicate for "not supplied". Absent -> NIL -> SQL NULL.
//  Present with "" -> '' . The two are different and the seed corpus
//  already writes them differently (MariaDB's own NULL mark against an
//  empty cell), so the DAL must not merge them.
// -------------------------------------------------------------- //

STATIC FUNCTION _DalVal( hFields, cCol )

   IF ! ValType( hFields ) == 'H'
      RETU NIL
   ENDIF

   IF ! hb_HHasKey( hFields, cCol )
      RETU NIL
   ENDIF

RETU hb_HGetDef( hFields, cCol, NIL )


// -------------------------------------------------------------- //
//  P3.2: the KEYS of a field hash are external input as well - they
//  become column names in the SQL. Only names the module declared in
//  New() are used; the rest are dropped and logged, never quoted into
//  a statement.
// -------------------------------------------------------------- //

STATIC FUNCTION _DalColsOk( oDal, hFields )

   LOCAL aOut := {}, cCol

   IF ! ValType( hFields ) == 'H'
      RETU aOut
   ENDIF

   FOR EACH cCol IN hb_HKeys( hFields )
      IF _DalIsCol( oDal, cCol )
         AADD( aOut, cCol )
      ELSE
         _l( "tdalmysql: dropped a field name outside the module's column list: " ;
             + oDal:cTable + "." + cCol, 4, "tdalmysql" )
      ENDIF
   NEXT

   ASORT( aOut )

RETU aOut


STATIC FUNCTION _DalIsCol( oDal, cCol )

   LOCAL nI

   FOR nI := 1 TO LEN( oDal:aCols )
      IF oDal:aCols[ nI ] == cCol
         RETU .T.
      ENDIF
   NEXT

RETU .F.


// -------------------------------------------------------------- //
//  SQL text, built from code-known names only. Values never appear
//  here - they are bound (P3.2).
// -------------------------------------------------------------- //

STATIC FUNCTION _DalQ( cName )

RETU CHR( 96 ) + cName + CHR( 96 )


STATIC FUNCTION _DalSqlCols( aCols )

   LOCAL cOut := "", nI

   FOR nI := 1 TO LEN( aCols )
      IF nI > 1
         cOut += ", "
      ENDIF
      cOut += _DalQ( aCols[ nI ] )
   NEXT

RETU cOut


STATIC FUNCTION _DalSqlPlace( nCount )

   LOCAL cOut := "", nI

   FOR nI := 1 TO nCount
      IF nI > 1
         cOut += ", "
      ENDIF
      cOut += "?"
   NEXT

RETU cOut


STATIC FUNCTION _DalSqlSet( aCols )

   LOCAL cOut := "", nI, cCol

   FOR nI := 1 TO LEN( aCols )
      IF nI > 1
         cOut += ", "
      ENDIF
      cCol := aCols[ nI ]
      cOut += _DalQ( cCol ) + " = ?"
   NEXT

RETU cOut


//  the filter text and its values, in the SAME order, so a caller can
//  never bind a value to the wrong placeholder
STATIC FUNCTION _DalFilterKeys( oDal, hFilter )

RETU _DalColsOk( oDal, hFilter )


STATIC FUNCTION _DalSqlFilter( oDal, aKeys )

   LOCAL cOut := "", nI

   FOR nI := 1 TO LEN( aKeys )
      IF nI > 1
         cOut += " AND "
      ENDIF
      cOut += _DalQ( aKeys[ nI ] ) + " = ?"
   NEXT

RETU cOut


// -------------------------------------------------------------- //
//  The FK graph, read from the shipped schema once per process.
//
//  The lines that matter look like
//     CREATE TABLE `part_part` (
//     KEY `fk_part_part_category` (`category`)  /* -> part_partcategory.id */,
//  so the table, the column and the target all come from the file that
//  actually loaded - this object carries no second copy of the graph
//  and cannot drift from it.
// -------------------------------------------------------------- //

STATIC FUNCTION _DalGraph()

   LOCAL aLines, cLine, cTable := "", cCol, cTgt
   LOCAL hFk := { => }, hRev := { => }, hPol := { => }, hOut
   STATIC s_hGraph := NIL

   IF s_hGraph != NIL
      RETU s_hGraph
   ENDIF

   aLines := _DalSchemaLines()

   FOR EACH cLine IN aLines

      IF _DalStart( cLine, "CREATE TABLE " )
         cTgt  := _DalAfter( cLine, "CREATE TABLE " )
         cTable := _DalWord( cTgt )
      ELSEIF _DalStart( _DalTrim( cLine ), "KEY `fk_" )

         cCol := _DalParenCol( cLine )
         cTgt := _DalTarget( cLine )

         IF ! EMPTY( cCol ) .AND. ! EMPTY( cTgt ) .AND. ! EMPTY( cTable )

            IF ! hb_HHasKey( hFk, cTable )
               hFk[ cTable ] := { => }
            ENDIF
            hFk[ cTable ][ cCol ] := cTgt

            //  Step 0.3: the delete policy is a property of the EDGE, and
            //  the edges into one table come from ten different modules, so
            //  it is declared here - next to the relation, in the file that
            //  is the single source of the graph - and not in a controller.
            //  Absent means KEEP: the dependent row keeps a dangling value
            //  and Orphans()/Cascade() make that visible instead of the DAL
            //  guessing a policy the artefact never states per FK.
            IF ! hb_HHasKey( hPol, cTable )
               hPol[ cTable ] := { => }
            ENDIF
            hPol[ cTable ][ cCol ] := _DalPolicy( cLine )

            IF ! hb_HHasKey( hRev, cTgt )
               hRev[ cTgt ] := {}
            ENDIF
            AADD( hRev[ cTgt ], { cTable, cCol } )

         ENDIF
      ENDIF

   NEXT

   s_hGraph := { "fk" => hFk, "rev" => hRev, "pol" => hPol }

RETU s_hGraph


STATIC FUNCTION _DalSchemaLines()

   LOCAL cText := hb_MemoRead( DAL_SCHEMA )
   LOCAL aLines := {}, nPos := 1, nNl, cLine

   IF cText == NIL
      RETU aLines
   ENDIF

   WHILE nPos <= LEN( cText )
      nNl := _DalNl( cText, nPos )
      IF nNl == 0
         cLine := SUBSTR( cText, nPos )
         nPos  := LEN( cText ) + 1
      ELSE
         cLine := SUBSTR( cText, nPos, nNl - nPos )
         nPos  := nNl + 1
      ENDIF
      AADD( aLines, cLine )
   END

RETU aLines


// -------------------------------------------------------------- //
//  One statement, no external value. TRUE = it ran.
//
//  Query(), not Exec(): Exec() raises a DynCall "Argument error" for
//  some statements (P0 record), and every tool in this folder already
//  goes through Query() + FetchAll() + Free().
// -------------------------------------------------------------- //

STATIC FUNCTION _DalRun( oDal, cSql )

   LOCAL oStmt := NIL
   LOCAL oErr := NIL
   LOCAL aRows := NIL
   LOCAL lOk := .F.

   BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
      oStmt := oDal:oConn:Query( cSql )
      aRows := oStmt:FetchAll( .T. )
      lOk   := ! oStmt:lError
      IF ! lOk
         _DalFail( oDal, DAL_BANNER, oStmt:cError )
      ENDIF
   END

   //  P3.3: reached on every path - a Break() above exits the sequence
   //  and execution continues here, so the statement is freed before the
   //  slot can be handed back (prepared.md's danger box).
   IF oStmt != NIL
      oStmt:Free()
   ENDIF

   //  NIL means it failed; an EMPTY() array means it ran and found
   //  nothing. The two are different and the callers use both.
   IF ! lOk
      RETU NIL
   ENDIF

RETU aRows


// -------------------------------------------------------------- //
//  One prepared statement with bound values. The rows back, or NIL
//  when it failed. (An out-parameter cannot work: re-binding a
//  parameter inside a function breaks the reference.)
//  aVals is an array of { value, type } pairs, in placeholder order.
// -------------------------------------------------------------- //

STATIC FUNCTION _DalPrepared( oDal, cSql, aVals )

   LOCAL oStmt := NIL
   LOCAL oErr := NIL
   LOCAL aRows := NIL
   LOCAL lOk := .F.
   LOCAL nI

   BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
      oStmt := oDal:oConn:Prepare( cSql )

      FOR nI := 1 TO LEN( aVals )
         oStmt:BindParam( nI, aVals[ nI ][ 1 ], aVals[ nI ][ 2 ] )
      NEXT

      lOk := oStmt:Execute()

      IF lOk
         //  read while the statement is still alive: Free() below resets
         //  what the connection reports. Row_Count() is the statement's
         //  own count (prepared.md: rows affected for INSERT/UPDATE/
         //  DELETE, rows returned for SELECT) - the connection's
         //  Affected_Rows() reported 0 for a prepared UPDATE here, so the
         //  conflict test uses the statement's number, not the pool
         //  connection's
         oDal:nLastId     := oDal:oConn:Last_Insert_Id()
         oDal:nRowAffected := oStmt:Row_Count()
         aRows := oStmt:FetchAll( .T. )
      ELSE
         _DalFail( oDal, DAL_BANNER, oStmt:cError )
      ENDIF
   END

   //  P3.3: freed on every path, including the one where an exception
   //  broke the sequence above
   IF oStmt != NIL
      oStmt:Free()
   ENDIF

   IF ! lOk
      RETU NIL
   ENDIF

RETU aRows


// -------------------------------------------------------------- //
//  Value type for BindParam. The handler validates before it calls;
//  this only decides how a value is put on the wire. NIL stays NIL
//  (SQL NULL) - an empty string is '' (P3.5).
// -------------------------------------------------------------- //

STATIC FUNCTION _DalBind( xVal )

   IF xVal == NIL
      RETU { NIL, "s" }
   ENDIF

   IF ValType( xVal ) == 'N'
      RETU { xVal, "n" }
   ENDIF

   IF ValType( xVal ) == 'D'
      RETU { xVal, "d" }
   ENDIF

   IF _DalIsInt( xVal )
      RETU { VAL( xVal ), "i" }
   ENDIF

   IF _DalIsNum( xVal )
      RETU { VAL( xVal ), "n" }
   ENDIF

   IF _DalIsDate( xVal )
      RETU { xVal, "d" }
   ENDIF

RETU { xVal, "s" }


// -------------------------------------------------------------- //
//  Why an Update touched nothing: the row is gone, or another session
//  wrote it first. The handler answers 404 or 409, and the two are not
//  the same answer.
// -------------------------------------------------------------- //

STATIC FUNCTION _DalWhy( oDal, nId )

   LOCAL cSql, aRows := NIL

   cSql := "SELECT COUNT(*) FROM " + _DalQ( oDal:cTable ) + " WHERE " ;
     + _DalQ( DAL_IDCOL ) + " = ?"

   aRows := _DalPrepared( oDal, cSql, { { nId, "i" } } )
   IF aRows != NIL
      IF EMPTY( aRows ) .OR. _DalRowNum( aRows[ 1 ] ) == 0
         RETU "not found"
      ENDIF
   ENDIF

RETU "conflict"


// -------------------------------------------------------------- //
//  The verbs.
// -------------------------------------------------------------- //

METHOD Count( hFilter ) CLASS TDalMySql

   LOCAL aKeys, cSql, aRows := NIL, aVals := {}

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "Count() called with no slot" )
      RETU -1
   ENDIF

   aKeys := _DalFilterKeys( SELF, hFilter )
   cSql  := "SELECT COUNT(*) FROM " + _DalQ( ::cTable )

   IF ! EMPTY( aKeys )
      cSql += " WHERE " + _DalSqlFilter( SELF, aKeys )
      aVals := _DalFilterVals( SELF, aKeys, hFilter )
      //  the filter carries values, so this SQL is not constant: it is
      //  prepared, not Query()
      aRows := _DalPrepared( SELF, cSql, aVals )
      IF aRows == NIL
         RETU -1
      ENDIF
   ELSE
      //  constant SQL, no external value: Query() is the right call
      aRows := _DalRun( SELF, cSql )
      IF aRows == NIL
         RETU -1
      ENDIF
   ENDIF

   IF EMPTY( aRows )
      _DalFail( SELF, DAL_BANNER, "COUNT(*) returned no row" )
      RETU -1
   ENDIF

RETU _DalRowNum( aRows[ 1 ] )


METHOD FetchAll( hFilter ) CLASS TDalMySql

   LOCAL aKeys, cSql, aRows := NIL, aVals := {}

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "FetchAll() called with no slot" )
      RETU NIL
   ENDIF

   aKeys := _DalFilterKeys( SELF, hFilter )
   cSql  := "SELECT " + _DalSqlCols( ::aCols ) + " FROM " + _DalQ( ::cTable )

   IF ! EMPTY( aKeys )
      cSql += " WHERE " + _DalSqlFilter( SELF, aKeys )
      aVals := _DalFilterVals( SELF, aKeys, hFilter )
   ENDIF

   cSql += " ORDER BY " + _DalQ( DAL_IDCOL )

   aRows := _DalPrepared( SELF, cSql, aVals )
   IF aRows == NIL
      RETU NIL
   ENDIF

RETU aRows


METHOD FetchPaged( nLimit, nOffset, hFilter ) CLASS TDalMySql

   LOCAL aKeys, cSql, aRows := NIL, aVals := {}

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "FetchPaged() called with no slot" )
      RETU NIL
   ENDIF

   aKeys := _DalFilterKeys( SELF, hFilter )
   cSql  := "SELECT " + _DalSqlCols( ::aCols ) + " FROM " + _DalQ( ::cTable )

   IF ! EMPTY( aKeys )
      cSql += " WHERE " + _DalSqlFilter( SELF, aKeys )
      aVals := _DalFilterVals( SELF, aKeys, hFilter )
   ENDIF

   //  the page bounds are external too (they come from a query string)
   cSql += " ORDER BY " + _DalQ( DAL_IDCOL ) + " LIMIT ? OFFSET ?"

   AADD( aVals, _DalBind( nLimit ) )
   AADD( aVals, _DalBind( nOffset ) )

   aRows := _DalPrepared( SELF, cSql, aVals )
   IF aRows == NIL
      RETU NIL
   ENDIF

RETU aRows


METHOD Show( nId ) CLASS TDalMySql

   LOCAL cSql, aRows := NIL, aVals := {}

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "Show() called with no slot" )
      RETU NIL
   ENDIF

   //  the version column is returned with the row: it is what Update
   //  matches on, so the caller has to have read it (P3.7)
   cSql := "SELECT " + _DalQ( DAL_IDCOL ) + ", " + _DalQ( DAL_VERSION ) + ", " ;
     + _DalSqlCols( ::aCols ) + " FROM " + _DalQ( ::cTable ) ;
     + " WHERE " + _DalQ( DAL_IDCOL ) + " = ?"

   AADD( aVals, _DalBind( nId ) )

   aRows := _DalPrepared( SELF, cSql, aVals )
   IF aRows == NIL
      RETU NIL
   ENDIF

   IF EMPTY( aRows )
      RETU NIL
   ENDIF

RETU aRows[ 1 ]


METHOD Insert( hFields ) CLASS TDalMySql

   LOCAL aCols, cSql, aVals := {}, aRows := NIL, nNew := 0, nI, cCol

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "Insert() called with no slot" )
      RETU 0
   ENDIF

   aCols := _DalColsOk( SELF, hFields )

   IF EMPTY( aCols )
      _DalFail( SELF, DAL_BANNER, "Insert() with no accepted field" )
      RETU 0
   ENDIF

   cSql := "INSERT INTO " + _DalQ( ::cTable ) + " ( " + _DalSqlCols( aCols ) ;
     + " ) VALUES ( " + _DalSqlPlace( LEN( aCols ) ) + " )"

   FOR nI := 1 TO LEN( aCols )
      cCol  := aCols[ nI ]
      AADD( aVals, _DalBind( _DalVal( hFields, cCol ) ) )
   NEXT

   aRows := _DalPrepared( SELF, cSql, aVals )
   IF aRows == NIL
      RETU 0
   ENDIF

   //  ids are server-assigned (Step 0.3): the create flow reads
   //  Last_Insert_Id(), it never assumes one. Read inside the prepared
   //  call (oDal:nLastId), not after Free() - after Free() the
   //  connection reports 0
   nNew := ::nLastId

RETU nNew


METHOD Update( nId, nVersion, hFields ) CLASS TDalMySql

   LOCAL aCols, aVals := {}, cSql, aRows := NIL, nAffected := 0, nI, cCol

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "Update() called with no slot" )
      RETU .F.
   ENDIF

   aCols := _DalColsOk( SELF, hFields )

   IF EMPTY( aCols )
      _DalFail( SELF, DAL_BANNER, "Update() with no accepted field" )
      RETU .F.
   ENDIF

   FOR nI := 1 TO LEN( aCols )
      cCol  := aCols[ nI ]
      AADD( aVals, _DalBind( _DalVal( hFields, cCol ) ) )
   NEXT

   //  P3.7: the version column is bumped in the same statement, and the
   //  WHERE carries the version the caller read. Two sessions that read
   //  the same row and one of them writes second gets 0 rows affected.
   cSql := "UPDATE " + _DalQ( ::cTable ) + " SET " + _DalSqlSet( aCols ) ;
     + ", " + DAL_VERSION + " = ?"

   AADD( aVals, _DalBind( nVersion + 1 ) )

   cSql += " WHERE " + _DalQ( DAL_IDCOL ) + " = ? AND " + DAL_VERSION ;
     + " = ?"

   AADD( aVals, _DalBind( nId ) )
   AADD( aVals, _DalBind( nVersion ) )

   aRows := _DalPrepared( SELF, cSql, aVals )
   IF aRows == NIL
      RETU .F.
   ENDIF

   nAffected := ::nRowAffected

   IF nAffected == 0
      //  not a blind overwrite: say which of the two it was, so the
      //  handler answers 409 (conflict) rather than 404 (missing)
      ::cErrSafe    := "no row matched that version"
      ::cLastReason := _DalWhy( SELF, nId )
      RETU .F.
   ENDIF

RETU .T.


//  the mode for one edge: an override (a caller that decides for this
//  call) beats the policy declared in the schema, which beats KEEP.
//  Only the three modes Step 0.3 names are possible.
STATIC FUNCTION _DalMode( cOther, cCol, hOverride )

   LOCAL cMode := "KEEP"
   LOCAL hGraph := _DalGraph()
   LOCAL hTab

   hTab := hb_HGetDef( hGraph[ "pol" ], cOther, NIL )

   IF ValType( hTab ) == 'H'
      cMode := hb_HGetDef( hTab, cCol, "KEEP" )
      IF EMPTY( cMode )
         cMode := "KEEP"
      ENDIF
   ENDIF

   IF ValType( hOverride ) == 'H' .AND. hb_HHasKey( hOverride, cOther )
      cMode := Upper( hb_HGetDef( hOverride, cOther, cMode ) )
   ENDIF

   IF cMode != "CASCADE" .AND. cMode != "NULL"
      cMode := "KEEP"
   ENDIF

RETU cMode


//  what a delete WOULD do: per referring table, the mode that applies and
//  how many rows it touches. delete_confirm shows this before the
//  destructive verb runs (SRS FR-DELETE-1..4) - with 15 edges into part_part
//  the user has to see "400 stock items" before clicking, not after.
METHOD Cascade( nId, hOverride ) CLASS TDalMySql

   LOCAL hGraph, aRev, cOther, cCol, cMode, cSql, aRows
   LOCAL hOut := { => }, hEdge, nTotal := 0, nI

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "Cascade() called with no connection" )
      RETU { "total" => -1 }
   ENDIF

   hGraph := _DalGraph()

   IF ! hb_HHasKey( hGraph[ "rev" ], ::cTable )
      RETU { "total" => 0 }
   ENDIF

   aRev := hGraph[ "rev" ][ ::cTable ]

   FOR nI := 1 TO LEN( aRev )

      cOther := aRev[ nI ][ 1 ]
      cCol   := aRev[ nI ][ 2 ]
      cMode  := _DalMode( cOther, cCol, hOverride )

      cSql  := "SELECT COUNT(*) FROM " + _DalQ( cOther ) + " WHERE " ;
        + _DalQ( cCol ) + " = ?"

      aRows := _DalPrepared( SELF, cSql, { { nId, "i" } } )

      IF aRows == NIL
         RETU { "total" => -1 }
      ENDIF

      hEdge := { "mode" => cMode, "rows" => 0 }
      IF ! EMPTY( aRows )
         hEdge[ "rows" ] := _DalRowNum( aRows[ 1 ] )
      ENDIF

      hOut[ cOther ] := hEdge
      nTotal += hEdge[ "rows" ]

   NEXT

   hOut[ "total" ] := nTotal

RETU hOut


METHOD Delete( nId, hOverride ) CLASS TDalMySql

   LOCAL hGraph, aRev, hOut := { => }, cSql, aRows := NIL
   LOCAL nI, cOther, cCol, cMode, nDone := 0

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "Delete() called with no slot" )
      RETU { "deleted" => 0 }
   ENDIF

   //  Step 0.3: MariaDB carries only the KEY index, so CASCADE / SET_NULL
   //  / DO_NOTHING are applied here. The mode for an edge comes from the
   //  policy declared in the shipped schema (the single source, keyed by
   //  edge - see _DalMode), and hOverride is a per-call decision on top of
   //  it. Absent both means KEEP: the dependent row keeps a dangling value
   //  and Cascade()/Orphans() make that visible rather than the DAL
   //  guessing a policy the artefact never states per FK.
   hGraph := _DalGraph()

   cSql := "DELETE FROM " + _DalQ( ::cTable ) + " WHERE " + _DalQ( DAL_IDCOL ) ;
     + " = ?"

   aRows := _DalPrepared( SELF, cSql, { { nId, "i" } } )
   IF aRows == NIL
      RETU { "deleted" => 0 }
   ENDIF

   hOut[ "deleted" ] := ::nRowAffected

   IF hb_HHasKey( hGraph[ "rev" ], ::cTable )

      aRev := hGraph[ "rev" ][ ::cTable ]

      FOR nI := 1 TO LEN( aRev )

         cOther := aRev[ nI ][ 1 ]
         cCol   := aRev[ nI ][ 2 ]
         cMode  := _DalMode( cOther, cCol, hOverride )

         IF cMode == "CASCADE"

            cSql := "DELETE FROM " + _DalQ( cOther ) + " WHERE " ;
              + _DalQ( cCol ) + " = ?"

            aRows := _DalPrepared( SELF, cSql, { { nId, "i" } } )
            IF aRows != NIL
               hOut[ cOther ] := ::nRowAffected
               nDone++
            ENDIF

         ELSEIF cMode == "NULL"

            //  the FK value becomes SQL NULL, not '' - P3.5 again
            cSql := "UPDATE " + _DalQ( cOther ) + " SET " + _DalQ( cCol ) ;
              + " = ? WHERE " + _DalQ( cCol ) + " = ?"

            aRows := _DalPrepared( SELF, cSql, { { NIL, "s" }, ;
                                          { nId, "i" } } )
            IF aRows != NIL
               hOut[ cOther ] := ::nRowAffected
               nDone++
            ENDIF

         ELSE
            hOut[ cOther ] := 0
         ENDIF

      NEXT

   ENDIF

   hOut[ "edges" ] := nDone

RETU hOut


METHOD Orphans() CLASS TDalMySql

   LOCAL hGraph, hFk, cCol, cTgt, cSql, aRows, nTotal := 0, nOne

   IF ::oConn == NIL
      _DalFail( SELF, DAL_BANNER, "Orphans() called with no slot" )
      RETU -1
   ENDIF

   hGraph := _DalGraph()

   IF ! hb_HHasKey( hGraph[ "fk" ], ::cTable )
      RETU 0
   ENDIF

   hFk := hGraph[ "fk" ][ ::cTable ]

   FOR EACH cCol IN hb_HKeys( hFk )

      cTgt  := hFk[ cCol ]

      //  a row whose FK value is set but whose target row is gone.
      //  EXISTS is the shape MariaDB answers here; SHOW-family
      //  introspection does not parse through this driver (P1 record).
      cSql := "SELECT COUNT(*) FROM " + _DalQ( ::cTable ) + " WHERE " ;
        + _DalQ( cCol ) + " IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM " ;
        + _DalQ( cTgt ) + " WHERE " + _DalQ( DAL_IDCOL ) + " = " ;
        + _DalQ( cCol ) + " )"

      aRows := _DalRun( SELF, cSql )
      IF aRows == NIL
         RETU -1
      ENDIF

      nOne := 0
      IF ! EMPTY( aRows )
         nOne := _DalRowNum( aRows[ 1 ] )
      ENDIF
      nTotal += nOne

   NEXT

RETU nTotal


// -------------------------------------------------------------- //
//  Small text helpers. Harbour's RTL on this build has no POS(), so
//  the scan is explicit (P1 record: POS()/IIF() are not linked).
// -------------------------------------------------------------- //

STATIC FUNCTION _DalFind( cHay, cNeedle )

   LOCAL nLen := LEN( cNeedle ), nI

   IF EMPTY( cNeedle )
      RETU 0
   ENDIF

   FOR nI := 1 TO LEN( cHay ) - nLen + 1
      IF SUBSTR( cHay, nI, nLen ) == cNeedle
         RETU nI
      ENDIF
   NEXT

RETU 0


STATIC FUNCTION _DalNl( cText, nFrom )

   LOCAL nI, n := LEN( cText )

   FOR nI := nFrom TO n
      IF SUBSTR( cText, nI, 1 ) == CHR( 10 )
         RETU nI
      ENDIF
   NEXT

RETU 0


STATIC FUNCTION _DalTrim( cText )

RETU ALLTRIM( cText )


STATIC FUNCTION _DalStart( cText, cPref )

   IF EMPTY( cPref )
      RETU .F.
   ENDIF

RETU SUBSTR( cText, 1, LEN( cPref ) ) == cPref


STATIC FUNCTION _DalAfter( cText, cPref )

   IF ! _DalStart( cText, cPref )
      RETU ""
   ENDIF

RETU SUBSTR( cText, LEN( cPref ) + 1 )


STATIC FUNCTION _DalUnq( cText )

   LOCAL cQ := CHR( 96 ), nPos

   cText := ALLTRIM( cText )

   IF EMPTY( cText )
      RETU ""
   ENDIF

   IF SUBSTR( cText, 1, 1 ) == cQ
      cText := SUBSTR( cText, 2 )
      nPos  := _DalFind( cText, cQ )
      IF nPos > 0
         cText := SUBSTR( cText, 1, nPos - 1 )
      ENDIF
   ENDIF

RETU ALLTRIM( cText )


//  `part_part` (            ->  part_part
STATIC FUNCTION _DalWord( cText )

   LOCAL nPos := _DalFind( cText, " (" )

   IF nPos > 0
      cText := SUBSTR( cText, 1, nPos - 1 )
   ENDIF

RETU _DalUnq( cText )


//  KEY `fk_part_part_category` (`category`)  /* -> part_partcategory.id */
//  ->  part_partcategory ; the policy word after it, when present
STATIC FUNCTION _DalPolicy( cLine )

   LOCAL nPos := _DalFind( cLine, "policy=" )
   LOCAL cRest, nSp, nStar, nEnd, cMode

   IF nPos == 0
      RETU ""
   ENDIF

   cRest := SUBSTR( cLine, nPos + 7 )

   nSp   := _DalFind( cRest, " " )
   nStar := _DalFind( cRest, "*" )
   nEnd  := LEN( cRest )

   IF nSp > 0 .AND. nSp < nEnd
      nEnd := nSp
   ENDIF
   IF nStar > 0 .AND. nStar < nEnd
      nEnd := nStar
   ENDIF

   cMode := Upper( ALLTRIM( SUBSTR( cRest, 1, nEnd - 1 ) ) )

   IF cMode != "CASCADE" .AND. cMode != "NULL" .AND. cMode != "KEEP"
      RETU ""
   ENDIF

RETU cMode


//  KEY `fk_part_part_category` (`category`) ...  ->  category
STATIC FUNCTION _DalParenCol( cLine )

   LOCAL nOpen := _DalFind( cLine, "(" )
   LOCAL cRest, nClose

   IF nOpen == 0
      RETU ""
   ENDIF

   cRest   := SUBSTR( cLine, nOpen + 1 )
   nClose  := _DalFind( cRest, ")" )

   IF nClose == 0
      RETU ""
   ENDIF

RETU _DalUnq( SUBSTR( cRest, 1, nClose - 1 ) )


//  ... /* -> part_partcategory.id */ ...  ->  part_partcategory
STATIC FUNCTION _DalTarget( cLine )

   LOCAL nPos := _DalFind( cLine, "-> " )
   LOCAL cRest, nDot

   IF nPos == 0
      RETU ""
   ENDIF

   cRest := SUBSTR( cLine, nPos + 3 )
   nDot  := _DalFind( cRest, "." )

   IF nDot == 0
      RETU ALLTRIM( cRest )
   ENDIF

RETU ALLTRIM( SUBSTR( cRest, 1, nDot - 1 ) )


//  COUNT(*) comes back as a one-field hash; the field name is the
//  server's, not ours, so take the value, not the key
STATIC FUNCTION _DalRowNum( hRow )

   LOCAL cKey, xVal := 0

   IF ! ValType( hRow ) == 'H'
      RETU 0
   ENDIF

   FOR EACH cKey IN hb_HKeys( hRow )
      xVal := hb_HGetDef( hRow, cKey, 0 )
      EXIT
   NEXT

   //  COUNT(*) comes back textual on this path; comparing a string with
   //  a number is BASE/1072 "Argument error: <>", so the count is a
   //  number here (same coercion P2's health route had to make)
   IF VALTYPE( xVal ) == "C"
      xVal := VAL( xVal )
   ENDIF

RETU xVal


//  the filter's values, in the SAME order as _DalSqlFilter() writes its
//  placeholders
STATIC FUNCTION _DalFilterVals( oDal, aKeys, hFilter )

   LOCAL aOut := {}, nI, cCol

   FOR nI := 1 TO LEN( aKeys )
      cCol  := aKeys[ nI ]
      AADD( aOut, _DalBind( _DalVal( hFilter, cCol ) ) )
   NEXT

RETU aOut


// -------------------------------------------------------------- //
//  Shape tests for BindParam's type. Explicit, because the CSV corpus
//  and the handlers have to agree on what a value is.
// -------------------------------------------------------------- //

STATIC FUNCTION _DalIsInt( xVal )

   LOCAL nI, c, n := LEN( xVal )

   IF ValType( xVal ) != 'C' .OR. n == 0
      RETU .F.
   ENDIF

   FOR nI := 1 TO n
      c := SUBSTR( xVal, nI, 1 )
      IF nI == 1 .AND. ( c == "-" .OR. c == "+" )
         LOOP
      ENDIF
      IF c < "0" .OR. c > "9"
         RETU .F.
      ENDIF
   NEXT

RETU .T.


STATIC FUNCTION _DalIsNum( xVal )

   LOCAL nI, c, nDot := 0, n := LEN( xVal ), lSeen := .F.

   IF ValType( xVal ) != 'C' .OR. n == 0
      RETU .F.
   ENDIF

   FOR nI := 1 TO n
      c := SUBSTR( xVal, nI, 1 )
      IF nI == 1 .AND. ( c == "-" .OR. c == "+" )
         LOOP
      ENDIF
      IF c == "."
         nDot++
         LOOP
      ENDIF
      IF c >= "0" .AND. c <= "9"
         lSeen := .T.
         LOOP
      ENDIF
      RETU .F.
   NEXT

RETU lSeen .AND. nDot == 1


STATIC FUNCTION _DalIsDate( xVal )

   IF ValType( xVal ) != 'C' .OR. LEN( xVal ) != 10
      RETU .F.
   ENDIF

RETU SUBSTR( xVal, 5, 1 ) == "-" .AND. SUBSTR( xVal, 8, 1 ) == "-" ;
     .AND. SUBSTR( xVal, 1, 1 ) >= "0" .AND. SUBSTR( xVal, 1, 1 ) <= "9"
