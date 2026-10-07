// --------------------------------------------------------------------------------
// Supplier - CRUD for `stock_stockitem`, on the MySQL DAL
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

CLASS SupplierControllers

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

METHOD New() CLASS SupplierControllers

   ::oConn := NIL

RETURN SELF


METHOD End() CLASS SupplierControllers

RETURN SELF


METHOD Slot() CLASS SupplierControllers

   IF ::oConn == NIL
      ::oConn := WDO_Get( "mysql" )
      IF ::oConn == NIL
         Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
            { => }, NIL )
      ENDIF
   ENDIF

RETU ::oConn


METHOD Destroy() CLASS SupplierControllers

   //  the borrowed DAL objects never close it; the slot is returned once
   IF ::oConn != NIL
      ::oConn:Close()
      ::oConn := NIL
   ENDIF

RETURN NIL


METHOD Finish( xRet ) CLASS SupplierControllers

   Self:Destroy()

RETU xRet


METHOD Dal( cTable, aCols ) CLASS SupplierControllers

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

METHOD Grid() CLASS SupplierControllers

   LOCAL nPage, nRows, nTotal, nTotalPages := 0
   LOCAL aAll, aGrid := {}, aPages := {}
   LOCAL cQ, hLike := { => }
   LOCAL oDal
   LOCAL nI, aCols := { "part", "supplier", "SKU", "manufacturer_part", "link" }

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
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

   oDal := Self:Dal( "part_supplierpart", aCols )

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

RETURN Self:Finish( UView( 'masters/supplier/grid.html', aGrid, aPages, nPage, nTotalPages, ;
              nTotal, cQ, Self:TakeFlash() ) )


METHOD Search() CLASS SupplierControllers

   LOCAL cQ, hLike := { => }, aAll := {}, nTotal := 0
   LOCAL oDal
   LOCAL nI, aCols := { "part", "supplier", "SKU", "manufacturer_part", "link" }

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   cQ := Trim( UGet( 'q', '' ) )
   IF EMPTY( cQ )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "part_supplierpart", aCols )

   FOR nI := 1 TO LEN( aCols )
      hLike[ aCols[ nI ] ] := cQ
   NEXT

   aAll := oDal:FetchAll( NIL, hLike )
   IF aAll == NIL
      aAll := {}
   ENDIF
   nTotal := LEN( aAll )

   oDal:Close()

RETURN Self:Finish( UView( 'masters/supplier/grid.html', aAll, { 1 }, 1, 1, nTotal, ;
              cQ, Self:TakeFlash() ) )


METHOD Show() CLASS SupplierControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      Self:FlashFail( "That supplier listing is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "part_supplierpart", ;
                     { "part", "supplier", "SKU", "manufacturer_part", "link" } )

   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That supplier listing is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/supplier/show.html', .T., hRow, Self:TakeFlash() ) )


// -------------------------------------------------------------- //
// Writes. The form renders and the POST verb performs, so the CSRF
// middleware and the scope stay on the write side only (N-01).
// -------------------------------------------------------------- //

METHOD Edit() CLASS SupplierControllers

   LOCAL oVal, nId, hRow := NIL
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   nId  := oVal:Get( 'id' )
   oDal := Self:Dal( "part_supplierpart", ;
                     { "part", "supplier", "SKU", "manufacturer_part", "link" } )
   hRow := oDal:Show( nId )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That supplier listing is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/supplier/edit.html', 'edit', .T., hRow, ;
              Self:TakeFlash(), hb_HGetDef( hRow, "version", 0 ) ) )


METHOD Create() CLASS SupplierControllers

RETURN Self:Finish( UView( 'masters/supplier/edit.html', 'create', .F., { => }, ;
              Self:TakeFlash(), 0 ) )


METHOD Store() CLASS SupplierControllers

   LOCAL oVal, hData := { => }, nNew
   LOCAL oDal

   //  the FK columns are validated as numbers: a part id typed into a form
   //  is external input, and the DAL binds it - it is never concatenated
   oVal := UValidatePost( { ;
      "part"    => "required|number|min:0", ;
      "supplier"    => "required|number|min:0", ;
      "SKU"    => "required|string|max:100|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'supplier.create' ) ) )
   ENDIF

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   hData[ "part" ] := _NumOf( oVal:Get( 'part' ) )
   hData[ "supplier" ] := _NumOf( oVal:Get( 'supplier' ) )
   hData[ "SKU" ] := AllTrim( oVal:Get( 'SKU', '' ) )

   oDal := Self:Dal( "part_supplierpart", ;
                     { "part", "supplier", "SKU" } )
   nNew := oDal:Insert( hData )
   oDal:Close()

   IF nNew > 0
      Self:FlashOk( 'Supplier ' + hb_NToS( nNew ) + ' was created!' )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'supplier.create' ) ) )


METHOD Update() CLASS SupplierControllers

   LOCAL oVal, nId, cVersion, nVersion, hData := { => }, lOk, hErr
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   //  P3.7: the write must carry the version the caller READ. Absent it
   //  the write is refused - Val( '' ) is 0, which would have matched
   //  every record still at version 0
   cVersion := UPost( 'version', '' )
   IF Empty( cVersion )
      Self:FlashFail( "Send the version you read with the change - " ;
        + "nothing was written.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.edit', nId ) ) )
   ENDIF
   nVersion := Val( cVersion )

   oVal := UValidatePost( { ;
      "part"    => "required|number|min:0", ;
      "supplier"    => "required|number|min:0", ;
      "SKU"    => "required|string|max:100|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN Self:Finish( URedirect( URoute( 'supplier.edit', nId ) ) )
   ENDIF

   hData[ "part" ] := _NumOf( oVal:Get( 'part' ) )
   hData[ "supplier" ] := _NumOf( oVal:Get( 'supplier' ) )
   hData[ "SKU" ] := AllTrim( oVal:Get( 'SKU', '' ) )

   oDal := Self:Dal( "part_supplierpart", ;
                     { "part", "supplier", "SKU" } )
   lOk  := oDal:Update( nId, nVersion, hData )
   hErr := oDal:Errors()
   oDal:Close()

   IF lOk
      Self:FlashOk( 'Supplier ' + hb_NToS( nId ) + ' was updated!' )
      RETURN Self:Finish( URedirect( URoute( 'supplier.show', nId ) ) )
   ENDIF

   //  SRS 5.2: a conflict shows the record again, it does not overwrite
   IF hErr != NIL .AND. hErr[ "reason" ] == "conflict"
      Self:FlashFail( "Someone changed this stock item after you read it. " ;
        + "It is shown again below - nothing was overwritten.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.show', nId ) ) )
   ENDIF

   //  D8: an edge the schema did not decide is refused, not defaulted
   IF hErr != NIL .AND. hErr[ "reason" ] == "policy undecided"
      Self:FlashFail( "The delete policy for this relation is not declared. " ;
        + "Nothing was changed.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   IF hErr != NIL .AND. hErr[ "reason" ] == "not found"
      Self:FlashFail( "That supplier listing is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
     { => }, NIL )

RETURN Self:Finish( URedirect( URoute( 'supplier.edit', nId ) ) )


// -------------------------------------------------------------- //
// Delete. confirm renders what the delete WOULD touch before the
// destructive verb runs (SRS FR-DELETE-1..4).
// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS SupplierControllers

   LOCAL oVal, nId, hRow, hPrev
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "part_supplierpart", ;
                     { "part", "supplier", "SKU", "manufacturer_part", "link" } )
   hRow  := oDal:Show( nId )
   hPrev := oDal:Cascade( nId, NIL )
   oDal:Close()

   IF hRow == NIL
      Self:FlashFail( "That supplier listing is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

RETURN Self:Finish( UView( 'masters/supplier/delete.html', .T., hRow, hPrev, ;
              Self:TakeFlash(), nId ) )


METHOD delete_action() CLASS SupplierControllers

   LOCAL oVal, nId, hRes
   LOCAL oDal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   nId := oVal:Get( 'id' )

   IF Self:Slot() == NIL
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   oDal := Self:Dal( "part_supplierpart", ;
                     { "part", "supplier", "SKU", "manufacturer_part", "link" } )
   hRes := oDal:Delete( nId, NIL )
   oDal:Close()

   IF ValType( hRes ) != 'H'
      Self:FlashFail( "System temporarily unavailable. Please try again later.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   //  D4: a rolled-back cascade is not "the row was not there"
   IF hb_HGetDef( hRes, "rolledback", .F. )
      Self:FlashFail( "The delete could not be applied. Nothing was changed.", ;
        { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   IF hb_HGetDef( hRes, "deleted", 0 ) == 0
      Self:FlashFail( "That supplier listing is not there.", { => }, NIL )
      RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )
   ENDIF

   //  D5: the flash quotes the numbers the transaction applied
   Self:FlashOk( 'Supplier ' + hb_NToS( nId ) + ' was deleted (' ;
       + hb_NToS( hb_HGetDef( hRes, "deleted", 0 ) ) + ' row, ' ;
       + hb_NToS( hb_HGetDef( hRes, "edges", 0 ) ) + ' other table(s) touched)' )

RETURN Self:Finish( URedirect( URoute( 'supplier.grid' ) ) )


// -------------------------------------------------------------- //
// Flash: the module's own, drained once read (D-10).
// -------------------------------------------------------------- //

METHOD FlashFail( cMessage, hErrors, hInput ) CLASS SupplierControllers

   UFlash( 'supplier' ):Set( { ;
      "type"    => 'danger', ;
      "message" => cMessage ;
   } )

RETURN NIL


METHOD FlashOk( cMessage ) CLASS SupplierControllers

   UFlash( 'supplier' ):Set( { ;
      "type"    => 'success', ;
      "message" => cMessage ;
   } )

RETURN NIL


METHOD TakeFlash() CLASS SupplierControllers

   LOCAL oFlash := UFlash( 'supplier' )
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
