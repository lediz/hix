/*-----------------------------------------------------------
  File ......: fkcheck.prg
  Author.....: Charles 9000
  Created....: 2026-10-07
  Version....: 1.0.0
  Description: P7.2 of INVENTREE-MYSQL-PLAN.md - the FK orphan check.

               D6 of the FK-policy decisions says an orphan is a
               reportable state and never an auto-repair: a dangling
               FK the app silently re-points is a guess about ownership,
               and the guess is what D1 exists to make explicit. This
               route is the report.

               GET /hix-fk-check, middleware MyAppAuthRole with the
               scope sys:fkcheck - a diagnostic over the whole graph,
               so it is granted to the admin account only (seed_users_mysql
               puts that scope in the admin's roles string).

               One slot for the whole route (P3.4): the connection is
               taken once and every DAL object borrows it, so the 27
               tables with out-edges cost one acquire, not 27.

               The shape is the one Cascade() renders, so the two halves
               of the FK surface read alike: table, column, target, count.

  Usage      : GET /hix-fk-check    (session + sys:fkcheck scope)
               200  { ok, tables, edges, total,
                      orphans: [ { table, column, target, rows } ] }
               503  { ok: false, error }  - no pool
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL hGraph, hFk, aTables, aCols, cTable, cCol, cTgt
   LOCAL oConn, oDal, nOne, aOut := {}, nTotal := 0, nEdges := 0
   LOCAL nI, nJ, hOut

   oConn := WDO_Get( "mysql" )
   IF oConn == NIL
      RETURN USendJson( { "ok" => .F., ;
                          "error" => "no MySQL/MariaDB pool registered" }, ;
                        503 )
   ENDIF

   //  the graph is the shipped schema's, parsed once per process - the
  //  same single source Delete() and Cascade() use, so this route cannot
  //  disagree with what a delete will do
   hGraph := _DalGraph()
   hFk    := hGraph[ "fk" ]
   aTables := hb_HKeys( hFk )

   FOR nI := 1 TO LEN( aTables )

      cTable := aTables[ nI ]
      aCols  := hb_HKeys( hFk[ cTable ] )

      oDal := TDalMySql():New( cTable, {} )
      oDal:Attach( oConn )

      FOR nJ := 1 TO LEN( aCols )

         cCol := aCols[ nJ ]
         cTgt := hb_HGetDef( hFk[ cTable ], cCol, "" )
         nEdges++

         //  per edge, not per table: "stock_stockitem.location ->
          //  stock_stocklocation" is actionable, "stock_stockitem has 4"
          //  is not
         nOne := oDal:OrphansEdge( cCol, cTgt )

         IF nOne != 0
            AADD( aOut, { "table"  => cTable, ;
                          "column" => cCol,  ;
                          "target" => cTgt,  ;
                          "rows"   => nOne } )
            IF nOne > 0
               nTotal += nOne
            ENDIF
         ENDIF
      NEXT

      oDal:Close()
   NEXT

   //  one slot, returned once
   oConn:Close()

   hOut := { "ok"      => .T., ;
             "tables"  => LEN( aTables ), ;
             "edges"   => nEdges, ;
             "total"   => nTotal, ;
             "orphans" => aOut }

RETURN USendJson( hOut, 200 )

#include 'models/tdalmysql.prg'
