/*
 * probe_pwcost.prg - measure the cost of _PwHash() at several iteration counts
 *
 * Adhoc tool, lives inside the project folder (webapp/srs/DEV-compliance.md).
 * Harbour core only (hb_sha256), no contrib, no SQL.
 *
 * Purpose: PW_HASH_ITERATIONS is a login-time work factor.  Raising it raises
 * the cost of an offline dictionary attack, but it also raises the latency of
 * every POST /auth.  This probe reports both so the value can be chosen with
 * the HIX exec_timeout_ms (30000) in mind.
 *
 * Build: hbmk2 test/probe_pwcost.hbp   ->  ./probe_pwcost
 */

#DEFINE PW_SALT_LEN 32

STATIC FUNCTION _PwHash( cPass, cSalt, nIter )

   LOCAL cHash := hb_sha256( cSalt + cPass )
   LOCAL nI

   FOR nI := 1 TO nIter
      cHash := hb_sha256( cSalt + cHash )
   NEXT

RETURN cHash


FUNCTION MAIN()

   LOCAL aIter := { 1000, 5000, 10000, 20000, 50000 }
   LOCAL cSalt := SubStr( hb_sha256( "salt-probe" ), 1, PW_SALT_LEN )
   LOCAL nI, nK, nMs, nTotal

   ? "iterations   digest                          ms/hash"
   FOR nI := 1 TO Len( aIter )
      nMs    := hb_MilliSeconds()
      nTotal := 0
      FOR nK := 1 TO 5
         nTotal := Len( _PwHash( "9012abcd", cSalt, aIter[ nI ] ) )   // keep the result live
      NEXT
      nTotal := hb_MilliSeconds() - nMs
      ? Pad( hb_NTOS( aIter[ nI ] ), 10, .T. ), ;
        Pad( _PwHash( "9012abcd", cSalt, aIter[ nI ] ), 34 ), ;
        Pad( hb_NTOS( nTotal / 5 ), 10, .T. )
   NEXT

RETURN NIL
