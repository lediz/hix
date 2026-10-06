/*
 * probe_entropy.prg - verify the CSPRNG primitives used for salts and app keys
 *
 * Adhoc tool, inside the project folder (webapp/srs/DEV-compliance.md).
 * Harbour core only: hb_RandStr() lives in src/rtl/hbrand.c and routes to
 * hb_arc4random_buf() (arc4random, seeded from /dev/urandom), so it needs no
 * hbct contrib and no change to app.hbp.
 *
 * Checks:
 *   1. hb_RandStr() is linked and callable
 *   2. hb_sha256() survives a binary (NUL / high-byte) seed and stays 64-hex
 *   3. distinct calls never repeat, and the hex output is uniform enough
 *
 * Build: hbmk2 probe_entropy.hbp && ./probe_entropy
 */

STATIC FUNCTION _HexSeed( nBytes )

   LOCAL cSeed := hb_RandStr( nBytes )
   LOCAL cOut  := hb_sha256( cSeed )
   LOCAL nI, nA

   // Reject anything that is not 64 lowercase hex characters.
   IF Len( cOut ) != 64
      RETURN ""
   ENDIF

   FOR nI := 1 TO 64
      nA := Asc( SubStr( cOut, nI, 1 ) )
      IF ! ( ( nA >= Asc( '0' ) .AND. nA <= Asc( '9' ) ) .OR. ;
             ( nA >= Asc( 'a' ) .AND. nA <= Asc( 'f' ) ) )
         RETURN ""
      ENDIF
   NEXT

RETURN cOut


FUNCTION MAIN()

   LOCAL hSeen := { => }
   LOCAL nI, cK, nBad := 0, nDup := 0
   LOCAL nH0 := 0, nH15 := 0

   ? "hb_RandStr linked:", ValType( hb_RandStr( 32 ) ) == "C", "len=", Len( hb_RandStr( 32 ) )

   FOR nI := 1 TO 5000
      cK := _HexSeed( 32 )
      IF Empty( cK )
         nBad++
      ELSE
         IF hb_HHasKey( hSeen, cK )
            nDup++
         ENDIF
         hSeen[ cK ] := .T.
         IF SubStr( cK, 1, 1 ) == "0"
            nH0++
         ENDIF
         IF SubStr( cK, 1, 1 ) == "f"
            nH15++
         ENDIF
      ENDIF
   NEXT

   ? "seeds generated  :", 5000
   ? "malformed        :", nBad
   ? "duplicates       :", nDup
   ? "unique           :", Len( hSeen )
   ? "first-hex '0'    :", nH0
   ? "first-hex 'f'    :", nH15
   ? "sample seed      :", _HexSeed( 32 )

RETURN NIL
