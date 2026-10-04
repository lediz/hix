// --------------------------------------------------------------------------------
// UsersController — CRUD for users.dbf
// Pattern: follows www/controllers/masters/customer.prg exactly
// Complies with DEV-compliance.md: HIX framework only, no SQL, local git
// --------------------------------------------------------------------------------

#include 'hbclass.ch'

CLASS UsersController

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

ENDCLASS

// -------------------------------------------------------------- //

METHOD New() CLASS UsersController

   _d( 'NEW() -->> ' + Self:ClassName() )

RETURN SELF

// -------------------------------------------------------------- //

METHOD End() CLASS UsersController

RETURN SELF

// -------------------------------------------------------------- //

METHOD Search() CLASS UsersController

RETURN UView( 'masters/users/search.html' )

// -------------------------------------------------------------- //

METHOD Show() CLASS UsersController

   LOCAL hRow := { => }
   LOCAL hMessage := { => }
   LOCAL oVal, oUsers

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0
      UFlash( "users" ):Set( { "errors" => oVal:GetErrors(), "message" => "Error validacion", "input" => oVal:Resume(), "type" => 'danger' } )
      RETURN URedirect( URoute( 'users.search' ) )
   ENDIF

   oUsers := TUsers()

   lFound := oUsers:GetRecno( oVal:Get( 'id'), @hRow, NIL, .T. )  // .T. == to String Web

   IF lFound
      oFlash := UFlash( 'users' )
      hMessage[ 'type' ]      := oFlash:Get( 'type' )
      hMessage[ 'message' ]   := oFlash:Get( 'message' )
      oFlash:Clear()
      oFlash:Save()
   ELSE
      hRow := oUsers:Blank( .t. )
   ENDIF

RETURN UView( 'masters/users/show.html', lFound, hRow, hMessage )

// -------------------------------------------------------------- //

METHOD Edit() CLASS UsersController

   LOCAL oVal, oUsers, lFound, oFlash
   LOCAL hMessage := { => }
   LOCAL hRow := { => }

   oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )

   IF ! oVal:Make()
      RETURN URedirect( URoute( 'users.search' ) )
   ENDIF

   // Recover data flash if it exist
   oFlash := UFlash( 'users' )
   hMessage[ 'type' ]      := oFlash:Get( 'type' )
   hMessage[ 'message' ]   := oFlash:Get( 'message' )
   hInput                  := oFlash:Get( 'input' )
   hErrors                 := oFlash:Get( 'errors', { => } )

   IF !empty( hInput )
      RETURN UView( 'masters/users/edit.html', 'edit', .T., hInput, hMessage, hErrors )
   ENDIF

   oUsers := TUsers()

   lFound := oUsers:GetRecno( oVal:Get( 'id'), @hRow, NIL, .T. )  // .T. == to String Web

   IF !lFound
      hRow := oUsers:Blank( .t. )
   ENDIF

   IF hb_IsHash( hInput )
      hRow := hInput
   ENDIF

   IF empty( hErrors )
      hErrors := { => }
   ENDIF

RETURN UView( 'masters/users/edit.html', 'edit', lFound, hRow, hMessage, hErrors )

// -------------------------------------------------------------- //

METHOD Create() CLASS UsersController

   LOCAL oUsers, oFlash, hRow
   LOCAL hMessage := { => }
   LOCAL hErrors := { => }

   oUsers := TUsers()

   oFlash := UFlash( 'users' )
   hMessage[ 'type' ]      := oFlash:Get( 'type' )
   hMessage[ 'message' ]   := oFlash:Get( 'message' )
   hInput                  := oFlash:Get( 'input' )
   hErrors                 := oFlash:Get( 'errors', { => } )

   IF !empty( hInput )
      hRow := hInput
   ELSE
      hRow := oUsers:Blank( .t. )  // .t. == to web string
   ENDIF

RETURN UView( 'masters/users/edit.html', 'create', .F., hRow, hMessage, hErrors )

// -------------------------------------------------------------- //

METHOD Update() CLASS UsersController

   LOCAL oVal, nId, cError, lSuccess
   LOCAL hMessage := { => }
   LOCAL hResume
   LOCAL oUsers
   LOCAL hChanges

   // Get ID from URL route parameter
   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0
      RETURN URedirect( URoute( 'users.search' ) )
   ENDIF

   nId := oVal:Get()

   // Validamos campos (Update).
   // ROLES field: semicolon-separated ops (e.g. "customers:search;show;edit")
   oVal := UValidatePost( { ;
      "name"    => "required|string|max:40|field", ;
      "pass"    => "required|string|min:4|field", ;
      "roles"   => "required|string|max:255|field" ;
   }, { 'dummy' => 'upper|trim' } )

   IF ! oVal:Make()
      hResume := oVal:Resume()

      UFlash( "users" ):Set( { ;
         "type"   => 'danger',          ;
         "message" => 'Error validacion',;
         "errors" => oVal:GetErrors(),  ;
         "input"  => hResume ;
      } )

      RETURN URedirect( URoute( 'users.edit', nId ) )
   ENDIF

   // Open DataSource
   oUsers := TUsers()

   // Convert fields to DBF-compatible string format
   hChanges := oVal:DataFields()

   lSuccess := oUsers:Update( nId, hChanges, @cError )

   IF lSuccess
      UFlash( "users" ):Set( { ;
         "type"    => 'success',          ;
         "message" => 'User ' + ltrim(str(nId)) + ' was updated!' ;
      } )
      RETURN URedirect( URoute( 'users.show', nId ) )
   ELSE
      hResume := oVal:Resume()

      UFlash( "users" ):Set( { ;
         "type"    => 'danger',         ;
         "message" => cError,           ;
         "errors"  => { => },           ;
         "input"   => hResume ;
      } )

      RETURN URedirect( URoute( 'users.edit', nId ) )
   ENDIF

RETURN nil

// -------------------------------------------------------------- //

METHOD Store() CLASS UsersController

   LOCAL oVal, nId, cError, lSuccess, nRecno
   LOCAL o
   LOCAL hMessage := { => }
   LOCAL oError

   // Validamos campos (Store).
   oVal := UValidatePost( { ;
      "name"    => "required|string|max:40|field", ;
      "pass"    => "required|string|min:4|field", ;
      "roles"   => "required|string|max:255|field" ;
   }, { 'dummy' => 'upper|trim' } )

   IF ! oVal:Make()
      UFlash( "users" ):Set( { ;
         "type"   => 'danger',          ;
         "message" => 'Error validacion',;
         "errors" => oVal:GetErrors(),  ;
         "input"  => oVal:Resume() ;
      } )

      RETURN URedirect( URoute( 'users.create' ) )
   ENDIF

   // Open DataSource
   oUsers := TUsers()

   // D-03 fix: persist the new record — the Insert() call was missing entirely
   lSuccess := oUsers:Insert( oVal:DataFields(), @cError, @nRecno )

   IF lSuccess
      UFlash( "users" ):Set( { ;
         "type"   => 'success',          ;
         "message" => 'User ' + ltrim(str(nRecno)) + ' was created!' ;
      } )

      RETURN URedirect( URoute( 'users.grid' ) )
   ELSE
      UFlash( "users" ):Set( { ;
         "type"    => 'danger',         ;
         "message" => cError,           ;
         "errors"  => { => },           ;
         "input"   => oVal:Resume() ;
      } )

      RETURN URedirect( URoute( 'users.create' ) )
   ENDIF

RETURN nil

// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS UsersController

   LOCAL oVal, oUsers
   LOCAL hRow := { => }
   LOCAL lFound := .F.

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0
      RETURN URedirect( URoute( 'users.grid' ) )
   ENDIF

   oUsers := TUsers()

   lFound := oUsers:GetRecno( oVal:Get( 'id'), @hRow, NIL, .T. )

RETURN UView( 'masters/users/delete.html', lFound, hRow )

// -------------------------------------------------------------- //

METHOD delete_action() CLASS UsersController

   LOCAL oVal, nId, lIsDeleted
   LOCAL oUsers
   LOCAL hRow := { => }

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0
      RETURN URedirect( URoute( 'users.grid' ) )
   ENDIF

   nId := oVal:Get()

   oUsers := TUsers()

   IF ! oUsers:GetRecno( nId, @hRow )
      RETURN URedirect( URoute( 'users.grid' ) )
   ENDIF

   IF oUsers:Delete( nId, .T., @lIsDeleted )
      RETURN URedirect( URoute( 'users.grid' ) )
   ENDIF

RETURN URedirect( URoute( 'users.grid' ) )

// -------------------------------------------------------------- //

METHOD Grid() CLASS UsersController

   LOCAL oUsers
   LOCAL nPage, nRows, nTotalPages := 0
   LOCAL aPages, aGrid, aAll
   LOCAL cSort, cDir, cSearch
   LOCAL hMessage := { => }
   LOCAL oFlash
   LOCAL cAction := 'grid'
   LOCAL hErrors := { => }
   LOCAL hSearch := { => }
   LOCAL cSearchUpper
   LOCAL nTotal, nStart, nEnd, nI
   LOCAL aFiltered, lMatch
   LOCAL aFields := {'name','pass','roles'}
   LOCAL cAlias, nRecCount, hRec, nJ, cSearchParams

   // --- Pagination params ---
   nPage    := Iif( Empty( UParam( 'page', '1' ) ), 1, Val( UParam( 'page', '1' ) ) )
   nRows    := 20   // default page size per FR-READ-2 (DAL SRS)
   cSort    := Upper( UParam( 'sort', 'name' ) )
   cDir     := Upper( UParam( 'dir', 'ASC' ) )
   cSearch  := Trim( UParam( 'q', '' ) )
   cSearchUpper := Upper( cSearch )
   // --- Per-field search params ---
   hSearch[ 'name' ] := Trim( UParam( '_q_name', '' ) )
   // --- Build query string for pagination links ---
   cSearchParams := ''
   IF !empty( cSearch )
      cSearchParams += '&q=' + cSearch
   ENDIF
   IF !empty( hSearch[ 'name' ] )
      cSearchParams += '&_q_name=' + hSearch[ 'name' ]
   ENDIF

   // --- Recover flash messages (only show on grid, clear after reading) ---
   oFlash := UFlash( 'users' )
   hMessage[ 'type' ]   := oFlash:Get( 'type' )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   oFlash:Clear()
   oFlash:Save()

   // --- Open Data Access Layer ---
   oUsers := TUsers()

   // --- FR-READ-2: Direct DBF read (bypassing LoadAll/Row/Normalize) ---
   cAlias := oUsers:cAlias
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
      ( cAlias )->( DbSkip( nStart - 1 ) )
   ENDIF
   nJ := 0
   DO WHILE nJ < nRows .AND. ( cAlias )->( !Eof() )
      hRec := { => }
      hRec[ '_recno' ] := ( cAlias )->( RecNo() )
      hRec[ '_deleted' ] := ( cAlias )->( Deleted() )
      hRec[ 'name' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'name' ) ) ) )
      hRec[ 'pass' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'pass' ) ) ) )
      hRec[ 'roles' ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( 'roles' ) ) ) )
      aAdd( aGrid, hRec )
      ( cAlias )->( DbSkip() )
      nJ++
   ENDDO

   // --- FR-READ-3: Per-field search (AND logic between fields) ---
   IF !empty( cSearch ) .OR. !empty( hSearch[ 'name' ] )
      cSearchUpper := Upper( cSearch )
      aFiltered := {}
      FOR nI := 1 TO Len( aGrid )
         lMatch := .T.
         IF !empty( cSearch )
            IF ! ( Upper( HB_HGetDef( aGrid[ nI ], 'name', '' ) ) $ cSearchUpper .OR. ;
               Upper( HB_HGetDef( aGrid[ nI ], 'pass', '' ) ) $ cSearchUpper .OR. ;
               Upper( HB_HGetDef( aGrid[ nI ], 'roles', '' ) ) $ cSearchUpper )
               lMatch := .F.
            ENDIF
         ENDIF
         IF !empty( hSearch[ 'name' ] )
            IF ! ( Upper( HB_HGetDef( aGrid[ nI ], 'name', '' ) ) $ Upper( hSearch[ 'name' ] ) )
               lMatch := .F.
            ENDIF
         ENDIF
         IF lMatch
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
RETURN UView( 'masters/users/grid.html', cAction, aGrid, aPages, nPage, nTotalPages, ;
              cSort, cDir, cSearch, hSearch, hMessage, hErrors )

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

METHOD Destroy() CLASS UsersController

   dbcloseall()

RETURN nil

// -------------------------------------------------------------- //

#include 'models/tusers.prg'
