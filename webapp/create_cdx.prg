#include "hbclass.ch"
#include "data_dir.prg"

FUNCTION MAIN()
   LOCAL cPath, cDbf, cCdx, cTag
   
   cPath := DataDir()
   IF cPath == NIL
      RETURN NIL
   ENDIF
   cDbf := cPath + "/customers.dbf"
   cCdx := cPath + "/customers.cdx"
   cTag := "first"
   
   // Open DBF with DBFCDX driver and create CDX
   USE ( cPath + "/customers" ) ALIAS "DBF" SHARED
   
   // Create index on FIRST field
   DBCreateIndex( cPath + "/customers.cdx", cTag, "UPPER( FIRST )" )
   
   ( "DBF" )->( DbCloseArea() )
   
   IF File( cCdx )
      QOut( "CDX created successfully: " + cCdx )
   ELSE
      QOut( "CDX creation failed." )
   ENDIF
   
RETURN NIL
