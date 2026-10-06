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

   // D-05 / D-07: credentials must never reach a view.  HIX_DBF:Row() builds
   // hRow from ::hFields, so hiding PASS/SALT keeps them out of every hRow
   // returned by GetRecno()/LoadAll().
   oUsers:Hide( { 'pass', 'salt' } )

   oUsers:Open()

RETURN oUsers
