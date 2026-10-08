/* ---------------------------------------------------------
 File.......: TUsers.prg
 Description: The credential store - one DBF + one CDX, opened
              through the framework's UDbf() with the RDD driver
              www/config.json names ("dbf" -> "rddname": DBFCDX).

              The store is data/users.dbf:

                ID     N(10,0)   the persisted PK. Never the recno:
                                  Pack() renumbers records and a public
                                  id must not move.
                NAME   C(40)     the login identity (D-09: a duplicate
                                  is refused outright by the module)
                PASS   C(128)    64 hex of 10 000 rounds of salted
                                  SHA-256 (www/models/hpassword.prg,
                                  D-07) - never the password
                SALT   C(32)     32 hex from a CSPRNG, per account
                ROLES  C(255)    the scope string the middlewares read,
                                  "role:ops;ops|role:ops"

              One CDX tag: 'name', keyed on Lower( field->name ). That
              tag is what makes the login lookup a seek instead of a
              scan, and what makes it case-insensitive by construction
              (D-16) - a DBF has no collation to lean on.

              Complies with DEV-compliance.md: HIX framework and Harbour
              only, no SQL anywhere, no engine started.
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION TUsers()

   LOCAL oUsers  := UDbf()

   oUsers:cPath  := hb_dirbase() + UConfig( "paths", "data", "data" )
   oUsers:cDbf   := 'users.dbf'
   oUsers:cCdx   := 'users.cdx'
   oUsers:cTag   := 'name'

   oUsers:Open()

return oUsers

// -------------------------------------------------- //
