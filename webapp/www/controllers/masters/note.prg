// --------------------------------------------------------------------------------
// Note - CRUD for `stock_stockitem`, on the MySQL DAL
//
// P4.2 of webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md. The shape is the one
// part.prg and users.prg already established - the same nine verbs, the same
// middleware pair, the same flash + redirect for writes - so what is new here
// is only what sits behind the verbs.
//
// What the DAL, not this module, decides:
//   P3.7  the write carries the version it read; a stale one is refused
//   D2    the NULL delete policy is refused on a NOT NULL FK column
//   D4    the cascade is one transaction; a refused one changes nothing
//   D8    an edge the schema did not decide is refused, not defaulted
//
// P4.2 is where the FK policy becomes observable: stock_stockitem FKs to
// part_part (policy=CASCADE) and to stock_stocklocation (policy=NULL), so
// deleting a part removes the stock items that were its inventory, and
// deleting a location leaves the items with no location rather than
// deleting them.
// --------------------------------------------------------------------------------

#include 'hbclass.ch'

CLASS NoteControllers

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
   METHOD FlashFail( cMessage, hErrors, hInput )
   METHOD FlashOk( cMessage )
   METHOD TakeFlash()

ENDCLASS

// -------------------------------------------------------------- //

METHOD New() CLASS NoteControllers

   ::oConn := NIL

RETURN SELF


METHOD End() CLASS NoteControllers

RETURN SELF


METHOD Slot() CLASS NoteControllers

   IF ::oConn == NIL
      ::oConn := WDO_Get( "mysql" )
      IF ::oConn == NIL
         Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
            { => }, NIL )
      ENDIF
   ENDIF

RETU ::oConn


METHOD Destroy() CLASS NoteControllers

   //  the borrowed DAL objects never close it; the slot is returned once
   IF ::oConn != NIL
      ::oConn:Close()
      ::oConn := NIL
   ENDIF

RETURN NIL


METHOD Finish( xRet ) CLASS NoteControllers

   Self:Destroy()

RETU xRet


METHOD Dal( cTable, aCols ) CLASS NoteControllers

   LOCAL oDal := NIL

   IF Self:Slot() != NIL
      oDal := TDalMySql():New( cTable, aCols )
      oDal:Attach( ::oConn )
   ENDIF

RETU oDal


// -------------------------------------------------------------- //
// Reads. The whitelist is this module's declaration, not the form's:
// a key the caller sends that is not in here is dropped by the DAL and
// logged, never quoted into a statement (P3.2).
// -------------------------------------------------------------- //

METHOD Grid() CLASS NoteControllers

   LOCAL nPage, nRows, nTotal, nTotalPages := 0
   LOCAL aAll, aGrid := {}, aPages := {}
   LOCAL cQ, hLike := { => }
   LOCAL oDal
   LOCAL nI, aCols := { "title", "description", "content", "updated_by" }

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   nPage := Iif( Empty( UGet( 'page', '' ) ), 1, Val( UGet( 'page', '' ) ) )
   IF nPage < 1
      nPage := 1
   ENDIF
   nRows := 20

   cQ := Trim( UGet( 'q', '' ) )
   IF ! EMPTY( cQ )
      FOR nI := 1 TO LEN( aCols )
         hLike[ aCols[ nI ] ] := cQ
      NEXT
   ENDIF

   oDal := Self:Dal( "common_note", aCols )

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

RETURN Self:Finish( UView( 'masters/note/grid.html', aGrid, aPages, nPage, nTotalPages, ;
              nTotal, cQ, Self:TakeFlash() ) )


METHOD Search() CLASS NoteControllers

   LOCAL cQ, hLike := { => }, aAll := {}, nTotal := 0
   LOCAL oDal
   LOCAL nI, aCols := { "title", "description", "content", "updated_by" }

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   cQ := Trim( UGet( 'q', '' ) )
   IF EMPTY( cQ )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "common_note", aCols )

   FOR nI := 1 TO LEN( aCols )
      hLike[ aCols[ nI ] ] := cQ
   NEXT

   aAll := oDal:FetchAll( NIL, hLike )
   IF aAll == NIL
      aAll := {}
   ENDIF
   nTotal := LEN( aAll )

   oDal:Close()

RETURN Self:Finish( UView( 'masters/note/grid.html', aAll, { 1 }, 1, 1, nTotal, ;
              cQ, Self:TakeFlash() ) )


METHOD Show() CLASS NoteControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      Self:FlashFail( "That note is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "common_note", ;
                     { "title", "description", "content", "updated_by" } )

   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That note is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/note/show.html', .T., hRow, Self:TakeFlash() ) )


// -------------------------------------------------------------- //
// Writes. The form renders and the POST verb performs, so the CSRF
// middleware and the scope stay on the write side only (N-01).
// -------------------------------------------------------------- //

METHOD Edit() CLASS NoteControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "common_note", ;
                     { "title", "description", "content", "updated_by" } )
   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That note is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/note/edit.html', 'edit', .T., hRow, ;
              Self:TakeFlash(), hb_HGetDef( hRow, "version", 0 ) ) )


METHOD Create() CLASS NoteControllers

RETURN Self:Finish( UView( 'masters/note/edit.html', 'create', .F., { => }, ;
              Self:TakeFlash(), 0 ) )


METHOD Store() CLASS NoteControllers

   LOCAL oVal, hData := { => }, nNew
   LOCAL oDal

   //  the FK columns are validated as numbers: a part id typed into a form
   //  is external input, and the DAL binds it - it is never concatenated
   oVal := UValidatePost( { ;
      "title"    => "required|string|max:100|field", ;
      "content"    => "required|string|max:100|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'note.create' ) ) )
   ENDIF

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   hData[ "title" ] := AllTrim( oVal:Get( 'title', '' ) )
   hData[ "content" ] := AllTrim( oVal:Get( 'content', '' ) )

   oDal := Self:Dal( "common_note", ;
                     { "title", "content" } )
   nNew := oDal:Insert( hData )
   oDal:Close()

   IF nNew > 0
      Self:FlashOk( 'Note ' + hb_NToS( nNew ) + ' was created!' )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'note.create' ) ) )


METHOD Update() CLASS NoteControllers

   LOCAL oVal, nId, cVersion, nVersion, hData := { => }, lOk, hErr
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   //  P3.7: the write must carry the version the caller READ. Absent it
   //  the write is refused - Val( '' ) is 0, which would have matched
   //  every record still at version 0
   cVersion := UPost( 'version', '' )
   IF Empty( cVersion )
      Self:FlashFail( "Send the version you read with the change - " ;
        + "nothing was written.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.edit', nId ) ) )
   ENDIF
   nVersion := Val( cVersion )

   oVal := UValidatePost( { ;
      "title"    => "required|string|max:100|field", ;
      "content"    => "required|string|max:100|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'note.edit', nId ) ) )
   ENDIF

   hData[ "title" ] := AllTrim( oVal:Get( 'title', '' ) )
   hData[ "content" ] := AllTrim( oVal:Get( 'content', '' ) )

   oDal := Self:Dal( "common_note", ;
                     { "title", "content" } )
   lOk  := oDal:Update( nId, nVersion, hData )
   hErr := oDal:Errors()
   oDal:Close()

   IF lOk
      Self:FlashOk( 'Note ' + hb_NToS( nId ) + ' was updated!' )
      RETURN Self:Finish( URedirect( URoute( 'note.show', nId ) ) )
   ENDIF

   //  SRS 5.2: a conflict shows the record again, it does not overwrite
   IF hErr != NIL .AND. hErr[ "reason" ] == "conflict"
      Self:FlashFail( "Someone changed this stock item after you read it. " ;
        + "It is shown again below - nothing was overwritten.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.show', nId ) ) )
   ENDIF

   //  D8: an edge the schema did not decide is refused, not defaulted
   IF hErr != NIL .AND. hErr[ "reason" ] == "policy undecided"
      Self:FlashFail( "The delete policy for this relation is not declared. " ;
        + "Nothing was changed.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   IF hErr != NIL .AND. hErr[ "reason" ] == "not found"
      Self:FlashFail( "That note is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'note.edit', nId ) ) )


// -------------------------------------------------------------- //
// Delete. confirm renders what the delete WOULD touch before the
// destructive verb runs (SRS FR-DELETE-1..4).
// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS NoteControllers

   LOCAL oVal, nId, hRow, hPrev
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "common_note", ;
                     { "title", "description", "content", "updated_by" } )
   hRow  := oDal:Show( nId )
   hPrev := oDal:Cascade( nId, NIL )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That note is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/note/delete.html', .T., hRow, hPrev, ;
              Self:TakeFlash(), nId ) )


METHOD delete_action() CLASS NoteControllers

   LOCAL oVal, nId, hRes
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "common_note", ;
                     { "title", "description", "content", "updated_by" } )
   hRes := oDal:Delete( nId, NIL )
   oDal:Close()

   IF ValType( hRes ) != 'H'
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   //  D4: a rolled-back cascade is not "the row was not there"
   IF hb_HGetDef( hRes, "rolledback", .F. )
      Self:FlashFail( "The delete could not be applied. Nothing was changed.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   IF hb_HGetDef( hRes, "deleted", 0 ) == 0
      Self:FlashFail( "That note is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )
   ENDIF

   //  D5: the flash quotes the numbers the transaction applied
   Self:FlashOk( 'Note ' + hb_NToS( nId ) + ' was deleted (' ;
       + hb_NToS( hb_HGetDef( hRes, "deleted", 0 ) ) + ' row, ' ;
       + hb_NToS( hb_HGetDef( hRes, "edges", 0 ) ) + ' other table(s) touched)' )

RETURN Self:Finish( URedirect( URoute( 'note.grid' ) ) )


// -------------------------------------------------------------- //
// Flash: the module's own, drained once read (D-10).
// -------------------------------------------------------------- //

METHOD FlashFail( cMessage, hErrors, hInput ) CLASS NoteControllers

   UFlash( 'note' ):Set( { ;
      "type"    => 'danger', ;
      "message" => cMessage ;
   } )

RETURN NIL


METHOD FlashOk( cMessage ) CLASS NoteControllers

   UFlash( 'note' ):Set( { ;
      "type"    => 'success', ;
      "message" => cMessage ;
   } )

RETURN NIL


METHOD TakeFlash() CLASS NoteControllers

   LOCAL oFlash := UFlash( 'note' )
   LOCAL hFlash := { => }

   hFlash[ 'type' ]    := oFlash:Get( 'type' )
   hFlash[ 'message' ] := oFlash:Get( 'message' )
   hFlash[ 'errors' ]  := oFlash:Get( 'errors', { => } )

   oFlash:Clear()
   oFlash:Save()

RETURN hFlash

//  UValidatePost's number rule validates the text; what comes back through
//  Get() is not guaranteed to be a Harbour number, and Val( NIL ) is a BASE
//  error that turns the whole verb into a 500 - so the conversion is guarded
STATIC FUNCTION _NumOf( xVal )

   IF ValType( xVal ) == 'N'
      RETU xVal
   ENDIF

   IF ValType( xVal ) == 'C' .AND. ! EMPTY( xVal )
      RETU VAL( xVal )
   ENDIF

RETU 0

#include 'models/tdalmysql.prg'
