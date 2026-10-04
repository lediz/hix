FUNCTION MAIN()
   LOCAL c := hb_sha256( "abc" )
   LOCAL nI, cOut := ""
   FOR nI := 1 TO Len( c )
      cOut += ltrim( str( Asc( SubStr( c, nI, 1 ) ) ) ) + " "
   NEXT
   ? "sha256 len=", Len( c )
   ? "sha256 bytes:", cOut
   ? "md5 len=", Len( hb_MD5("abc") ), " val=", hb_MD5("abc")
RETURN NIL
