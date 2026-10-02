#include 'hbclass.ch'	

//#xtranslate Throw( <oErr> ) => ( Eval( ErrorBlock(), <oErr> ), Break( <oErr> ) )

CLASS Customer

	//DATA lAuthorization	 INIT .t.

	METHOD New()			 CONSTRUCTOR 
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
	
ENDCLASS 

// -------------------------------------------------------------- //

METHOD New() CLASS Customer

	_d( 'NEW() -->> ' + Self:ClassName() )	
	
RETU SELF 

// -------------------------------------------------------------- //

METHOD End() CLASS Customer
	
RETU SELF 

// -------------------------------------------------------------- //

METHOD Search() CLASS Customer

RETU UView( 'masters/customer/search.html' )

// -------------------------------------------------------------- //

METHOD Show() CLASS Customer

   LOCAL hrow := {=>}
   LOCAL hMessage := {=>}
   LOCAL oVal, oCustomers

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id",        "" } ;
   } )
   
   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0

      UFlash( "customer" ):Set( { "errors" => oVal:GetErrors(), "message" => "Error validacion",  "input" => oVal:Resume(), "type" => 'danger' } )
      RETURN URedirect( URoute( 'customer.search' ) )      
   ENDIF

   oCustomers := TCustomers()   
   
   lFound := oCustomers:GetRecno( oVal:Get( 'id'), @hRow, NIL , .T. )  // .T. == to String Web            

   if lFound 
      oFlash   := UFlash( 'customer' )
      
      hMessage[ 'type' ]      := oFlash:Get( 'type' )
      hMessage[ 'message' ]   := oFlash:Get( 'message' )
      oFlash:Clear()
      oFlash:Save()
      
   else 
      hRow := oCustomers:Blank( .t. )
   endif     
RETU UView( 'masters/customer/show.html', lFound, hRow, hMessage )

// -------------------------------------------------------------- //
// "url": "/customer/:id" -> we need chek if :id number & > 0  
// "url": "/customer/:id([0-9]+)" -> we have a expression ! only numbers

METHOD Edit() CLASS Customer

   LOCAL oVal, oCustomers, lFound, oFlash
   LOCAL hMessage := {=>}
   LOCAL hRow := {=>}

   oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" }  })   

   IF ! oVal:Make()     
      RETU URedirect( URoute( 'customer.search' ) )      
   ENDIF

   
   // Recover data flash if it exist
      oFlash := UFlash('customer')

      hMessage[ 'type' ]      := oFlash:Get('type')
      hMessage[ 'message' ]   := oFlash:Get('message')
      hInput                  := oFlash:Get('input')
      hErrors                 := oFlash:Get('errors', {=>})    
   
   
   // Si existeix Input es que viene de una EDIT

   if !empty( hInput )         
      RETU UView( 'masters/customer/edit.html', 'edit', .T., hInput, hMessage, hErrors )        
   endif 
   
   oCustomers  := TCustomers() 
   
   
   // Si no hay input, es una simple edicion para editar. Buscaremos registro   

   lFound := oCustomers:GetRecno( oVal:Get( 'id'), @hRow, NIL , .T. )  // .T. == to String Web 
   
   if !lFound 
      hRow := oCustomers:Blank( .t. )
   endif 

   if hb_IsHash( hInput )
      hRow := hInput
   endif

   if empty( hErrors )
      hErrors := {=>}
   endif 

RETU UView( 'masters/customer/edit.html', 'edit', lFound, hRow, hMessage, hErrors )

// -------------------------------------------------------------- //

METHOD Create() CLASS Customer

   LOCAL oCustomers, oFlash, hRow
   LOCAL hMessage 	:= {=>}   
   LOCAL hErrors 	:= {=>}   

	oCustomers  := TCustomers() 

   oFlash := UFlash('customer')

   hMessage[ 'type' ]      := oFlash:Get('type')
   hMessage[ 'message' ]   := oFlash:Get('message')
   hInput                  := oFlash:Get('input')	
	hErrors                 := oFlash:Get('errors', {=>} ) 
	

	if ! empty( hInput )	
		hRow := hInput 		
	else		

		hRow := oCustomers:Blank( .t. )	// .t. == to web string
	endif 
RETU UView( 'masters/customer/edit.html', 'create', .F., hRow, hMessage, hErrors )
// -------------------------------------------------------------- //

METHOD Update() CLASS Customer

   LOCAL oVal, nId, cError, lSuccess
   LOCAL hMessage := {=>}
   LOCAL hResume
   LOCAL oCustomers
   LOCAL hChanges
 
   // Get ID from URL route parameter
   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )
   
   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0
      retu URedirect( URoute( 'customer.search' ) )
   ENDIF
   
   nId := oVal:Get()

  
   // Validamos campos (Update).
   //
   // NOTA H8: _deleted NO va en las reglas — es un flag interno del DBF.
   // Se preserva del form via UPost para re-mostrar el estado en la vista
   // tras un fallo de validación, pero nunca se copia a DataFields().

      oVal  := UValidatePost( { ;
               "first"    	=> "required|string|max:20|field", ;
               "last"     	=> "required|string|max:20|field", ;
               "zip"   	   => "required|string|max:10|field", ;
               "address"   => "required|string|max:120|field", ;
               "country"   => "required|string|max:50|field", ;
               "notes"     => "string|field";
            }, { 'dummy' => 'upper|trim' } )
     if ! oVal:Make()

         hResume := oVal:Resume()
         hResume[ '_deleted' ] := Val( UPost( '_deleted', '.F.' ) ) == 1

         UFlash("customer"):Set( { ;
            "type"   => 'danger',          ;
            "message" => 'Error validacion',;
            "errors" => oVal:GetErrors(),  ;
            "input"  => hResume            ;
         })

         retu URedirect( URoute( 'customer.edit', nId ) )

      endif
   // Open DataSource 
      oCustomers  := TCustomers() 
   
      // Convert numeric/logical fields to DBF-compatible string format
      hChanges := oVal:DataFields()
   
      lSuccess := oCustomers:Update( nId, hChanges, @cError )

      if lSuccess

         UFlash("customer"):Set( { ;
            "type"    => 'success',          ;
            "message" => 'Customer ' + ltrim(str(nId)) + ' was updated!' ;
         })

         retu URedirect( URoute( 'customer.show', nId ) )

      else

         hResume := oVal:Resume()
         hResume[ '_deleted' ] := Val( UPost( '_deleted', '.F.' ) ) == 1

         UFlash("customer"):Set( { ;
            "type"    => 'danger',         ;
            "message" => cError,           ;
            "errors"  => {=>},             ;
            "input"   => hResume           ;
         })

         retu URedirect( URoute('customer.edit', nId) )

      endif

RETU nil

// -------------------------------------------------------------- //

// -------------------------------------------------------------- //

METHOD Store() CLASS Customer

   
   LOCAL oVal, nId, cError, lSuccess, nRecno
   LOCAL o 
   LOCAL hMessage := {=>}
   LOCAL oError
  
   // Validamos campos (Store).

      oVal  := UValidatePost( { ;
               "first"    	=> "required|string|max:20|field", ;
               "last"     	=> "required|string|max:20|field", ;
               "zip"   	    => "required|string|max:10|field", ;
               "address"   => "required|string|max:120|field", ;
               "country"   => "required|string|max:50|field", ;
               "notes"      => "string|field";
            }, { 'dummy' => 'upper|trim' } )
     if ! oVal:Make() 

         UFlash("customer"):Set( { ;
            "type"   => 'danger',          ;
            "message" => 'Error validacion',; 
            "errors" => oVal:GetErrors(),  ;
            "input"  => oVal:Resume()      ;
         })
   
         retu URedirect( URoute( 'customer.create' ) )

      endif 

 
   // Open DataSource 
      oCustomers  := TCustomers() 
   

      if lSuccess      
      
         UFlash("customer"):Set( { ;
            "type"   => 'success',          ;
            "message" => 'Customer ' + ltrim(str(nRecno)) + ' was created!';
         })    
         
         retu URedirect( URoute( 'customer.grid' ) )    
         
      else 

         UFlash("customer"):Set( { ;
            "type"    => 'danger',         ;
            "message" => cError,           ;
            "errors"  => {=>},  ;
            "input"   => oVal:Resume()     ;
         })
         
         retu URedirect( URoute('customer.create' ) )     
         
      endif 

RETU nil 

// -------------------------------------------------------------- //

// -------------------------------------------------------------- //
// P0: Paginated Data Grid — FR-READ-1 / FR-READ-2 (DAL SRS)
// Uses UDbf:LoadAll() + UDbf:Page() for server-side pagination
// Supports column sorting via ?sort=field&dir=asc|desc
// Supports multi-record search via ?q=search_term (FR-READ-3)
// -------------------------------------------------------------- //

// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS Customer

   LOCAL oVal, oCustomers
   LOCAL hRow := {=>}
   LOCAL lFound := .F.

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )
   
   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0
      retu URedirect( URoute( 'customer.grid' ) )
   ENDIF
   
   oCustomers := TCustomers()   
   
   lFound := oCustomers:GetRecno( oVal:Get( 'id'), @hRow, NIL , .T. )
   
   if lFound
   endif
     
RETU UView( 'masters/customer/delete.html', lFound, hRow )

// -------------------------------------------------------------- //

METHOD delete_action() CLASS Customer

   LOCAL oVal, nId, lIsDeleted
   LOCAL oCustomers
   LOCAL hRow := {=>}

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )
   
   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0
      retu URedirect( URoute( 'customer.grid' ) )
   ENDIF
   
   nId := oVal:Get()

   oCustomers := TCustomers()

   if ! oCustomers:GetRecno( nId, @hRow )
      retu URedirect( URoute( 'customer.grid' ) )
   endif

   if oCustomers:Delete( nId, .T., @lIsDeleted )
      retu URedirect( URoute( 'customer.grid' ) )
   endif

   retu URedirect( URoute( 'customer.grid' ) )

// -------------------------------------------------------------- //

METHOD Grid() CLASS Customer

   LOCAL oCustomers
   LOCAL nPage, nRows, nTotalPages := 0
   LOCAL aPages, aGrid, aAll
   LOCAL cSort, cDir, cSearch
   LOCAL hMessage := {=>}
   LOCAL oFlash
   LOCAL cAction := 'grid'
   LOCAL hErrors := {=>}
   LOCAL cSearchUpper
   LOCAL nTotal, nStart, nEnd, nI
   LOCAL aFiltered
   LOCAL aFields := {'first','last','address','zip','country','notes'}
   LOCAL cAlias, nRecCount, hRec, nJ

   // --- Pagination params ---
   nPage    := Iif( Empty( UParam( 'page', '1' ) ), 1, Val( UParam( 'page', '1' ) ) )
   nRows    := 20   // default page size per FR-READ-2 (DAL SRS)
   cSort    := Upper( UParam( 'sort', 'first' ) )
   cDir     := Upper( UParam( 'dir', 'ASC' ) )
   cSearch  := Trim( UParam( 'q', '' ) )
   cSearchUpper := Upper( cSearch )

   // --- Recover flash messages (only show on grid, clear after reading) ---
   oFlash   := UFlash( 'customer' )
   hMessage[ 'type' ]   := oFlash:Get( 'type' )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   oFlash:Clear()
   oFlash:Save()

   // --- Open Data Access Layer ---
   oCustomers := TCustomers()

   // --- FR-READ-2: Direct DBF read (bypassing LoadAll/Row/Normalize) ---
   cAlias := oCustomers:cAlias
   nRecCount := ( cAlias )->( RecCount() )
   nTotal := nRecCount
   IF nTotal == 0
      nTotalPages := 0
   ELSE
      nTotalPages := Int( ( nTotal + nRows - 1 ) / nRows )
   ENDIF
   IF nPage > nTotalPages
      nPage := nTotalPages
   ENDIF
   nStart := ( ( nPage - 1 ) * nRows ) + 1
   nEnd := MIN( nStart + nRows - 1, nTotal )
   aGrid := {}
   ( cAlias )->( DbGoTop() )
   IF nStart > 1
      ( cAlias )->( DbGoTo( nStart ) )
   ENDIF
   nJ := 0
   DO WHILE nJ < nRows .AND. ( cAlias )->( !Eof() )
      hRec := { => }
      hRec[ '_recno' ] := ( cAlias )->( RecNo() )
      hRec[ '_deleted' ] := ( cAlias )->( Deleted() )
      hRec[ 'first' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'first' ) ) ) )
      hRec[ 'last' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'last' ) ) ) )
      hRec[ 'address' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'address' ) ) ) )
      hRec[ 'country' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'country' ) ) ) )
      hRec[ 'zip' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'zip' ) ) ) )
      hRec[ 'notes' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'notes' ) ) ) )
      aAdd( aGrid, hRec )
      ( cAlias )->( DbSkip() )
      nJ++
   ENDDO

   // --- FR-READ-3: Multi-record search (if search term provided) ---
   IF !empty( cSearch )
      cSearchUpper := Upper( cSearch )
      aFiltered := {}
      FOR nI := 1 TO Len( aGrid )
         IF Upper( HB_HGetDef( aGrid[ nI ], 'first', '' ) ) $ cSearchUpper .OR. ;
            Upper( HB_HGetDef( aGrid[ nI ], 'last', '' ) ) $ cSearchUpper .OR. ;
            Upper( HB_HGetDef( aGrid[ nI ], 'zip', '' ) ) $ cSearchUpper .OR. ;
            Upper( HB_HGetDef( aGrid[ nI ], 'notes', '' ) ) $ cSearchUpper .OR. ;
            Upper( HB_HGetDef( aGrid[ nI ], 'address', '' ) ) $ cSearchUpper .OR. ;
            Upper( HB_HGetDef( aGrid[ nI ], 'country', '' ) ) $ cSearchUpper
            aAdd( aFiltered, aGrid[ nI ] )
         ENDIF
      NEXT
      aGrid := aFiltered
   ENDIF

   // --- Apply column sort (FR-READ-4) ---
   IF !empty( cSort ) .AND. Len( aGrid ) > 1
      aGrid := SortGrid( aGrid, cSort, cDir )
   ENDIF

   // --- Ensure aGrid is never empty after sort (guard against empty input) ---
   IF empty( aGrid )
      aGrid := {}
   ENDIF

   // --- Pagination links ---
   IF nTotalPages > 0
      aPages := PageLinks( nPage, nTotalPages )
   ELSE
      aPages := {}
   ENDIF

   // --- Render view ---
RETURN UView( 'masters/customer/grid.html', cAction, aGrid, aPages, nPage, nTotalPages, ;
              cSort, cDir, cSearch, hMessage, hErrors )
// -------------------------------------------------------------- //
// Helper: SortGrid — sort an array of hashes by a field name
// Parameters: aGrid, cField (uppercase), cDir (ASC|DESC)
// Returns: sorted array of hashes
// -------------------------------------------------------------- //

FUNCTION SortGrid( aGrid, cField, cDir )

   LOCAL aCopy := {}, nI, nLen, nJ
   LOCAL cKey, cValI, cValJ
   LOCAL lSwap

   // Guard: empty array - no sort needed
   IF Empty( aGrid )
      RETURN {}
   ENDIF

   FOR nI := 1 TO Len( aGrid )
      aAdd( aCopy, aGrid[ nI ] )
   NEXT

   nLen := Len( aCopy )

   // Bubble sort (fine for page-sized arrays of 20)
   FOR nI := 1 TO nLen - 1
      lSwap := .F.
      FOR nJ := 1 TO nLen - nI
         cKey := aCopy[ nJ ]
         cValI := HB_HGetDef( cKey, cField, '' )
         cValJ := HB_HGetDef( aCopy[ nJ + 1 ], cField, '' )

         IF cDir == 'ASC'
            IF cValI > cValJ
               lSwap := .T.
            ENDIF
         ELSE
            IF cValI < cValJ
               lSwap := .T.
            ENDIF
         ENDIF

         IF lSwap
            aCopy[ nJ ] := aCopy[ nJ + 1 ]
            aCopy[ nJ + 1 ] := cKey
         ENDIF
      NEXT
   NEXT

RETURN aCopy

// -------------------------------------------------------------- //
// Helper: PageLinks — generate pagination link array
// Parameters: nCurrentPage, nTotalPages
// Returns: array of page numbers to display
// -------------------------------------------------------------- //

// -------------------------------------------------------------- //
// Helper: PageLinks — generate pagination link array
// Parameters: nCurrentPage, nTotalPages
// Returns: array of page numbers to display
// -------------------------------------------------------------- //

FUNCTION PageLinks( nPage, nTotalPages )

   LOCAL aPages := {}
   LOCAL nStart, nEnd, nI

   IF nTotalPages <= 10
      nStart := 1
      nEnd   := nTotalPages
   ELSE
      nStart := nPage - 4
      IF nStart < 1
         nStart := 1
      ENDIF
      nEnd := nStart + 9
      IF nEnd > nTotalPages
         nEnd := nTotalPages
      ENDIF
   ENDIF

   FOR nI := nStart TO nEnd
      aAdd( aPages, nI )
   NEXT

RETURN aPages

// -------------------------------------------------------------- //

METHOD Destroy() CLASS Customer

   dbcloseall()

RETU nil 

// -------------------------------------------------------------- //

#include 'models/tcustomers.prg'
#include 'models/tstates.prg'
// force recompile
// recompile
// recompile
