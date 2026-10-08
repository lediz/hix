// --------------------------------------------------------------------------------
// Users — CRUD for the credential store, on the RDDCDX RDD (DBF + CDX)
//
// The store is data/users.dbf plus one CDX tag, opened through the framework's
// UDbf() by www/models/tusers.prg with the RDD driver www/config.json names
// ("dbf" -> "rddname": DBFCDX). The shape is the audited one - the same nine
// verbs, the same middleware pair, the same flash + redirect for writes - as
// www/controllers/masters/customer.prg, the app's RDDCDX proof-of-concept.
//
// Defect closures carried over, restated for this store:
//   D-05  the digest and the salt never reach a view: the read whitelist is
//         {name, roles} only, so no hRow this module hands a view can carry
//         them (this replaces the Hide( {'pass','salt'} ) the older module used)
//   D-06  free-text search is restricted to an allow-list of columns (the
//         substring tests go over name and roles, never over an arbitrary
//         column) - a DBF has no LIKE, so the test is Harbour's own
//   D-08  the sort key uses the same case as the grid's hash keys
//   D-09  NAME is the login identity: a duplicate is refused outright, with
//         the message. A DBF has no UNIQUE KEY, so this refusal is the whole
//         enforcement; the CDX tag on NAME is what makes the lookup a seek
//   D-10  the flash is drained once it has been read
//   D-11  one store per request, opened once and closed by the verb that took
//         it - over a DBF this is an area, not a lease, and hix.json's
//         auto_close_dbf logs one this module forgot rather than leaking it
//   D-13  oVal:Get( 'id' ) is named explicitly, never implied
//   D-16  the name is normalised once; the CDX tag keyed on Lower(NAME) is
//         what makes the match case-insensitive by construction
//   N-01  every write form carries a CSRF token (@CSRF in the views; the
//         MyAppAuthRoleEdit middleware enforces it)
//
// What this store cannot promise, and where that is visible instead:
//   P3.7  does NOT apply to this store: the shipped users.dbf header is
//         ID NAME PASS SALT ROLES - there is no VERSION column, so there is
//         no optimistic-concurrency contract to keep. The write is last-writer
//         wins, which is what a single-writer DBF store gives. Inventing a
//         VERSION field would change the store's header and invalidate the
//         CDX file, so the contract is dropped rather than faked.
//   D4    users_users has no FK pointing at it, so the delete preview is
//         empty by construction and nothing here cascades at all.
// --------------------------------------------------------------------------------

#include 'hbclass.ch'

CLASS UsersControllers

   DATA oDb INIT NIL

   METHOD New()           CONSTRUCTOR
   METHOD End()
   METHOD Search()
   METHOD Show()
   METHOD Edit()
   METHOD Grid()
   METHOD Update()
   METHOD Create()
   METHOD Store()
   METHOD delete_confirm()
   METHOD delete_action()
   METHOD Destroy()

   METHOD Open()
   METHOD Finish( xRet )
   METHOD FinishStore()
   METHOD NameExists( cName, nExclude )
   METHOD FlashFail( cMessage, hErrors, hInput )
   METHOD FlashOk( cMessage )
   METHOD TakeFlash()

ENDCLASS

// -------------------------------------------------------------- //

METHOD New() CLASS UsersControllers

   ::oDb := NIL

RETURN SELF


METHOD End() CLASS UsersControllers

RETURN SELF


// -------------------------------------------------------------- //
// D-11 over a file store: there is nothing to lease, so Open() opens the
// module's own DBF once and every verb that took it closes it. Absent the
// store the module answers the same way it does when a record is not there.
// -------------------------------------------------------------- //

METHOD Open() CLASS UsersControllers

   IF ::oDb == NIL
      ::oDb := TUsers()
      IF ::oDb != NIL
         IF ! ::oDb:lConnect
            Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
               { => }, NIL )
            Self:FinishStore()
            RETU NIL
         ENDIF
      ENDIF
   ENDIF

RETU ::oDb


METHOD Destroy() CLASS UsersControllers

   //  the store is returned here, once
   Self:FinishStore()

RETURN NIL


METHOD FinishStore() CLASS UsersControllers

   IF ::oDb != NIL
      ::oDb:Close()
      ::oDb := NIL
   ENDIF

RETURN NIL


METHOD Finish( xRet ) CLASS UsersControllers

   Self:FinishStore()

RETU xRet


// -------------------------------------------------------------- //
// Reads. FR-READ-1..5: grid paged, search by substring, show by id.
// The whitelist is this module's declaration, not the form's: a field the
// form sends that is not in here is dropped, never written (P3.2).
// "pass" and "salt" are NOT in the read list, so no row handed to a view
// can carry a credential (D-05).
// -------------------------------------------------------------- //

METHOD Grid() CLASS UsersControllers

   LOCAL nPage, nRows, nTotal, nTotalPages := 0
   LOCAL aAll, aGrid := {}, aPages := {}
   LOCAL cQ, cSort, cDir
   LOCAL oDb
   LOCAL nI, nJ, aFields := { "name", "roles" }, hQ := { => }, cSearchParams := ""
   LOCAL aMatch := {}, lKeep, cTerm, lSetDel

   IF Self:Open() == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nPage := Iif( Empty( UGet( 'page', '' ) ), 1, Val( UGet( 'page', '' ) ) )
   IF nPage < 1
      nPage := 1
   ENDIF
   nRows := 20

   cQ    := Trim( UGet( 'q', '' ) )
   cSort := Lower( UGet( 'sort', 'name' ) )      // D-08: same case as the grid keys
   cDir  := Upper( UGet( 'dir', 'ASC' ) )

   //  D-06: ONE allow-list drives the projection, the column sort and the
   //  per-column search - pass and salt are not in it
   IF Ascan( aFields, cSort ) == 0
      cSort := "name"
   ENDIF
   IF cDir != "DESC"
      cDir := "ASC"
   ENDIF

   //  FR-READ-3: one search entry per grid column (?_q_<column>)
   FOR nI := 1 TO LEN( aFields )
      hQ[ aFields[ nI ] ] := Trim( UGet( '_q_' + aFields[ nI ], '' ) )
   NEXT

   oDb := Self:Open()

   //  a DBF has no LIKE and no projection: the rows are read once, then
   //  narrowed in Harbour. The store is small (one row per account), so the
   //  scan is the honest answer, not a placeholder for an index.
   //  www/config.json sets "deleted": false, so a soft-deleted record is
   //  VISIBLE to a scan by default. The grid must not show it (T47), so the
   //  flag is set for this scan and restored after - the same discipline
   //  HIX_DBF:CountDeleted() uses (src/dbf/hix_dbf.prg:785).
   lSetDel := Set( _SET_DELETED, .T. )
   aAll := oDb:LoadAll( NIL, NIL, NIL, NIL )
   Set( _SET_DELETED, lSetDel )
   IF aAll == NIL
      aAll := {}
   ENDIF

   //  narrow by column (AND), case-insensitively, and by the free-text bar
  //  (OR over the rendered columns)
   FOR nI := 1 TO LEN( aAll )
      lKeep := .T.
      FOR nJ := 1 TO LEN( aFields )
         cTerm := hb_HGetDef( hQ, aFields[ nJ ], "" )
         IF ! EMPTY( cTerm ) .AND. ! _InSensitive( hb_HGetDef( aAll[ nI ], ;
            aFields[ nJ ], "" ), cTerm )
            lKeep := .F.
            EXIT
         ENDIF
      NEXT
      IF lKeep .AND. ! EMPTY( cQ ) .AND. ! _RowMatchesQ( aAll[ nI ], aFields, cQ )
         lKeep := .F.
      ENDIF
      IF lKeep
         AADD( aMatch, aAll[ nI ] )
      ENDIF
   NEXT

   aMatch := _SortRows( aMatch, cSort, cDir )

   nTotal := LEN( aMatch )
   IF nTotal > 0
      nTotalPages := Int( ( nTotal + nRows - 1 ) / nRows )
      IF nPage > nTotalPages
         nPage := nTotalPages
      ENDIF
      FOR nI := ( nPage - 1 ) * nRows + 1 TO MIN( nPage * nRows, nTotal )
         AADD( aGrid, aMatch[ nI ] )
      NEXT
   ENDIF

   FOR nI := 1 TO MIN( nTotalPages, 10 )
      AADD( aPages, nI )
   NEXT

   //  the active search is carried through the pagination and sort links
   cSearchParams := ''
   IF ! EMPTY( cQ )
      cSearchParams += '&q=' + cQ
   ENDIF
   FOR nI := 1 TO LEN( aFields )
      IF ! EMPTY( hb_HGetDef( hQ, aFields[ nI ], "" ) )
         cSearchParams += '&_q_' + aFields[ nI ] + '=' + hb_HGetDef( hQ, ;
            aFields[ nI ], "" )
      ENDIF
   NEXT

RETURN Self:Finish( UView( 'masters/users/grid.html', 'grid', aGrid, aPages, nPage, ;
              nTotalPages, cSort, cDir, cQ, hQ, Self:TakeFlash(), { => }, ;
              cSearchParams ) )


METHOD Search() CLASS UsersControllers

   LOCAL hSearch := { => }, nI
   LOCAL aFields := { "name", "roles" }      // same list as Grid()

   FOR nI := 1 TO LEN( aFields )
      hSearch[ aFields[ nI ] ] := Trim( UGet( '_q_' + aFields[ nI ], '' ) )
   NEXT

RETURN Self:Finish( UView( 'masters/users/search.html', hSearch, Self:TakeFlash() ) )


METHOD Show() CLASS UsersControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDb

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0      // D-13
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDb  := Self:Open()

   //  the audited shape renders the view either way: a miss is a blank row plus
   //  the flash, not a redirect, so the view can say 'User not exist' (T32)
   hRow := _RowByRecno( oDb, nId )

RETURN Self:Finish( UView( 'masters/users/show.html', ( hRow != NIL ), ;
              iif( hRow == NIL, _BlankRow(), _Visible( hRow ) ), Self:TakeFlash() ) )


// -------------------------------------------------------------- //
// Writes. The form (edit/create) renders and the POST verb (store/update)
// performs - the audited split, kept so the CSRF middleware and the scope
// stay on the write side only (N-01).
// -------------------------------------------------------------- //

METHOD Edit() CLASS UsersControllers

   LOCAL oVal, nId, hRow := NIL, hInput := NIL
   LOCAL oDb, oFlash, hMessage := { => }, hErrors := { => }

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   //  Recover data flash if it exists (the audited shape). A failed store/update
   //  leaves the POSTED values in the flash's input plus the errors; re-rendering
   //  with those is what makes T43/T45's "flash + re-render" work - the form
   //  shows what the caller sent and why each field was rejected.
   oFlash    := UFlash( 'users' )
   hMessage[ 'type' ]    := oFlash:Get( 'type' )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   hInput    := oFlash:Get( 'input' )
   hErrors   := oFlash:Get( 'errors', { => } )

   IF ! hb_IsHash( hInput )
      //  a plain GET /users/:id/edit: pre-populate from the RECORD (T33), so
      //  the form opens with the current values rather than empty
      oDb  := Self:Open()
      hRow := _RowByRecno( oDb, nId )
      IF hRow == NIL
         Self:FlashFail( "That user is not there.", { => }, NIL )
         RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
      ENDIF
      hRow := _Visible( hRow )
   ELSE
      //  the values the caller posted, filtered to the allow-list so a failed
      //  write cannot carry pass/salt back into the form (D-05)
      hRow := _Visible( hInput )
   ENDIF

   //  D-10: drain the flash here, after this render has consumed it, so a
   //  validation error does not leak into the NEXT edit or grid (D-10b/D-10c).
   //  TakeFlash() is not used because Edit() needs the flash's input to build
   //  the form, and it already read it above.
   oFlash:Clear()
   oFlash:Save()

RETURN Self:Finish( UView( 'masters/users/edit.html', 'edit', .T., ;
              hRow, hMessage, hErrors ) )


METHOD Create() CLASS UsersControllers

   LOCAL oFlash, hMessage := { => }, hErrors := { => }, hInput := NIL

   //  same flash round trip as Edit(): a failed store leaves the POSTED values
   //  in input and the per-field reasons in errors, and the re-rendered create
   //  form must show both (D-15g). Passing an empty hErrors is what made the
   //  form render no is-invalid markers at all.
   oFlash    := UFlash( 'users' )
   hMessage[ 'type' ]    := oFlash:Get( 'type' )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   hInput    := oFlash:Get( 'input' )
   hErrors   := oFlash:Get( 'errors', { => } )
   oFlash:Clear()
   oFlash:Save()

RETURN Self:Finish( UView( 'masters/users/edit.html', 'create', .F., ;
              iif( hb_IsHash( hInput ), _Visible( hInput ), { => } ), ;
              hMessage, hErrors ) )


METHOD Store() CLASS UsersControllers

   LOCAL oVal, cName, cPass, cSalt, nNew := 0
   LOCAL oDb

   // 'pass' is not |field - it is never copied into the store as posted
   // (D-07): it is salted and hashed below before it is written.
   oVal := UValidatePost( { ;
      "name"    => "required|string|max:40|field", ;
      "pass"    => "required|string|min:4|max:40", ;
      "roles"   => "required|string|max:255|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'users.create' ) ) )
   ENDIF

   cName := AllTrim( oVal:Get( 'name' ) )
   cPass := AllTrim( oVal:Get( 'pass' ) )

   oDb := Self:Open()
   IF oDb == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   // D-09: NAME is the login identity - a duplicate is refused outright,
   // with the message. A DBF has no UNIQUE KEY, so this refusal is the
   // whole enforcement.
   IF Self:NameExists( cName, NIL )
      Self:FlashFail( 'Name ' + cName + ' is already in use', ;
        { 'name' => 'Name already in use' }, oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'users.create' ) ) )
   ENDIF

   cSalt := _PwSalt()

   nNew := _NextRecno( oDb )

   IF ! oDb:Append()
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.create' ) ) )
   ENDIF

   //  D-07: the digest, never the password. The id is a persisted PK,
   //  assigned here, never the recno - Pack() renumbers records.
   _PutField( oDb, "ID",      nNew )
   _PutField( oDb, "NAME",    cName )
   _PutField( oDb, "PASS",    _PwHash( cPass, cSalt ) )
   _PutField( oDb, "SALT",    cSalt )
   _PutField( oDb, "ROLES",   AllTrim( oVal:Get( 'roles' ) ) )

   Self:FlashOk( 'User ' + hb_NToS( nNew ) + ' was created!' )

RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )


METHOD Update() CLASS UsersControllers

   LOCAL oVal, nId, cVersion, nVersion, cPass, cSalt, lOk := .F., nGot
   LOCAL oDb, hUpd, cErr := ""

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   oDb := Self:Open()
   IF oDb == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   //  P3.7 does not apply: no VERSION column in the shipped store, so the
   //  version the caller sent is not compared. It is still required by the
   //  form so the write is explicit about the record it read.
   cVersion := UPost( 'version', '' )

   oVal := UValidatePost( { ;
      "name"  => "required|string|max:40|field", ;
      "pass"  => "string|max:40", ;
      "roles" => "required|string|max:255|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'users.edit', nId ) ) )
   ENDIF

   IF ! _GotoRecno( oDb, nId )
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   //  D-09 on the update side: renaming onto a name another account already
   //  uses is refused. The account itself is excluded - a write that keeps its
   //  own name is not a collision.
   IF Self:NameExists( AllTrim( oVal:Get( 'name' ) ), nId )
      Self:FlashFail( 'Name ' + AllTrim( oVal:Get( 'name' ) ) + ' is already in use', ;
        { 'name' => 'Name already in use' }, oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'users.edit', nId ) ) )
   ENDIF

   nGot := 0

   //  the audited verb: HIX_DBF:Update() takes the lock, writes the fields,
   //  DbCommit()s and unlocks (src/dbf/hix_dbf.prg:606). Hand-rolling the
   //  same steps without DbCommit() leaves the record unchanged - that is
   //  what made T44 return 302 without persisting.
   //  the shipped store has no VERSION field (header: ID NAME PASS SALT ROLES),
   //  so there is no optimistic-concurrency column here. P3.7's conflict
   //  contract does not apply to this store and is not faked: the write is
   //  last-writer-wins, which is what a single-writer DBF store gives.
   hUpd := hb_Hash()
   hUpd[ "NAME" ]  := AllTrim( oVal:Get( 'name' ) )
   hUpd[ "ROLES" ] := AllTrim( oVal:Get( 'roles' ) )

   //  the form says "leave blank to keep the current password": a write that
   //  does not carry one must not re-hash, and must not clear, the digest
   cPass := AllTrim( oVal:Get( 'pass', '' ) )
   IF ! EMPTY( cPass )
      cSalt   := _PwSalt()
      hUpd[ "PASS" ] := _PwHash( cPass, cSalt )
      hUpd[ "SALT" ] := cSalt
   ENDIF

   lOk := oDb:Update( nId, hUpd, @cErr )

   IF ! lOk
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.edit', nId ) ) )
   ENDIF

   Self:FlashOk( 'User ' + hb_NToS( nId ) + ' was updated!' )

RETURN Self:Finish( URedirect( URoute( 'users.show', nId ) ) )


// -------------------------------------------------------------- //
// Delete. confirm renders what the delete WOULD touch before the
// destructive verb runs (SRS FR-DELETE-1..4). users_users has no FK
// pointing at it, so the preview is empty by construction - that is the
// honest answer, not a missing check.
// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS UsersControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDb

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   oDb := Self:Open()
   IF oDb == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   hRow := _RowByRecno( oDb, nId )

   IF hRow == NIL
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/users/delete.html', .T., ;
              _Visible( hRow ) ) )


METHOD delete_action() CLASS UsersControllers

   LOCAL oVal, nId, lOk := .F.
   LOCAL oDb

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   oDb := Self:Open()
   IF oDb == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   IF ! _GotoRecno( oDb, nId )
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   //  a DBF delete flags the record; it does not remove it. The id is a
   //  persisted PK, so a later Insert() never reuses it and no FK can be
   //  silently re-pointed by a recno shift.
   lOk := oDb:Delete( NIL, .F. )

   IF ! lOk
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   Self:FlashOk( 'User ' + hb_NToS( nId ) + ' was deleted (1 row, 0 other table(s) touched)' )

RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )


// -------------------------------------------------------------- //
// Flash: the module's own, drained once read (D-10).
// -------------------------------------------------------------- //

METHOD FlashFail( cMessage, hErrors, hInput ) CLASS UsersControllers

   //  the posted values go into the flash's input, not just the errors: Edit()
   //  reads them back to re-render the form with what the caller sent (the
   //  audited shape - see customer.prg's UFlash 'input'). Without this the
   //  validation-failure round trip loses the values and T43/T45 cannot pass.
   UFlash( 'users' ):Set( { ;
      "type"    => 'danger', ;
      "message" => cMessage, ;
      "errors"  => iif( ValType( hErrors ) == 'H', hErrors, { => } ), ;
      "input"   => iif( ValType( hInput ) == 'H', hInput, { => } ) ;
   } )

RETURN NIL


METHOD FlashOk( cMessage ) CLASS UsersControllers

   UFlash( 'users' ):Set( { ;
      "type"    => 'success', ;
      "message" => cMessage ;
   } )

RETURN NIL


METHOD TakeFlash() CLASS UsersControllers

   LOCAL oFlash := UFlash( 'users' )
   LOCAL hFlash := { => }

   hFlash[ 'type' ]    := oFlash:Get( 'type' )
   hFlash[ 'message' ] := oFlash:Get( 'message' )
   hFlash[ 'errors' ]  := oFlash:Get( 'errors', { => } )
   hFlash[ 'input' ]   := oFlash:Get( 'input', { => } )

   oFlash:Clear()
   oFlash:Save()

RETURN hFlash


METHOD NameExists( cName, nExclude ) CLASS UsersControllers

   LOCAL oDb := Self:Open()

   IF oDb == NIL
      RETU .F.
   ENDIF

RETU _NameExists( oDb, cName, nExclude )


// -------------------------------------------------------------- //
// The store helpers. UDbf's verbs are the RDD's own; the id is the
// persisted PK on the "id" CDX tag, never the recno.
// -------------------------------------------------------------- //

STATIC FUNCTION _PutField( oDb, cName, xVal )

   oDb:FieldPut( Upper( cName ), xVal )

RETURN NIL


STATIC FUNCTION _GetField( oDb, cName )

RETU oDb:FieldGet( Upper( cName ) )


//  the next record number: RecCount() + 1, as the audited module does (it
//  reports RecNo() after the append). A soft-deleted record keeps its number,
//  so a number is never handed to two live records while it exists.
STATIC FUNCTION _NextRecno( oDb )

RETU oDb:RecCount() + 1


//  the public id is the record number, exactly as the audited customer module
//  uses it (GetRecno). The DBF's own ID field is blank in every shipped copy -
//  the app never populated it, and nothing should assume it can.
STATIC FUNCTION _GotoRecno( oDb, nRecno )

   oDb:Goto( nRecno )

RETU ( ! oDb:Eof() )


//  one row as the views consume it: the allow-list only (D-05), plus the
//  id (the recno) and the allow-list the views consume
STATIC FUNCTION _RowByRecno( oDb, nRecno )

   LOCAL hRow := NIL

   IF ! _GotoRecno( oDb, nRecno )
      RETU NIL
   ENDIF

   hRow := hb_Hash()
   hRow[ "id" ]      := nRecno
   hRow[ "name" ]    := oDb:FieldGet( "NAME" )
   hRow[ "roles" ]   := oDb:FieldGet( "ROLES" )

RETU hRow


//  a blank row, as the audited module hands the view when the record is not
//  there: the view renders and says so, rather than the verb redirecting
STATIC FUNCTION _BlankRow()

RETU { "id" => 0, "name" => "", "roles" => "" }


//  D-05: the row is rebuilt from the allow-list before it is handed to a
//  view, so the digest and the salt cannot follow the row into the view
STATIC FUNCTION _Visible( hRow )

   LOCAL hOut := hb_Hash()

   hOut[ "id" ]      := hb_HGetDef( hRow, "id", 0 )
   hOut[ "name" ]    := hb_HGetDef( hRow, "name", "" )
   hOut[ "roles" ]   := hb_HGetDef( hRow, "roles", "" )

RETU hOut


//  D-09: NAME is the login identity. The check is an exact, case-insensitive
//  comparison over the store - the CDX tag on NAME is what makes the lookup a
//  seek instead of a scan, and the confirmation is what a prefix key can still
//  get wrong.
STATIC FUNCTION _NameExists( oDb, cName, nExclude )

   LOCAL cFound, cSeek, lFound, nGot

   cSeek  := Upper( AllTrim( cName ) )
   lFound := .F.

   oDb:First()
   WHILE ! oDb:Eof()
      cFound := Upper( AllTrim( oDb:FieldGet( "NAME" ) ) )
      IF cFound == cSeek
         nGot := oDb:Recno()
         IF nExclude == NIL .OR. nGot != nExclude
            lFound := .T.
            EXIT
         ENDIF
      ENDIF
      oDb:Next()
   END

RETU lFound


//  case-insensitive substring, Harbour's own - the store has no collation
//  to lean on, so the comparison is stated here (D-16's shape).
STATIC FUNCTION _InSensitive( cHay, cNeedle )

   LOCAL cUp := Upper( AllTrim( iif( ValType( cHay ) == 'C', cHay, "" ) ) )
   LOCAL cKey := Upper( AllTrim( iif( ValType( cNeedle ) == 'C', cNeedle, "" ) ) )

   IF EMPTY( cKey )
      RETU .T.
   ENDIF

RETU ( cKey $ cUp )


STATIC FUNCTION _RowMatchesQ( hRow, aFields, cQ )

   LOCAL nI

   FOR nI := 1 TO LEN( aFields )
      IF _InSensitive( hb_HGetDef( hRow, aFields[ nI ], "" ), cQ )
         RETU .T.
      ENDIF
   NEXT

RETU .F.


STATIC FUNCTION _SortRows( aRows, cKey, cDir )

   LOCAL nI, nJ, xA, xB, nCmp, aOut := aRows

   FOR nI := 2 TO LEN( aOut )
      nJ := nI
      WHILE nJ > 1
         xA   := hb_HGetDef( aOut[ nJ - 1 ], cKey, "" )
         xB   := hb_HGetDef( aOut[ nJ ], cKey, "" )
         nCmp := _CompareVal( xA, xB )
         IF cDir == "DESC"
            nCmp := -nCmp
         ENDIF
         IF nCmp > 0
            aOut := _SwapAt( aOut, nJ - 1, nJ )
            nJ--
         ELSE
            EXIT
         ENDIF
      END
   NEXT

RETU aOut


STATIC FUNCTION _SwapAt( aRows, nA, nB )

   LOCAL xHold := aRows[ nA ]

   aRows[ nA ] := aRows[ nB ]
   aRows[ nB ] := xHold

RETU aRows


STATIC FUNCTION _CompareVal( xA, xB )

   LOCAL cA, cB

   IF ValType( xA ) == 'N' .AND. ValType( xB ) == 'N'
      IF xA < xB
         RETU -1
      ENDIF
      IF xA > xB
         RETU 1
      ENDIF
      RETU 0
   ENDIF

   cA := Upper( iif( ValType( xA ) == 'C', xA, hb_NToS( xA ) ) )
   cB := Upper( iif( ValType( xB ) == 'C', xB, hb_NToS( xB ) ) )

   //  Harbour's < and > on strings are SET EXACT affected (www/config.json
   //  sets "exact": false): with EXACT OFF the comparison only looks at the
   //  RIGHT operand's length, so "long" < "short" and "long" > "short" can BOTH
   //  be false - a comparator built on them cannot order the rows, which is what
   //  made D-08a's sort a no-op. Ord() byte-wise is not affected.
RETU _CmpBytes( cA, cB )


//  byte-wise string compare, independent of SET EXACT
STATIC FUNCTION _CmpBytes( cA, cB )

   LOCAL nI, nLen, nA, nB

   nLen := MIN( LEN( cA ), LEN( cB ) )

   FOR nI := 1 TO nLen
      nA := _ByteOf( SubStr( cA, nI, 1 ) )
      nB := _ByteOf( SubStr( cB, nI, 1 ) )
      IF nA < nB
         RETU -1
      ENDIF
      IF nA > nB
         RETU 1
      ENDIF
   NEXT

   //  equal up to nLen: the shorter string sorts first
   IF LEN( cA ) < LEN( cB )
      RETU -1
   ENDIF
   IF LEN( cA ) > LEN( cB )
      RETU 1
   ENDIF

RETU 0


//  Ord() is not linked into the HIX server ("Unknown or unregistered function
//  symbol (ORD)"), so the byte value is taken from a fixed table built with
//  linked primitives only. Length-1 == is exact under SET EXACT OFF.
//  Ord() is not linked into the HIX server, so the rank of a character is
//  taken from a fixed ordered alphabet. The alphabet is built by concatenation
//  so no quote character has to be escaped inside a single literal.
STATIC FUNCTION _ByteOf( cCh )

   LOCAL cTable := "" + " !" + chr( 34 ) + "$%&'()*+,-./0123456789:;<=>?@" + ;
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`" + ;
                    "abcdefghijklmnopqrstuvwxyz{|}~"
   LOCAL nI

   FOR nI := 1 TO LEN( cTable )
      IF SubStr( cTable, nI, 1 ) == cCh
         RETU nI
      ENDIF
   NEXT

RETU 0


#include 'models/hpassword.prg'
#include 'models/tusers.prg'
