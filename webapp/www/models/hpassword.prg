// --------------------------------------------------------------------------------
// hpassword.prg — password hashing helpers (defect D-07)
//
// Harbour core only: hb_sha256() returns 64 lowercase hex chars and needs no
// contrib library, so it links into the HIX server without touching app.hbp.
//
// Storage model in users.dbf:
//   SALT C(32)   per-user hex salt, generated at create / password change
//   PASS C(128)  hex( SHA256( salt + SHA256( salt + ... (salt + password) ) ) )
//                PW_HASH_ITERATIONS inner rounds, raises brute-force cost
//
// Plaintext passwords never reach the DBF, the flash, the session or a view.
// --------------------------------------------------------------------------------

#include 'hbclass.ch'

#DEFINE PW_SALT_LEN      32
// Work factor.  Measured on this machine with test/probe_pwcost.prg
// (hb_sha256, Harbour core, no contrib):
//     1000 -> 0.4 ms      10000 -> 4.0 ms      50000 -> 17.8 ms   per hash
// 10000 raises the offline brute-force cost 10x over the D-07 baseline while a
// login still costs ~4 ms, far inside hix.json exec_timeout_ms (30000).
// Changing this value invalidates every digest already stored in users.dbf:
// re-seed with regenerate_users.prg afterwards.
#DEFINE PW_HASH_ITERATIONS 10000

// Per-user salt.  Harbour core exposes no CSPRNG without the hbct contrib
// (hb_rand), and app.hbp must not be changed, so the salt is derived from
// per-request entropy instead.  That is acceptable: a salt is stored in the
// clear next to the digest and does not have to be secret, it only has to be
// unique per user so digests cannot be compared or precomputed.  The cost of
// an offline attack is dominated by PW_HASH_ITERATIONS.
STATIC FUNCTION _PwSalt( cName )

   LOCAL cSeed

   cSeed := 'pw.salt|' + AllTrim( cName ) + '|' + ;
            hb_TToS( hb_DateTime() ) + '|' + ;
            hb_NTOS( Seconds() )     + '|' + ;
            hb_NTOS( RecCount() )

RETURN SubStr( hb_sha256( cSeed ), 1, PW_SALT_LEN )


// Salted, iterated SHA-256.  Returns 64 hex characters.
STATIC FUNCTION _PwHash( cPass, cSalt )

   LOCAL cHash := hb_sha256( cSalt + cPass )
   LOCAL nI

   FOR nI := 1 TO PW_HASH_ITERATIONS
      cHash := hb_sha256( cSalt + cHash )
   NEXT

RETURN cHash


// Constant-time-ish comparison of two hex digests.
STATIC FUNCTION _PwMatch( cStored, cCandidate )

   LOCAL cA, cB, nI, lSame := .T.

   cA := Lower( AllTrim( cStored ) )
   cB := Lower( AllTrim( cCandidate ) )

   IF Len( cA ) != Len( cB )
      RETURN .F.
   ENDIF

   FOR nI := 1 TO Len( cA )
      IF SubStr( cA, nI, 1 ) != SubStr( cB, nI, 1 )
         lSame := .F.   // keep scanning: do not leak the matching prefix length
      ENDIF
   NEXT

RETURN lSame
