/*
 * probe_seek.prg - diagnostic for the users.dbf 'name' CDX tag (D-16)
 * Prints, for a set of test keys, which record DbSeek lands on and whether
 * the exact case-insensitive guard accepts it.
 * Adhoc tool: lives inside the project folder (DEV-compliance.md).
 */

#include "../data_dir.prg"

REQUEST DBFCDX

FUNCTION MAIN()
   LOCAL aKeys := { "admin", "ADMIN", "carle", "carles", "CARLES", "zed", "nobody" }
   LOCAL cData
   LOCAL cSeek, cFound

   cData := DataDir()
   IF cData == NIL
      RETURN NIL
   ENDIF
   cData := cData + "/users"

   rddSetDefault( "DBFCDX" )
   USE ( cData ) INDEX ( cData ) ALIAS "USR" SHARED

   ? "traversal order (focused index):"
   ( "USR" )->( DbGoTop() )
   DO WHILE ! ( "USR" )->( Eof() )
      ? "  NAME=" + AllTrim( ( "USR" )->( FieldGet( FieldPos( "NAME" ) ) ) )
      ( "USR" )->( DbSkip() )
   ENDDO

   ? ""
   ? "DbSeek results:"
   FOR EACH cSeek IN aKeys
      cSeek := Lower( cSeek )
      ( "USR" )->( DbGoTop() )
      ( "USR" )->( DbSeek( cSeek ) )
      IF ( "USR" )->( Eof() )
         ? "  seek '" + cSeek + "' -> no record (Eof)"
      ELSE
         cFound := AllTrim( ( "USR" )->( FieldGet( FieldPos( "NAME" ) ) ) )
         ? "  seek '" + cSeek + "' -> NAME='" + cFound + "'  exactmatch=" + ;
           iif( Lower( cFound ) == cSeek, "YES", "NO" )
      ENDIF
   NEXT

   ( "USR" )->( DbCloseArea() )

   ? ""
   ? "Harbour string comparison semantics (SET EXACT default = .F.):"
   ? '  carles =  carle -> ' + iif( 'carles' = 'carle',  'T', 'F' )
   ? '  carles == carle -> ' + iif( 'carles' == 'carle', 'T', 'F' )
   ? '  carles !=  carle -> ' + iif( 'carles' != 'carle', 'T', 'F' )
   ? '  12345678 =  1234 -> ' + iif( '12345678' = '1234',  'T', 'F' )
   ? '  12345678 == 1234 -> ' + iif( '12345678' == '1234', 'T', 'F' )
RETURN NIL
