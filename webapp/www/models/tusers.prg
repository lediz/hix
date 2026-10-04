// --------------------------------------------------------------------------------
// TUsers — DAL for users.dbf (persistent user management)
// Schema: ID(N,10) | NAME(C,40) | PASS(C,40) | ROLES(C,255)
// CDX index: NAME tag 'name' (case-insensitive via Lower())
// Complies with DEV-compliance.md: HIX framework only, no SQL, local git
// --------------------------------------------------------------------------------

FUNCTION TUsers()

   LOCAL oUsers := UDbf()

   oUsers:cPath    := hb_dirbase() + UConfig( "paths", "data", "data" )
   oUsers:cDbf     := 'users.dbf'
   oUsers:cCdx     := 'users.cdx'
   oUsers:cTag     := 'name'

   oUsers:Open()

RETURN oUsers
