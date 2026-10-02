#include "hbclass.ch"

FUNCTION MAIN()
   LOCAL cPath, cDbf, cCdx, cTag
   
   cPath := "/home/jack/Projects/pi-agent/webapp/data"
   cDbf := cPath + "/customers.dbf"
   cCdx := cPath + "/customers.cdx"
   cTag := "first"
   
   // Open DBF with DBFCDX driver and create CDX
   USE "/home/jack/Projects/pi-agent/webapp/data/customers" ALIAS "DBF" SHARED
   
   // Create index on FIRST field
   DBCreateIndex( "/home/jack/Projects/pi-agent/webapp/data/customers.cdx", cTag, "UPPER( FIRST )" )
   
   ( "DBF" )->( DbCloseArea() )
   
   IF File( cCdx )
      QOut( "CDX created successfully: " + cCdx )
   ELSE
      QOut( "CDX creation failed." )
   ENDIF
   
RETURN NIL
