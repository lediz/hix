/*
 * migrate_dbf.prg - Migrate customers.dbf to new schema
 * Uses Harbour core RDD functions (DBCREATE, DBUSEAREA, DBAPPEND, etc.)
 */

#include "hbclass.ch"
#include "data_dir.prg"

FUNCTION MAIN()
   LOCAL hRow, nRecCount, nI, nFieldPos
   LOCAL cPath

   cPath := DataDir()
   IF cPath == NIL
      RETURN NIL
   ENDIF
   
   // Open old DBF using USE with literal path
   USE ( cPath + "/customers" ) ALIAS "OLDBEF" SHARED
   ( "OLDBEF" )->( DbGoTop() )
   nRecCount := ( "OLDBEF" )->( RecCount() )
   
   QOut( "Migrating " + ltrim(str(nRecCount)) + " records..." )
   
   // Create new DBF with new schema using DBCREATE
   DBCREATE( cPath + "/customers_new.dbf", ;
      { { "ID", "N", 10, 0 }, ;
        { "FIRST", "C", 20, 0 }, ;
        { "LAST", "C", 20, 0 }, ;
        { "ADDRESS", "C", 120, 0 }, ;
        { "ZIP", "C", 10, 0 }, ;
        { "COUNTRY", "C", 50, 0 }, ;
        { "NOTES", "C", 70, 0 }, ;
        { "AGE", "N", 3, 0 } } )
   
   // Open new DBF
   USE ( cPath + "/customers_new" ) ALIAS "NEWDBF" SHARED
   ( "NEWDBF" )->( DbGoTop() )
   
   nI := 0
   DO WHILE ( "OLDBEF" )->( !Eof() )
      nI++
      hRow := { => }
      hRow[ "ID" ] := ( "OLDBEF" )->( FieldGet( FieldPos( "ID" ) ) )
      hRow[ "FIRST" ] := ( "OLDBEF" )->( FieldGet( FieldPos( "FIRST" ) ) )
      hRow[ "LAST" ] := ( "OLDBEF" )->( FieldGet( FieldPos( "LAST" ) ) )
      hRow[ "ADDRESS" ] := AllTrim( ( "OLDBEF" )->( FieldGet( FieldPos( "STREET" ) ) ) ) + ;
         " " + AllTrim( ( "OLDBEF" )->( FieldGet( FieldPos( "CITY" ) ) ) ) + ;
         " " + AllTrim( ( "OLDBEF" )->( FieldGet( FieldPos( "STATE" ) ) ) )
      hRow[ "ZIP" ] := ( "OLDBEF" )->( FieldGet( FieldPos( "ZIP" ) ) )
      hRow[ "COUNTRY" ] := "US"
      hRow[ "NOTES" ] := ( "OLDBEF" )->( FieldGet( FieldPos( "NOTES" ) ) )
      hRow[ "AGE" ] := ( "OLDBEF" )->( FieldGet( FieldPos( "AGE" ) ) )
      
      ( "NEWDBF" )->( DbAppend() )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ID" ), hRow[ "ID" ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "FIRST" ), hRow[ "FIRST" ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "LAST" ), hRow[ "LAST" ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ADDRESS" ), hRow[ "ADDRESS" ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ZIP" ), hRow[ "ZIP" ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "COUNTRY" ), hRow[ "COUNTRY" ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "NOTES" ), hRow[ "NOTES" ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "AGE" ), hRow[ "AGE" ] ) )
      ( "NEWDBF" )->( DbCommit() )
      
      ( "OLDBEF" )->( DbSkip() )
      
      IF Mod( nI, 100 ) == 0
         QOut( "  Migrated " + ltrim(str(nI)) + "/" + ltrim(str(nRecCount)) )
      ENDIF
   ENDDO
   
   ( "OLDBEF" )->( DbCloseArea() )
   ( "NEWDBF" )->( DbCloseArea() )
   
   // Replace old with new
   FileCopy( cPath + "/customers_new.dbf", cPath + "/customers.dbf", .T. )
   FileCopy( cPath + "/customers_new.cdx", cPath + "/customers.cdx", .T. )
   FileDelete( cPath + "/customers_new.dbf" )
   FileDelete( cPath + "/customers_new.cdx" )
   
   QOut( "Migration complete. " + ltrim(str(nI)) + " records migrated." )
   
RETURN NIL
