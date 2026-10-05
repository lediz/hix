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

// Fixed salt used by ModelUser() on the "this username does not exist" path.
// The KDF must cost the same whether the name is real or not: skipping the
// 10 000 rounds for unknown names made response time a user-enumeration
// oracle (~4 ms of difference, PENTEST-REPORT.md §6).  It is not a secret and
// no digest is ever stored with it.
#DEFINE PW_DUMMY_SALT    "0123456789abcdef0123456789abcdef"
// Work factor.  Measured on this machine with test/probe_pwcost.prg
// (hb_sha256, Harbour core, no contrib):
//     1000 -> 0.4 ms      10000 -> 4.0 ms      50000 -> 17.8 ms   per hash
// 10000 raises the offline brute-force cost 10x over the D-07 baseline while a
// login still costs ~4 ms, far inside hix.json exec_timeout_ms (30000).
// Changing this value invalidates every digest already stored in users.dbf:
// re-seed with regenerate_users.prg afterwards.
#DEFINE PW_HASH_ITERATIONS 10000

// Per-user salt, from a CSPRNG.
// hb_RandStr() is Harbour core RTL (src/rtl/hbrand.c -> hb_random_block ->
// hb_arc4random_buf, arc4random seeded from /dev/urandom), so a real random
// source is available without the hbct contrib (hb_rand) and without touching
// app.hbp.  Verified by test/probe_entropy.prg: 5000 seeds, 0 duplicates,
// uniform output.
//
// The previous version derived the salt from name + timestamp + Seconds() +
// RecCount().  That was predictable: an attacker who knows roughly when an
// account was created and can read the user list can reconstruct the salt,
// which turns a per-user offline attack into a precomputable one.
//
// 32 random bytes -> SHA-256 -> 64 hex, truncated to PW_SALT_LEN (32 hex =
// 128 bits of salt entropy).  A salt is stored in the clear next to the
// digest and does not have to be secret; it only has to be unique and
// unpredictable, so digests cannot be compared, batched or precomputed.
STATIC FUNCTION _PwSalt()

RETURN SubStr( hb_sha256( hb_RandStr( 32 ) ), 1, PW_SALT_LEN )


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
