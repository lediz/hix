#include "hbclass.ch"
#include "data_dir.prg"

FUNCTION MAIN()
   LOCAL cPath, cDbf, cCdx, cTag, nI, hRow
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
   
   cPath := DataDir()
   IF cPath == NIL
      RETURN NIL
   ENDIF
   cDbf := cPath + "/customers.dbf"
   cCdx := cPath + "/customers.cdx"
   cTag := "first"
   
   // Create DBF with DBFCDX driver
   DBCREATE( cPath + "/customers.dbf", ;
      { { "ID", "N", 10, 0 }, ;
        { "FIRST", "C", 20, 0 }, ;
        { "LAST", "C", 20, 0 }, ;
        { "ADDRESS", "C", 120, 0 }, ;
        { "ZIP", "C", 10, 0 }, ;
        { "COUNTRY", "C", 50, 0 }, ;
        { "NOTES", "C", 70, 0 }, ;
        { "AGE", "N", 3, 0 } } )
   
   // Open DBF with DBFCDX driver
   USE ( cPath + "/customers.dbf" ) ALIAS "DBF" SHARED
   ( "DBF" )->( DbGoTop() )
   
   QOut( "DBF created. Fields: " )
   FOR nI := 1 TO ( "DBF" )->( FCount() )
      // FieldName(), not FieldGet(): the latter returns the field's value,
      // which made this line die with BASE/1081 ("   " + numeric).
      QOut( "   " + ( "DBF" )->( FieldName( nI ) ) )
   NEXT
   
   // Create index on FIRST field
   DBCreateIndex( cCdx, cTag, "UPPER( FIRST )" )
   
   // Insert 100 records
   FOR nI := 1 TO 100
      ( "DBF" )->( DbAppend() )
      ( "DBF" )->( FieldPut( FieldPos( "ID" ), nI ) )
      ( "DBF" )->( FieldPut( FieldPos( "FIRST" ), aFirst[ Mod( nI, 10 ) + 1 ] ) )
      ( "DBF" )->( FieldPut( FieldPos( "LAST" ), aLast[ Mod( nI, 10 ) + 1 ] ) )
      ( "DBF" )->( FieldPut( FieldPos( "ADDRESS" ), aStreet[ Mod( nI, 20 ) + 1 ] + " " + aCity[ Mod( nI, 10 ) + 1 ] + " " + aState[ Mod( nI, 10 ) + 1 ] ) )
      ( "DBF" )->( FieldPut( FieldPos( "ZIP" ), aZip[ Mod( nI, 10 ) + 1 ] ) )
      ( "DBF" )->( FieldPut( FieldPos( "COUNTRY" ), "US" ) )
      ( "DBF" )->( FieldPut( FieldPos( "NOTES" ), aNotes[ Mod( nI, 10 ) + 1 ] ) )
      ( "DBF" )->( FieldPut( FieldPos( "AGE" ), 25 + Mod( nI, 45 ) ) )
      ( "DBF" )->( DbCommit() )
      
      IF Mod( nI, 20 ) == 0
         QOut( "  Generated " + ltrim(str(nI)) + "/100" )
      ENDIF
   NEXT
   
   ( "DBF" )->( DbCloseArea() )
   
   QOut( "DBF created successfully: " + cDbf )
   QOut( "CDX created successfully: " + cCdx )
   QOut( "Tag: " + cTag )
   
RETURN NIL
