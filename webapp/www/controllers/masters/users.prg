// --------------------------------------------------------------------------------
// Users — CRUD for the credential store, on the MySQL DAL
//
// P4.8 of webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md (Step 0.2, Option A for
// `users`). The shape follows the audited www/controllers/masters/customer.prg
// and www/controllers/masters/part.prg - the same nine verbs, the same
// middleware pair, the same flash + redirect for writes. What changes is what
// sits behind the verbs: the pool and www/models/tdalmysql.prg instead of
// UDbf(), over users_users, the table shipped in webapp/sql/hix_users.sql.
//
// Defect closures carried over from the DBF module, restated for the new store:
//   D-05  the digest and the salt never reach a view: the read whitelist is
//         {name, roles} only, so no hRow the module hands a view can carry
//         them (this replaces TUsers():Hide( {'pass','salt'} ))
//   D-06  free-text search is restricted to an allow-list of columns (the
//         LIKE terms go over name and roles, never over an arbitrary column)
//   D-08  the sort key uses the same case as the grid's hash keys
//   D-09  NAME is the login identity: a duplicate is refused on create and on
//         update. The UNIQUE KEY ix_name in the schema is the backstop; the
//         refusal here is what makes it a message instead of a server error
//   D-10  the flash is drained once it has been read
//   D-11  one pool slot per request, returned by the verb that took it
//         (Finish() - see part.prg for why the destructor alone is not enough)
//   D-13  oVal:Get( 'id' ) is named explicitly, never implied
//   D-16  the name is normalised once; the store's collation (utf8mb4_unicode_ci,
//         P0.4) does the case-insensitive match and the exact confirmation is
//         done here, because a collated equality answers for a longer key too
//   N-01  every write form carries a CSRF token (@CSRF in the views; the
//         MyAppAuthRoleEdit middleware enforces it)
//   P3.7  a write carries the version it read; a stale one is refused
//
// The password is hashed here, not in a view and never stored in the clear:
// www/models/hpassword.prg (D-07). A write that leaves the password blank keeps
// the current digest - the store is never silently re-hashed.
// --------------------------------------------------------------------------------

#include 'hbclass.ch'

CLASS UsersControllers

   DATA oConn INIT NIL

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

   METHOD Slot()
   METHOD Finish( xRet )
   METHOD Dal( cTable, aCols )
   METHOD NameExists( cName, nExclude )
   METHOD FlashFail( cMessage, hErrors, hInput )
   METHOD FlashOk( cMessage )
   METHOD TakeFlash()

ENDCLASS

// -------------------------------------------------------------- //

METHOD New() CLASS UsersControllers

   ::oConn := NIL

RETURN SELF


METHOD End() CLASS UsersControllers

RETURN SELF


// -------------------------------------------------------------- //
// D-11 / P3.4: one WDO_Get per request. Absent the pool the module
// answers the SRS banner and nothing else - the server's words never
// reach the client (P3.6).
// -------------------------------------------------------------- //

METHOD Slot() CLASS UsersControllers

   IF ::oConn == NIL
      ::oConn := WDO_Get( "mysql" )
      IF ::oConn == NIL
         Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
            { => }, NIL )
      ENDIF
   ENDIF

RETU ::oConn


METHOD Destroy() CLASS UsersControllers

   //  the borrowed DAL objects never close it; the slot is returned once
   IF ::oConn != NIL
      ::oConn:Close()
      ::oConn := NIL
   ENDIF

RETURN NIL


//  P3.4 made explicit: the slot goes back before the verb returns.
//  See part.prg for why Harbour's destructor is not enough - the
//  dispatcher's WDO_ReleaseAllThread() hook runs before the object
//  dies, so a handler that relies on it logs a reclaim per request.
METHOD Finish( xRet ) CLASS UsersControllers

   Self:Destroy()

RETU xRet


// -------------------------------------------------------------- //
// Two whitelists, not one (D-05).
//
// READ: what a view may see. pass and salt are NOT in here, which is
// what keeps them out of every hRow this module hands a view - the
// replacement for TUsers():Hide( {'pass','salt'} ).
//
// WRITE: what the store may be given. Only Store()/Update() ask for
// it, and the values are computed here (hpassword.prg), never taken
// from a view.
// -------------------------------------------------------------- //

METHOD Dal( cTable, aCols ) CLASS UsersControllers

   LOCAL oDal := NIL

   IF Self:Slot() != NIL
      oDal := TDalMySql():New( cTable, aCols )
      oDal:Attach( ::oConn )
   ENDIF

RETU oDal


// -------------------------------------------------------------- //
// Reads. D-06: the LIKE terms go over the columns named here, so a
// free-text query can never ask for an arbitrary column.
// -------------------------------------------------------------- //

METHOD Grid() CLASS UsersControllers

   LOCAL nPage, nRows, nTotal, nTotalPages := 0
   LOCAL aAll, aGrid := {}, aPages := {}
   LOCAL cQ, hLike := { => }, cSort, cDir
   LOCAL oDal
   LOCAL nI, nJ, aFields := { "name", "roles" }, hQ := { => }, cSearchParams := ""
   LOCAL aMatch := {}, lKeep, cTerm

   IF Self:Slot() == NIL
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
   //  per-column search - pass and salt are not in it, so nothing here can
   //  read, sort, search or render a credential
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

   //  the free-text bar is an OR of LIKEs over the rendered columns (the DAL's
   //  shape - see P4-PART-RESULTS §3); the per-column boxes narrow, so they are
   //  applied as an AND below
   IF ! EMPTY( cQ )
      FOR nI := 1 TO LEN( aFields )
         hLike[ aFields[ nI ] ] := cQ
      NEXT
   ENDIF

   oDal := Self:Dal( "users_users", { "name", "roles" } )

   aAll := oDal:FetchAll( NIL, hLike )
   IF aAll == NIL
      aAll := {}
   ENDIF

   //  narrow by column (AND), case-insensitively - the store's collation
   //  already ignores case, but the comparison here is Harbour's own
   FOR nI := 1 TO LEN( aAll )
      lKeep := .T.
      FOR nJ := 1 TO LEN( aFields )
         cTerm := hb_HGetDef( hQ, aFields[ nJ ], "" )
         IF ! EMPTY( cTerm ) .AND. ! _InSensitive( hb_HGetDef( aAll[ nI ], aFields[ nJ ], "" ), cTerm )
            lKeep := .F.
            EXIT
         ENDIF
      NEXT
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
         cSearchParams += '&_q_' + aFields[ nI ] + '=' + hb_HGetDef( hQ, aFields[ nI ], "" )
      ENDIF
   NEXT

   oDal:Close()

RETURN Self:Finish( UView( 'masters/users/grid.html', 'grid', aGrid, aPages, nPage, nTotalPages, ;
              cSort, cDir, cQ, hQ, Self:TakeFlash(), { => }, cSearchParams ) )


METHOD Search() CLASS UsersControllers

   LOCAL hSearch := { => }, nI
   LOCAL aFields := { "name", "roles" }      // same list as Grid()

   //  FR-READ-3: one entry per grid column, kept identical to Grid()
   FOR nI := 1 TO LEN( aFields )
      hSearch[ aFields[ nI ] ] := Trim( UGet( '_q_' + aFields[ nI ], '' ) )
   NEXT

RETURN Self:Finish( UView( 'masters/users/search.html', hSearch, Self:TakeFlash() ) )


METHOD Show() CLASS UsersControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0      // D-13
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "users_users", { "name", "roles" } )

   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/users/show.html', .T., hRow, Self:TakeFlash() ) )


// -------------------------------------------------------------- //
// Writes. The form (edit/create) renders and the POST verb (store/update)
// performs - the audited split, kept so the CSRF middleware and the scope
// stay on the write side only.
// -------------------------------------------------------------- //

METHOD Edit() CLASS UsersControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "users_users", { "name", "roles" } )
   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   //  the version the form shows is the version the write must carry back
RETURN Self:Finish( UView( 'masters/users/edit.html', 'edit', .T., hRow, ;
              Self:TakeFlash(), { => } ) )


METHOD Create() CLASS UsersControllers

RETURN Self:Finish( UView( 'masters/users/edit.html', 'create', .F., { => }, ;
              Self:TakeFlash(), { => } ) )


METHOD Store() CLASS UsersControllers

   LOCAL oVal, cName, cPass, cSalt, hData := { => }, nNew
   LOCAL oDal

   // 'pass' is not |field - it is never copied into the store as posted
   // (D-07): it is salted and hashed below before it is bound.
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

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   // D-09: NAME is the login identity - a duplicate is refused outright,
   // with the message, rather than left to the UNIQUE KEY in the schema.
   IF Self:NameExists( cName, NIL )
      Self:FlashFail( 'Name ' + cName + ' is already in use', ;
        { 'name' => 'Name already in use' }, oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'users.create' ) ) )
   ENDIF

   cSalt := _PwSalt()

   hData[ "name" ]  := cName
   hData[ "pass" ]  := _PwHash( cPass, cSalt )   // D-07: the digest, never the password
   hData[ "salt" ]  := cSalt
   hData[ "roles" ] := AllTrim( oVal:Get( 'roles' ) )

   oDal := Self:Dal( "users_users", { "name", "pass", "salt", "roles" } )
   nNew := oDal:Insert( hData )
   oDal:Close()

   IF nNew > 0
      Self:FlashOk( 'User ' + hb_NToS( nNew ) + ' was created!' )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'users.create' ) ) )


METHOD Update() CLASS UsersControllers

   LOCAL oVal, nId, cVersion, nVersion, cPass, cSalt, cName, hData := { => }, lOk, hErr
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   //  P3.7: the write must carry the version the caller READ. Absent it the
   //  write is refused - Val( '' ) is 0, which would have matched every
   //  account still at version 0, i.e. an account nobody read.
   cVersion := UPost( 'version', '' )
   IF Empty( cVersion )
      Self:FlashFail( "Send the version you read with the change - " ;
        + "nothing was written.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.edit', nId ) ) )
   ENDIF
   nVersion := Val( cVersion )

   oVal := UValidatePost( { ;
      "name"  => "required|string|max:40|field", ;
      "pass"  => "string|max:40", ;
      "roles" => "required|string|max:255|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'users.edit', nId ) ) )
   ENDIF

   // D-09 on the update side: renaming onto a name another account already
   // uses is refused. The account itself is excluded - a write that keeps its
   // own name is not a collision.
   cName := AllTrim( oVal:Get( 'name' ) )
   IF Self:NameExists( cName, nId )
      Self:FlashFail( 'Name ' + cName + ' is already in use', ;
        { 'name' => 'Name already in use' }, oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'users.edit', nId ) ) )
   ENDIF

   hData[ "name" ]  := cName
   hData[ "roles" ] := AllTrim( oVal:Get( 'roles' ) )

   //  the form says "leave blank to keep the current password": a write that
   //  does not carry one must not re-hash, and must not clear, the digest
   cPass := AllTrim( oVal:Get( 'pass', '' ) )
   IF ! EMPTY( cPass )
      cSalt := _PwSalt()
      hData[ "pass" ] := _PwHash( cPass, cSalt )
      hData[ "salt" ] := cSalt
   ENDIF

   oDal := Self:Dal( "users_users", { "name", "pass", "salt", "roles" } )
   lOk  := oDal:Update( nId, nVersion, hData )
   hErr := oDal:Errors()
   oDal:Close()

   IF lOk
      Self:FlashOk( 'User ' + hb_NToS( nId ) + ' was updated!' )
      //  URoute resolves the parameter itself: 'users.show' is /users/:id
      RETURN Self:Finish( URedirect( URoute( 'users.show', nId ) ) )
   ENDIF

   //  SRS 5.2: a conflict is a warning that shows the record again, not a
   //  blind overwrite. It goes to the show page - the edit form renders only
   //  what the caller posted, so it cannot show the record.
   IF hErr != NIL .AND. hErr[ "reason" ] == "conflict"
      Self:FlashFail( "Someone changed this account after you read it. " ;
        + "It is shown again below - nothing was overwritten.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.show', nId ) ) )
   ENDIF

   IF hErr != NIL .AND. hErr[ "reason" ] == "not found"
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'users.edit', nId ) ) )


// -------------------------------------------------------------- //
// Delete. confirm renders what the delete WOULD touch before the
// destructive verb runs (SRS FR-DELETE-1..4). users_users has no
// foreign key pointing at it, so the preview is empty by construction
// - that is the honest answer, not a missing check.
// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS UsersControllers

   LOCAL oVal, nId, hRow
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "users_users", { "name", "roles" } )
   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/users/delete.html', .T., hRow ) )


METHOD delete_action() CLASS UsersControllers

   LOCAL oVal, nId, hRes
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "users_users", { "name", "roles" } )
   hRes := oDal:Delete( nId, NIL )
   oDal:Close()

   //  the verb says what it did and what it did not do. A rolled-back
   //  cascade is not "the account was not there": nothing was changed (D4)
   IF ValType( hRes ) != 'H'
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   IF hb_HGetDef( hRes, "rolledback", .F. )
      Self:FlashFail( "The delete could not be applied. Nothing was changed.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   IF hb_HGetDef( hRes, "deleted", 0 ) == 0
      Self:FlashFail( "That user is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )
   ENDIF

   Self:FlashOk( 'User ' + hb_NToS( nId ) + ' was deleted!' )

RETURN Self:Finish( URedirect( URoute( 'users.grid' ) ) )


// -------------------------------------------------------------- //
// D-09: the name is the login identity. The check is a bound equality
// over the store (the collation makes it case-insensitive, which is what
// the CDX tag keyed on Lower(NAME) used to give) and the row is confirmed
// by id so a write that keeps its own name is not a collision.
// -------------------------------------------------------------- //

METHOD NameExists( cName, nExclude ) CLASS UsersControllers

   LOCAL oDal, aRows, nI, nGot
   LOCAL lFound := .F.

   IF EMPTY( cName )
      RETU .F.
   ENDIF

   oDal := Self:Dal( "users_users", { "name" } )
   IF oDal == NIL
      RETU .F.
   ENDIF

   aRows := oDal:FetchAll( { "name" => cName }, NIL )
   oDal:Close()

   IF EMPTY( aRows )
      RETU .F.
   ENDIF

   FOR nI := 1 TO LEN( aRows )
      nGot := hb_HGetDef( aRows[ nI ], "id", 0 )
      IF nExclude == NIL .OR. nGot != nExclude
         RETU .T.
      ENDIF
   NEXT

RETU lFound


// -------------------------------------------------------------- //
// Flash: the module's own, drained once read (D-10).
// -------------------------------------------------------------- //

METHOD FlashFail( cMessage, hErrors, hInput ) CLASS UsersControllers

   UFlash( 'users' ):Set( { ;
      "type"    => 'danger', ;
      "message" => cMessage, ;
      "errors"  => iif( ValType( hErrors ) == 'H', hErrors, ;
                        { => } ) ;
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

   oFlash:Clear()
   oFlash:Save()

RETURN hFlash

// -------------------------------------------------------------- //
// File-level helpers (no state of their own).
//
//  _InSensitive: a substring test that ignores case - what the CDX tag
//  keyed on Lower(NAME) used to give the per-column search boxes.
//
//  _SortRows: the grid's column sort. The DAL orders by id; the audited
//  module ordered the filtered list, and the grid's sort parameter is a
//  user-visible column, so the order happens here, over the allow-listed
//  column only (D-06/D-08).
// -------------------------------------------------------------- //

STATIC FUNCTION _InSensitive( cHay, cNeedle )

   IF EMPTY( cNeedle )
      RETU .T.
   ENDIF

RETU _PosIn( Upper( cHay ), Upper( cNeedle ) ) > 0

STATIC FUNCTION _PosIn( cHay, cNeedle )

   LOCAL nLen := LEN( cNeedle ), i

   IF EMPTY( cNeedle )
      RETU 0
   ENDIF

   FOR i := 1 TO LEN( cHay ) - nLen + 1
      IF SUBSTR( cHay, i, nLen ) == cNeedle
         RETU i
      ENDIF
   NEXT

RETU 0

STATIC FUNCTION _SortRows( aRows, cKey, cDir )

   LOCAL nI, nJ, nCmp, xSwap := NIL, aOut := {}

   FOR nI := 1 TO LEN( aRows )
      AADD( aOut, aRows[ nI ] )
   NEXT

   FOR nI := 2 TO LEN( aOut )
      xSwap := aOut[ nI ]
      nJ := nI - 1
      WHILE nJ >= 1
         nCmp := _CompareVal( hb_HGetDef( aOut[ nJ ], cKey, "" ), ;
                              hb_HGetDef( xSwap, cKey, "" ) )
         IF cDir == "DESC"
            nCmp := -nCmp
         ENDIF
         IF nCmp <= 0
            EXIT
         ENDIF
         aOut[ nJ + 1 ] := aOut[ nJ ]
         nJ--
      END
      aOut[ nJ + 1 ] := xSwap
   NEXT

RETU aOut

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

   IF cA < cB
      RETU -1
   ENDIF
   IF cA > cB
      RETU 1
   ENDIF

RETU 0

#include 'models/hpassword.prg'
#include 'models/tdalmysql.prg'
