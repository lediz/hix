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
   
   nId := oVal:Get( 'id' )     // D-13: always name the field

  
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
   
   nId := oVal:Get( 'id' )     // D-13: always name the field

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
   LOCAL hSearch := { => }
   LOCAL cSearchUpper
   LOCAL nTotal, nStart, nEnd, nI
   LOCAL lMatch, lHit
   // aFields  = fields projected from the DBF (free-text 'q' may use all of them)
   // aCols    = the columns actually rendered by grid.html: each one gets a
   //            search entry (?_q_<column>) and is a legal sort key.
   LOCAL aFields := {'first','last','address','zip','country','notes'}
   LOCAL aCols   := {'first','last','address','country','zip'}
   LOCAL cAlias, hRec, nJ, cSearchParams

   // --- Pagination params ---
   nPage    := Iif( Empty( UGet( 'page', '1' ) ), 1, Val( UGet( 'page', '1' ) ) )
   IF nPage < 1
      nPage := 1
   ENDIF
   nRows    := 20   // default page size per FR-READ-2 (DAL SRS)
   // Grid hash keys are lowercase, so the sort key must be too (else the
   // lookup in SortGrid misses the key and the sort silently does nothing).
   cSort    := Lower( UGet( 'sort', 'first' ) )
   IF Ascan( aCols, cSort ) == 0
      cSort := 'first'
   ENDIF
   cDir     := Upper( UGet( 'dir', 'ASC' ) )
   // NOTE: query-string params are read with UGet(), not UParam().
   // UParam() resolves its fallback with 'cVal != xDef'; under Harbour's default
   // SET EXACT OFF (www/config.json -> sets.exact = false) any value compares
   // equal to an empty string, so UParam( key, '' ) silently returns '' for a
   // parameter that IS present.  That is why the per-field search never worked
   // here while ?sort= / ?dir= (non-empty defaults) did.
   cSearch  := Trim( UGet( 'q', '' ) )
   cSearchUpper := Upper( cSearch )

   // --- FR-READ-3: one search entry per visible grid column ---
   FOR nI := 1 TO Len( aCols )
      hSearch[ aCols[ nI ] ] := Trim( UGet( '_q_' + aCols[ nI ], '' ) )
   NEXT

   // --- Carry the active search through pagination and column-sort links ---
   cSearchParams := ''
   IF !empty( cSearch )
      cSearchParams += '&q=' + EncParam( cSearch )
   ENDIF
   FOR nI := 1 TO Len( aCols )
      IF !empty( hSearch[ aCols[ nI ] ] )
         cSearchParams += '&_q_' + aCols[ nI ] + '=' + EncParam( hSearch[ aCols[ nI ] ] )
      ENDIF
   NEXT

   // --- Recover flash messages (only show on grid, clear after reading) ---
   oFlash   := UFlash( 'customer' )
   hMessage[ 'type' ]   := oFlash:Get( 'type' )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   oFlash:Clear()
   oFlash:Save()

   // --- Open Data Access Layer ---
   oCustomers := TCustomers()

   // --- FR-READ-1/2/3: read the whole table, apply the search, sort, and only
   // then paginate the result.  The previous order cut the page out of the raw
   // table first and filtered only that page, so a match sitting on a later
   // page was invisible and the page count ignored the filter.
   cAlias := oCustomers:cAlias
   aAll := {}
   ( cAlias )->( DbGoTop() )
   DO WHILE ( cAlias )->( !Eof() )
      hRec := { => }
      hRec[ '_recno' ] := ( cAlias )->( RecNo() )
      hRec[ '_deleted' ] := ( cAlias )->( Deleted() )
      FOR nJ := 1 TO Len( aFields )
         hRec[ aFields[ nJ ] ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( aFields[ nJ ] ) ) ) )
      NEXT

      lMatch := .T.

      // Free-text 'q': the query must be contained in one of the projected fields
      IF !empty( cSearchUpper )
         lHit := .F.
         FOR nJ := 1 TO Len( aFields )
            IF cSearchUpper $ Upper( HB_HGetDef( hRec, aFields[ nJ ], '' ) )
               lHit := .T.
            ENDIF
         NEXT
         IF !lHit
            lMatch := .F.
         ENDIF
      ENDIF

      // Per-column entries: AND between columns, containment within the column
      FOR nJ := 1 TO Len( aCols )
         IF !empty( hSearch[ aCols[ nJ ] ] )
            IF ! ( Upper( hSearch[ aCols[ nJ ] ] ) $ Upper( HB_HGetDef( hRec, aCols[ nJ ], '' ) ) )
               lMatch := .F.
            ENDIF
         ENDIF
      NEXT

      IF lMatch
         aAdd( aAll, hRec )
      ENDIF
      ( cAlias )->( DbSkip() )
   ENDDO

   // --- Apply column sort (FR-READ-4) to the whole filtered set ---
   IF Len( aAll ) > 1
      aAll := SortGrid( aAll, cSort, cDir )
   ENDIF

   // --- Paginate the filtered, sorted set ---
   nTotal := Len( aAll )
   IF nTotal == 0
      nTotalPages := 0
   ELSE
      nTotalPages := Int( ( nTotal + nRows - 1 ) / nRows )
   ENDIF
   IF nPage > nTotalPages
      nPage := nTotalPages
   ENDIF
   // A search that matches nothing leaves nTotalPages = 0; keep the page index
   // valid so the slice below is never asked for a negative subscript.
   IF nPage < 1
      nPage := 1
   ENDIF
   nStart := ( ( nPage - 1 ) * nRows ) + 1
   nEnd   := MIN( nStart + nRows - 1, nTotal )
   aGrid := {}
   FOR nI := nStart TO nEnd
      aAdd( aGrid, aAll[ nI ] )
   NEXT

   // --- Pagination links ---
   IF nTotalPages > 0
      aPages := PageLinks( nPage, nTotalPages )
   ELSE
      aPages := {}
   ENDIF

   // --- Render view ---
RETURN UView( 'masters/customer/grid.html', cAction, aGrid, aPages, nPage, nTotalPages, ;
              cSort, cDir, cSearch, hSearch, hMessage, hErrors, cSearchParams )
// -------------------------------------------------------------- //
// Helper: EncParam — percent-encode a search value so it survives being
// re-emitted inside pagination / column-sort links.
// -------------------------------------------------------------- //

FUNCTION EncParam( cVal )

RETURN hb_StrReplace( cVal, { '%', '&', '#', '+', ' ' }, { '%25', '%26', '%23', '%2B', '%20' } )

// -------------------------------------------------------------- //
// Helper: SortGrid — sort an array of hashes by a field name
// Parameters: aGrid, cField (lowercase, as the grid hash keys are), cDir (ASC|DESC)
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
