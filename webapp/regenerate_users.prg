/*
 * regenerate_users.prg - Regenerate users.dbf with test data
 * Uses Harbour core RDD functions (DBFCDX)
 * Complies with DEV-compliance.md: HIX framework only, no SQL, local git
 * ROLES field: C(255) with "role:ops" format matching CRUD example
 */

#include "hbclass.ch"

REQUEST DBFCDX

FUNCTION MAIN()
   LOCAL nI, nCount
   LOCAL aName := { "admin", "carles", "maria", "john", "jane" }
   LOCAL aPass := { "1234", "1234", "1234", "5678", "9012" }
   // ROLES: "role:ops" format matching CRUD example (hStore roles hash)
   // role name = first part, ops = semicolon-separated after ":"
   // ROLES format: "role:op1;op2;op3|role2:op1;op2" (pipe separates role pairs)
   LOCAL aRoles := { ;
      "customers:search;show;edit;delete;recall;create|users:search;show;edit;delete;create", ;  // full customer + users access
      "customers:search;show", ;                            // read-only
      "customers:search;show;edit", ;                      // edit access
      "customers:search;show", ;                           // read-only
      "customers:search;show;edit" }                       // edit access
   
   rddSetDefault( "DBFCDX" )
   
   QOut( "Creating users.dbf with test data..." )
   
   // Create new DBF with schema: id(N,10,0), name(C,40,0), pass(C,40,0), roles(C,255)
   DBCREATE( "/home/jack/Projects/pi-agent/webapp/data/users_new.dbf", ;
      { { "ID", "N", 10, 0 }, ;
        { "NAME", "C", 40, 0 }, ;
        { "PASS", "C", 40, 0 }, ;
        { "ROLES", "C", 255, 0 } } )
   
   // Open EXCLUSIVE to create index
   USE "/home/jack/Projects/pi-agent/webapp/data/users_new" ALIAS "NEWDBF" EXCLUSIVE
   ( "NEWDBF" )->( DbGoTop() )
   
   nCount := 5
   FOR nI := 1 TO nCount
      ( "NEWDBF" )->( DbAppend() )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ID" ), nI ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "NAME" ), aName[ nI ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "PASS" ), aPass[ nI ] ) )
      ( "NEWDBF" )->( FieldPut( FieldPos( "ROLES" ), aRoles[ nI ] ) )
      ( "NEWDBF" )->( DbCommit() )
      
      IF Mod( nI, 20 ) == 0
         QOut( "  Generated " + ltrim(str(nI)) + "/" + ltrim(str(nCount)) )
      ENDIF
   NEXT
   
   // Create index after data is appended (EXCLUSIVE mode required).
   // D-16: the tag key is Lower(name) so ModelUser's DbSeek( Lower(cUser) )
   // matches exactly regardless of how the name was typed into the DBF.
   INDEX ON Lower( field->name ) TAG name
   
   // Close the table to release the CDX file
   ( "NEWDBF" )->( DbCloseArea() )
   
   // Check users_new.cdx entries
   QOut( "users_new.cdx entries:" )
   USE "/home/jack/Projects/pi-agent/webapp/data/users_new" ALIAS "NEWDBF2" SHARED
   ( "NEWDBF2" )->( DbGoTop() )
   DO WHILE ! ( "NEWDBF2" )->( Eof() )
      QOut( "  " + ( "NEWDBF2" )->( FieldGet( FieldPos( "NAME" ) ) ) + " roles=" + ( "NEWDBF2" )->( FieldGet( FieldPos( "ROLES" ) ) ) )
      ( "NEWDBF2" )->( DbSkip() )
   ENDDO
   ( "NEWDBF2" )->( DbCloseArea() )
   
   // Replace old with new (backup existing files)
   IF File( "/home/jack/Projects/pi-agent/webapp/data/users.dbf" )
      FileCopy( "/home/jack/Projects/pi-agent/webapp/data/users.dbf", "/home/jack/Projects/pi-agent/webapp/data/users.dbf.bak", .T. )
   ENDIF
   IF File( "/home/jack/Projects/pi-agent/webapp/data/users.cdb" )
      FileCopy( "/home/jack/Projects/pi-agent/webapp/data/users.cdb", "/home/jack/Projects/pi-agent/webapp/data/users.cdb.bak", .T. )
   ENDIF
   IF File( "/home/jack/Projects/pi-agent/webapp/data/users.dbt" )
      FileCopy( "/home/jack/Projects/pi-agent/webapp/data/users.dbt", "/home/jack/Projects/pi-agent/webapp/data/users.dbt.bak", .T. )
   ENDIF
   
   // Delete old CDX first, then copy new one
   QOut( "Deleting old users.cdx..." )
   FileDelete( "/home/jack/Projects/pi-agent/webapp/data/users.cdx" )
   QOut( "Copying users_new.cdx to users.cdx..." )
   FileCopy( "/home/jack/Projects/pi-agent/webapp/data/users_new.cdx", "/home/jack/Projects/pi-agent/webapp/data/users.cdx", .T. )
   FileCopy( "/home/jack/Projects/pi-agent/webapp/data/users_new.dbf", "/home/jack/Projects/pi-agent/webapp/data/users.dbf", .T. )
   FileDelete( "/home/jack/Projects/pi-agent/webapp/data/users_new.dbf" )
   FileDelete( "/home/jack/Projects/pi-agent/webapp/data/users_new.cdx" )
   
   // Verify users.cdx entries
   QOut( "users.cdx entries after copy:" )
   USE "/home/jack/Projects/pi-agent/webapp/data/users" ALIAS "USR" SHARED
   ( "USR" )->( DbGoTop() )
   DO WHILE ! ( "USR" )->( Eof() )
      QOut( "  " + ( "USR" )->( FieldGet( FieldPos( "NAME" ) ) ) + " roles=" + ( "USR" )->( FieldGet( FieldPos( "ROLES" ) ) ) )
      ( "USR" )->( DbSkip() )
   ENDDO
   ( "USR" )->( DbCloseArea() )
   
   QOut( "Done. " + ltrim(str(nCount)) + " users created." )
   QOut( "Fields: ID, NAME, PASS, ROLES(C,255)" )
   QOut( "ROLES format: role:ops (matching CRUD example)" )
   QOut( "Backup files: users.dbf.bak, users.cdb.bak, users.dbt.bak" )
   
RETURN NIL
