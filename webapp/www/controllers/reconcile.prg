/*-----------------------------------------------------------
  File ......: reconcile.prg
  Author.....: Charles 9000
  Created....: 2026-10-08
  Version....: 1.0.0
  Description: P7.3 of INVENTREE-MYSQL-PLAN.md - the aggregate reconcile
               check, and P5.1's evidence: the aggregates come from SQL
               (SUM/AVG over the FK indexes) instead of maintained
               counter tables.

               Under MySQL there is no cache to reconcile against, so the
               check is the one that still means something: the two ways
               of reading an aggregate - SQL SUM in one statement, and
               summing the rows the DAL fetches - must agree. If they ever
               disagree, the whitelist, the filter or the pagination is
               wrong, and that is a defect the delete tests would not see.

               GET /hix-reconcile, middleware MyAppAuthRole with the scope
               sys:reconcile - a diagnostic over the whole inventory, so it
               is granted to the admin account only.

               One slot for the whole route (P3.4): every DAL object
               borrows the same connection.

  Usage      : GET /hix-reconcile   (session + sys:reconcile scope)
               200  { ok, tables, checked, mismatches, rows: [
                      { table, column, sql, rows, equal } ] }
               503  { ok: false, error } - no pool
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL oConn, oDal, nSum, nRowSum, nI, nJ, aRows, aOut := {}, nBad := 0
   LOCAL cTable, cCol, hEqual := .T., nChecked := 0
   LOCAL aSpec := { { "stock_stockitem", "quantity" }, ;
                    { "part_bomitem", "quantity" }, ;
                    { "order_salesorderlineitem", "quantity" }, ;
                    { "build_build", "quantity" } }

   oConn := WDO_Get( "mysql" )
   IF oConn == NIL
      RETURN USendJson( { "ok" => .F., ;
                          "error" => "no MySQL/MariaDB pool registered" }, ;
                        503 )
   ENDIF

   FOR nI := 1 TO LEN( aSpec )

      cTable := aSpec[ nI ][ 1 ]
      cCol   := aSpec[ nI ][ 2 ]

      oDal := TDalMySql():New( cTable, { cCol } )
      oDal:Attach( oConn )

      //  the aggregate, in one SQL statement (P5.1)
      nSum := oDal:SumOf( cCol, NIL, NIL )

      //  the same aggregate, summed from the rows the DAL returns
      aRows   := oDal:FetchAll( NIL, NIL )
      nRowSum := 0
      IF aRows != NIL
         FOR nJ := 1 TO LEN( aRows )
            nRowSum += VAL( hb_HGetDef( aRows[ nJ ], cCol, 0 ) )
         NEXT
      ENDIF

      nChecked++
      IF nSum != nRowSum
         nBad++
      ENDIF

      AADD( aOut, { "table"   => cTable, ;
                    "column"  => cCol,   ;
                    "sql"     => nSum,   ;
                    "rows"    => nRowSum, ;
                    "equal"   => ( nSum == nRowSum ) } )

      oDal:Close()
   NEXT

   oConn:Close()

RETURN USendJson( { "ok"         => ( nBad == 0 ), ;
                    "tables"     => LEN( aSpec ), ;
                    "checked"    => nChecked, ;
                    "mismatches" => nBad, ;
                    "rows"       => aOut }, ;
                  iif( nBad == 0, 200, 500 ) )

#include 'models/tdalmysql.prg'
