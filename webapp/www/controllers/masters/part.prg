// --------------------------------------------------------------------------------
// Part — CRUD for the part module, on the MySQL DAL
//
// P4.1 of webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md. The shape follows the
// audited www/controllers/masters/customer.prg and users.prg (same nine verbs,
// same middleware pair, same flash + redirect for writes) - what changes is
// what sits behind the verbs: the pool and www/models/tdalmysql.prg instead of
// UDbf().
//
// One slot per request (P3.4): Slot() takes the pool connection ONCE and every
// Dal( cTable ) in the request borrows it. Twelve tables against a pool of eight
// would block on the ninth WDO_Get; here the count never leaves one. Destroy()
// returns it, once.
//
// The column whitelist is this module's declaration, not the form's: the KEYS
// of a posted hash are external input, and the DAL drops anything outside the
// list rather than quoting it into a statement (P3.2).
//
// delete_confirm renders Cascade() - what the delete WOULD touch - before the
// destructive verb runs (SRS FR-DELETE-1..4). With 15 edges pointing at part_part
// that preview is the whole point of the confirm step.
// --------------------------------------------------------------------------------

#include 'hbclass.ch'

CLASS PartControllers

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
   METHOD Dal( cTable )
   METHOD Cols( cTable )
   METHOD FlashFail( cMessage, hErrors, hInput )
   METHOD FlashOk( cMessage )
   METHOD TakeFlash()
   METHOD Finish( xRet )

ENDCLASS

// -------------------------------------------------------------- //

METHOD New() CLASS PartControllers

   ::oConn := NIL

RETURN SELF


METHOD End() CLASS PartControllers

RETURN SELF


// -------------------------------------------------------------- //
// P3.4: one WDO_Get per handler. Absent the pool the module answers the
// SRS banner and nothing else - the server's words never reach the client
// (P3.6).
// -------------------------------------------------------------- //

METHOD Slot() CLASS PartControllers

   IF ::oConn == NIL
      ::oConn := WDO_Get( "mysql" )
      IF ::oConn == NIL
         Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
            { => }, NIL )
      ENDIF
   ENDIF

RETU ::oConn


METHOD Destroy() CLASS PartControllers

   //  the slot is returned here, once - the borrowed DAL objects never
   //  close it (TDalMySql:Close() only returns a connection it owns)
   IF ::oConn != NIL
      ::oConn:Close()
      ::oConn := NIL
   ENDIF

RETURN NIL


//  P3.4, made explicit: every verb returns through Finish(), which gives
//  the slot back BEFORE the verb returns. Harbour's destructor runs when
//  the object's reference dies, and the dispatcher calls WDO_ReleaseAllThread()
//  in the child thread before that happens - so a handler that only relies on
//  Destroy() leaves the connection still borrowed when the hook runs, and the
//  hook logs a reclaim for every request ("reclaiming 1 leaked connection").
//  Destroy() is idempotent, so calling it here and being called again later
//  is harmless.
METHOD Finish( xRet ) CLASS PartControllers

   Self:Destroy()

RETU xRet


// -------------------------------------------------------------- //
// The columns this module will read or write, per table. A field the form
// sends that is not in here is dropped by the DAL and logged.
// -------------------------------------------------------------- //

METHOD Cols( cTable ) CLASS PartControllers

   DO CASE
   CASE cTable == "part_part"
      RETU { "name", "description", "IPN", "keywords", ;
             "category", "link", "units", ;
             "minimum_stock", "maximum_stock", "active" }
   CASE cTable == "part_partcategory"
      RETU { "name", "description" }
   CASE cTable == "stock_stocklocation"
      RETU { "name", "description" }
   ENDCASE

RETU {}


METHOD Dal( cTable ) CLASS PartControllers

   LOCAL oDal := NIL

   IF Self:Slot() != NIL
      oDal := TDalMySql():New( cTable, Self:Cols( cTable ) )
      oDal:Attach( ::oConn )
   ENDIF

RETU oDal


// -------------------------------------------------------------- //
// Reads. FR-READ-1..5: grid paged, search by substring, show by id.
// The LIKE wildcards are part of the bound VALUE, never of the SQL text.
// -------------------------------------------------------------- //

METHOD Grid() CLASS PartControllers

   LOCAL nPage, nRows, nTotal, nTotalPages := 0
   LOCAL aAll, aGrid := {}, aPages := {}
   LOCAL cQ, hLike := { => }, cSort, cDir
   LOCAL oDal
   LOCAL nI, aCols

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   nPage := Iif( Empty( UGet( 'page', '' ) ), 1, Val( UGet( 'page', '' ) ) )
   IF nPage < 1
      nPage := 1
   ENDIF
   nRows := 20

   cQ   := Trim( UGet( 'q', '' ) )
   cSort := Lower( UGet( 'sort', 'name' ) )
   cDir  := Upper( UGet( 'dir', 'ASC' ) )

   aCols := Self:Cols( "part_part" )

   //  the search bar looks in the columns this module renders
   IF ! EMPTY( cQ )
      FOR nI := 1 TO LEN( aCols )
         hLike[ aCols[ nI ] ] := cQ
      NEXT
   ENDIF

   oDal := Self:Dal( "part_part" )

   nTotal := oDal:Count( NIL, hLike )
   IF nTotal < 0
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      nTotal := 0
   ENDIF

   IF nTotal > 0
      nTotalPages := Int( ( nTotal + nRows - 1 ) / nRows )
      IF nPage > nTotalPages
         nPage := nTotalPages
      ENDIF
      aAll := oDal:FetchPaged( nRows, ( nPage - 1 ) * nRows, NIL, hLike )
      IF aAll == NIL
         aAll := {}
      ENDIF
      FOR nI := 1 TO LEN( aAll )
         AADD( aGrid, aAll[ nI ] )
      NEXT
   ENDIF

   FOR nI := 1 TO MIN( nTotalPages, 10 )
      AADD( aPages, nI )
   NEXT

   oDal:Close()

RETURN Self:Finish( UView( 'masters/part/grid.html', aGrid, aPages, nPage, nTotalPages, ;
              nTotal, cSort, cDir, cQ, Self:TakeFlash() ) )


METHOD Search() CLASS PartControllers

   LOCAL cQ, hLike := { => }, aAll := {}, nTotal := 0
   LOCAL oDal
   LOCAL nI, aCols

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   cQ := Trim( UGet( 'q', '' ) )
   IF EMPTY( cQ )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   aCols := Self:Cols( "part_part" )

   FOR nI := 1 TO LEN( aCols )
      hLike[ aCols[ nI ] ] := cQ
   NEXT

   oDal := Self:Dal( "part_part" )

   aAll := oDal:FetchAll( NIL, hLike )
   IF aAll == NIL
      aAll := {}
   ENDIF
   nTotal := LEN( aAll )

   oDal:Close()

RETURN Self:Finish( UView( 'masters/part/grid.html', aAll, { 1 }, 1, 1, nTotal, ;
              'name', 'ASC', cQ, Self:TakeFlash() ) )


METHOD Show() CLASS PartControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      Self:FlashFail( "That part is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "part_part" )

   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That part is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/part/show.html', .T., hRow, Self:TakeFlash() ) )


// -------------------------------------------------------------- //
// Writes. The form (edit/create) renders and the POST verb (store/update)
// performs - the audited split, kept so the CSRF middleware and the scope
// stay on the write side only.
// -------------------------------------------------------------- //

METHOD Edit() CLASS PartControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "part_part" )
   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That part is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   //  the version the form shows is the version the write must carry back
RETURN Self:Finish( UView( 'masters/part/edit.html', 'edit', .T., hRow, ;
              Self:TakeFlash(), hRow[ "version" ] ) )


METHOD Create() CLASS PartControllers

RETURN Self:Finish( UView( 'masters/part/edit.html', 'create', .F., { => }, ;
              Self:TakeFlash(), 0 ) )


METHOD Store() CLASS PartControllers

   LOCAL oVal, hData := { => }, nNew
   LOCAL oDal

   oVal := UValidatePost( { ;
      "name"        => "required|string|max:100|field", ;
      "description" => "string|max:250|field", ;
      "IPN"         => "string|max:100|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( "The name is required.", oVal:GetErrors(), ;
        oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'part.create' ) ) )
   ENDIF

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   hData[ "name" ] := AllTrim( oVal:Get( 'name' ) )
   hData[ "description" ] := AllTrim( oVal:Get( 'description', '' ) )
   hData[ "IPN" ] := AllTrim( oVal:Get( 'IPN', '' ) )

   oDal := Self:Dal( "part_part" )
   nNew := oDal:Insert( hData )
   oDal:Close()

   IF nNew > 0
      Self:FlashOk( 'Part ' + hb_NToS( nNew ) + ' was created!' )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'part.create' ) ) )


METHOD Update() CLASS PartControllers

   LOCAL oVal, nId, nVersion, cVersion, hData := { => }, lOk, hErr
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   //  P3.7: the write must carry the version the caller READ. Absent it the
   //  write is refused - Val( '' ) is 0, which would have matched every record
   //  still at version 0, i.e. a blind overwrite of a row nobody read.
   cVersion := UPost( 'version', '' )
   IF Empty( cVersion )
      Self:FlashFail( "Send the version you read with the change - " ;
        + "nothing was written.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.edit', nId ) ) )
   ENDIF
   nVersion := Val( cVersion )

   //  the same validation create does: a write that omits the name must not
   //  clear it (the audited module validates the POST body, not the URL)
   oVal := UValidatePost( { ;
      "name"        => "required|string|max:100|field", ;
      "description" => "string|max:250|field", ;
      "IPN"         => "string|max:100|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( "The name is required.", oVal:GetErrors(), ;
        oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'part.edit', nId ) ) )
   ENDIF

   hData[ "name" ] := AllTrim( oVal:Get( 'name' ) )
   hData[ "description" ] := AllTrim( oVal:Get( 'description', '' ) )
   hData[ "IPN" ] := AllTrim( oVal:Get( 'IPN', '' ) )

   oDal := Self:Dal( "part_part" )
   lOk  := oDal:Update( nId, nVersion, hData )
   hErr := oDal:Errors()
   oDal:Close()

   IF lOk
      Self:FlashOk( 'Part ' + hb_NToS( nId ) + ' was updated!' )
      //  URoute resolves the parameter itself: 'part.show' is /part/:id, so
      //  URoute( 'part.show' ) alone answers "" and the redirect lands back
      //  on the verb that was just called (405 on GET).
      RETURN Self:Finish( URedirect( URoute( 'part.show', nId ) ) )
   ENDIF

   //  SRS 5.2: a conflict is a warning that shows the record again, not a
   //  blind overwrite. The audited app signals writes through flash +
   //  redirect, so the conflict is a flash of its own kind - see the
   //  deviation note in P4-PART-RESULTS. It goes to the SHOW page, not back
   //  to the edit form: the edit form renders only the fields the caller
   //  posted, so it cannot "show the record again" - show does, and the next
   //  write has to re-read the version from it.
   IF hErr != NIL .AND. hErr[ "reason" ] == "conflict"
      Self:FlashFail( "Someone changed this part after you read it. " ;
        + "It is shown again below - nothing was overwritten.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.show', nId ) ) )
   ENDIF

   IF hErr != NIL .AND. hErr[ "reason" ] == "not found"
      Self:FlashFail( "That part is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'part.edit', nId ) ) )


// -------------------------------------------------------------- //
// Delete. confirm renders the cascade preview; the POST verb performs.
// No policy is declared on any edge yet (Step 0.3 is P4.2's to decide), so
// the default KEEP leaves dependent rows dangling - and the preview says so.
// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS PartControllers

   LOCAL oVal, nId, hRow, hPrev
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "part_part" )
   hRow := oDal:Show( nId )
   hPrev := oDal:Cascade( nId, NIL )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That part is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/part/delete.html', .T., hRow, hPrev, ;
              Self:TakeFlash(), nId ) )


METHOD delete_action() CLASS PartControllers

   LOCAL oVal, nId, hRes
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "part_part" )
   hRes := oDal:Delete( nId, NIL )
   oDal:Close()

   //  the verb says what it did and what it did not do. A rolled-back
   //  cascade is not "the row was not there": the cascade could not be
   //  applied at all, and the store is unchanged (D4)
   IF ValType( hRes ) != 'H'
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   IF hb_HGetDef( hRes, "rolledback", .F. )
      Self:FlashFail( "The delete could not be applied. Nothing was changed.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   IF hb_HGetDef( hRes, "deleted", 0 ) == 0
      Self:FlashFail( "That part is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )
   ENDIF

   //  D5: the flash quotes the numbers the transaction actually applied,
  //  not the preview's - the preview was a claim about a moment that has
  //  already passed
   Self:FlashOk( 'Part ' + hb_NToS( nId ) + ' was deleted (' ;
        + hb_NToS( hb_HGetDef( hRes, "deleted", 0 ) ) + ' row, ' ;
        + hb_NToS( hb_HGetDef( hRes, "edges", 0 ) ) + ' other table(s) touched)' )

RETURN Self:Finish( URedirect( URoute( 'part.grid' ) ) )


// -------------------------------------------------------------- //
// Flash: the module's own, drained once read (D-10 in the audited module).
// -------------------------------------------------------------- //

METHOD FlashFail( cMessage, hErrors, hInput ) CLASS PartControllers

   UFlash( 'part' ):Set( { ;
      "type"    => 'danger', ;
      "message" => cMessage, ;
      "errors"  => iif( ValType( hErrors ) == 'H', hErrors, ;
                        { => } ) ;
   } )

RETURN NIL


METHOD FlashOk( cMessage ) CLASS PartControllers

   UFlash( 'part' ):Set( { ;
      "type"    => 'success', ;
      "message" => cMessage ;
   } )

RETURN NIL


METHOD TakeFlash() CLASS PartControllers

   LOCAL oFlash := UFlash( 'part' )
   LOCAL hFlash := { => }

   hFlash[ 'type' ]    := oFlash:Get( 'type' )
   hFlash[ 'message' ] := oFlash:Get( 'message' )
   hFlash[ 'errors' ]  := oFlash:Get( 'errors', { => } )

   oFlash:Clear()
   oFlash:Save()

RETURN hFlash

#include 'models/tdalmysql.prg'
