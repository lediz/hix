/*
 * migrate_users.prg — Seed users RDDCDX with migrated credentials
 * Complies with DEV-compliance.md: HIX framework only, no SQL, local git
 */

#include "hbclass.ch"
#include "data_dir.prg"

FUNCTION MAIN()
   LOCAL cData, hRow
   LOCAL oDB
   
   cData := DataDir()
   IF cData == NIL
      RETURN NIL
   ENDIF
   cData := cData + "/users.dbf"
   
   // Ensure DB exists with correct schema (N id, C name, C pass, M roles)
   IF ! FILE( cData )
      QOut( "Creating users RDDCDX: " + cData )
      DBCREATE( cData, { { "id", "N", 10, 0 }, { "name", "C", 50, 0 }, { "pass", "C", 40, 0 }, { "roles", "M", 1, 256 } } )
   ENDIF
   
   // Open with USE (RDDCDX driver)
   USE ( cData ) ALIAS "USR" SHARED
   ( "USR" )->( DbGoTop() )
   
   // Insert admin demo
   hRow := { => }
   hRow[ "id" ] := 1
   hRow[ "name" ] := "Admin Demo"
   hRow[ "pass" ] := "1234"
   hRow[ "roles" ] := "{sales:;purchases:;customers:search;show;edit;delete;recall;create}"
   ( "USR" )->( DbAppend() )
   ( "USR" )->( FieldPut( FieldPos( "id" ), hRow[ "id" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "name" ), hRow[ "name" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "pass" ), hRow[ "pass" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "roles" ), hRow[ "roles" ] ) )
   ( "USR" )->( DbCommit() )
   QOut( "  Added: Admin Demo (id=1)" )
   
   // Insert carles
   hRow := { => }
   hRow[ "id" ] := 2
   hRow[ "name" ] := "Carles Aubia"
   hRow[ "pass" ] := "1234"
   hRow[ "roles" ] := "{customers:search;show;purchases:}"
   ( "USR" )->( DbAppend() )
   ( "USR" )->( FieldPut( FieldPos( "id" ), hRow[ "id" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "name" ), hRow[ "name" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "pass" ), hRow[ "pass" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "roles" ), hRow[ "roles" ] ) )
   ( "USR" )->( DbCommit() )
   QOut( "  Added: Carles Aubia (id=2)" )
   
   // Insert maria
   hRow := { => }
   hRow[ "id" ] := 3
   hRow[ "name" ] := "Maria de la O"
   hRow[ "pass" ] := "1234"
   hRow[ "roles" ] := "{customers:search;show;edit;sales:}"
   ( "USR" )->( DbAppend() )
   ( "USR" )->( FieldPut( FieldPos( "id" ), hRow[ "id" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "name" ), hRow[ "name" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "pass" ), hRow[ "pass" ] ) )
   ( "USR" )->( FieldPut( FieldPos( "roles" ), hRow[ "roles" ] ) )
   ( "USR" )->( DbCommit() )
   QOut( "  Added: Maria de la O (id=3)" )
   
   ( "USR" )->( DbCloseArea() )
   QOut( "Migrate complete: users RDDCDX ready at data/users.cdb" )
   
RETURN NIL
