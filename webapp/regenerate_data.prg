/*
 * regenerate_data.prg - Regenerate customers.dbf with test data
 * Uses Harbour core RDD functions
 */

#include "hbclass.ch"

REQUEST DBFCDX

FUNCTION MAIN()
   LOCAL cPath, nI, nCount
   LOCAL aFirst := { "John", "Jane", "Bob", "Alice", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry" }
   LOCAL aLast := { "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez" }
   LOCAL aStreet := { "123 Main St", "456 Oak Ave", "789 Pine Rd", "321 Elm Blvd", "654 Maple Dr", ;
      "987 Cedar Ln", "147 Birch Way", "258 Walnut Ct", "369 Spruce Pl", "741 Ash St", ;
      "852 Willow Rd", "963 Poplar Ave", "159 Hickory Ln", "267 Sycamore Dr", "378 Magnolia Blvd", ;
      "489 Chestnut Way", "591 Dogwood Ct", "612 Redwood Pl", "723 Sequoia St", "834 Cypress Rd" }
   LOCAL aCity := { "Springfield", "Riverside", "Lakeside", "Hillside", "Fairview", ;
      "Brookside", "Woodside", "Meadow", "Glenwood", "Pineville" }
   LOCAL aState := { "IL", "CA", "TX", "NY", "FL", "OH", "PA", "VA", "WA", "CO" }
   LOCAL aZip := { "62701", "92501", "75001", "10001", "33101", "43001", "19001", "22001", "98001", "80001" }
   LOCAL aNotes := { "Regular customer", "VIP client", "New account", "Pending review", "Inactive", ;
      "Active", "Archived", "Special order", "Bulk buyer", "Referral" }
   
   cPath := "/home/jack/Projects/pi-agent/webapp/data"

   rddSetDefault( "DBFCDX" )
   
   // Create new DBF with new schema using DBFNTX driver
   DBCREATE( cPath + "/customers_new.dbf", ;
      { { "ID", "N", 10, 0 }, ;
        { "FIRST", "C", 20, 0 }, ;
        { "LAST", "C", 20, 0 }, ;
        { "ADDRESS", "C", 120, 0 }, ;
        { "ZIP", "C", 10, 0 }, ;
        { "COUNTRY", "C", 50, 0 }, ;
        { "NOTES", "C", 70, 0 }, ;
        { "AGE", "N", 3, 0 } } )
   
   USE "/home/jack/Projects/pi-agent/webapp/data/customers_new" ALIAS "NEWINDEX" EXCLUSIVE
   INDEX ON field->first TAG first
   ( "NEWINDEX" )->( DbCloseArea() )

   USE "/home/jack/Projects/pi-agent/webapp/data/customers_new" ALIAS "NEWDBF" SHARED
   ( "NEWDBF" )->( DbGoTop() )
   
   nCount := 100
   QOut( "Generating " + ltrim(str(nCount)) + " records..." )
   
   FOR nI := 1 TO nCount
      ( "NEWDBF" )->( DbAppend() )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ID" ), nI ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "FIRST" ), aFirst[ Mod( nI, 10 ) + 1 ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "LAST" ), aLast[ Mod( nI, 10 ) + 1 ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ADDRESS" ), aStreet[ Mod( nI, 20 ) + 1 ] + " " + aCity[ Mod( nI, 10 ) + 1 ] + " " + aState[ Mod( nI, 10 ) + 1 ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ZIP" ), aZip[ Mod( nI, 10 ) + 1 ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "COUNTRY" ), "US" ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "NOTES" ), aNotes[ Mod( nI, 10 ) + 1 ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "AGE" ), 25 + Mod( nI, 45 ) ) )
      ( "NEWDBF" )->( DbCommit() )
      
      IF Mod( nI, 20 ) == 0
         QOut( "  Generated " + ltrim(str(nI)) + "/" + ltrim(str(nCount)) )
      ENDIF
   NEXT
   
   ( "NEWDBF" )->( DbCloseArea() )
   
   // Replace old with new
   FileCopy( cPath + "/customers_new.dbf", cPath + "/customers.dbf", .T. )
   FileCopy( cPath + "/customers_new.cdx", cPath + "/customers.cdx", .T. )
   FileDelete( cPath + "/customers_new.dbf" )
   FileDelete( cPath + "/customers_new.cdx" )
   
   QOut( "Data regeneration complete. " + ltrim(str(nCount)) + " records created." )
   QOut( "Fields: ID, FIRST, LAST, ADDRESS, ZIP, COUNTRY, NOTES, AGE" )
   
RETURN NIL
