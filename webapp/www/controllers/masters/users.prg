// --------------------------------------------------------------------------------
// UsersController — CRUD for users.dbf
// Pattern: follows www/controllers/masters/customer.prg
// Complies with DEV-compliance.md: HIX framework only, no SQL, local git
//
// Defect closures in this file:
//   D-05  credentials never projected into a grid/show/edit hash
//   D-06  free-text grid search restricted to an allow-list of fields
//   D-07  passwords stored as salted, iterated SHA-256 (see models/hpassword.prg)
//   D-08  column sort uses the same key case as the grid hash keys
//   D-09  NAME uniqueness enforced on create and update
//   D-10  flash is drained (cleared) once it has been consumed
//   D-11  Destroy() closes only this module's alias, not every workarea
//   D-13  oVal:Get('id') used consistently
//   +     new records get an ID (Insert() used to leave ID = 0)
// --------------------------------------------------------------------------------

#include 'hbclass.ch'

CLASS UsersController

   DATA oUsers INIT NIL      // D-11: the single DAL instance owned by this request

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

   METHOD OpenDbf()
   METHOD TakeFlash()
   METHOD NameExists( cName, nExclude )
   METHOD NextId()
   METHOD ScrubResume( hResume )
   METHOD FlashFail( cMessage, hErrors, hInput )

ENDCLASS

// -------------------------------------------------------------- //

METHOD New() CLASS UsersController

   _d( 'NEW() -->> ' + Self:ClassName() )

RETURN SELF

// -------------------------------------------------------------- //

METHOD End() CLASS UsersController

RETURN SELF

// -------------------------------------------------------------- //
// D-11: the previous implementation called dbcloseall(), which closed every
// alias in the worker thread (pool_http.workers = 64), including aliases owned
// by other modules and by HIX itself.  Close only the alias we opened.
// HIX already runs HIX_CloseDbfAreas() after each action (auto_close_dbf), so
// this is the belt-and-braces half: it makes the module correct on its own.

METHOD Destroy() CLASS UsersController

   IF ValType( ::oUsers ) == 'O'
      ::oUsers:Close()
      ::oUsers := NIL
   ENDIF

RETURN nil

// -------------------------------------------------------------- //
// Open the users DAL once per request and reuse it across helper calls.

METHOD OpenDbf() CLASS UsersController

   IF ! ValType( ::oUsers ) == 'O'
      ::oUsers := TUsers()
   ENDIF

RETURN ::oUsers

// -------------------------------------------------------------- //
// D-10: read the users flash AND clear it, so a validation re-render cannot
// reappear on a later, unrelated request.

METHOD TakeFlash() CLASS UsersController

   LOCAL oFlash := UFlash( 'users' )
   LOCAL hFlash := { => }

   hFlash[ 'type' ]    := oFlash:Get( 'type' )
   hFlash[ 'message' ] := oFlash:Get( 'message' )
   hFlash[ 'input' ]   := oFlash:Get( 'input' )
   hFlash[ 'errors' ]  := oFlash:Get( 'errors', { => } )

   oFlash:Clear()
   oFlash:Save()

RETURN hFlash

// -------------------------------------------------------------- //
// D-05: never put a submitted password into the flash — the flash is rendered
// back into the form.

METHOD ScrubResume( hResume ) CLASS UsersController

   LOCAL hOut

   IF ! ValType( hResume ) == 'H'
      RETURN { => }
   ENDIF

   hOut := hb_HClone( hResume )

   // Blank it rather than delete it: hb_HDelKey() is not linked into the
   // HIX server binary, and an empty value is never rendered (edit.html
   // always posts value="").
   IF hb_HHasKey( hOut, 'pass' )
      hOut[ 'pass' ] := ''
   ENDIF

RETURN hOut

// -------------------------------------------------------------- //

METHOD FlashFail( cMessage, hErrors, hInput ) CLASS UsersController

   UFlash( 'users' ):Set( { ;
      "type"    => 'danger',                    ;
      "message" => cMessage,                    ;
      "errors"  => iif( ValType( hErrors ) == 'H', hErrors, { => } ), ;
      "input"   => Self:ScrubResume( hInput )   ;
   } )

RETURN nil

// -------------------------------------------------------------- //
// D-09: NAME uniqueness.  The 'name' CDX tag is keyed on Lower(name), so the
// seek is exact once the result is confirmed with a strict ==.
// A soft-deleted name still counts: re-creating it would resurrect an identity
// that existing sessions/audit trails may still reference.

METHOD NameExists( cName, nExclude ) CLASS UsersController

   LOCAL o       := Self:OpenDbf()
   LOCAL cAlias  := o:cAlias
   LOCAL cKey    := Lower( AllTrim( UStr( cName ) ) )
   LOCAL cFound

   IF empty( cKey )
      RETURN .F.
   ENDIF

   ( cAlias )->( DbSeek( cKey ) )

   IF ( cAlias )->( Eof() )
      RETURN .F.
   ENDIF

   cFound := Lower( AllTrim( ( cAlias )->( FieldGet( FieldPos( 'NAME' ) ) ) ) )

   IF cFound != cKey
      RETURN .F.
   ENDIF

   IF ValType( nExclude ) == 'N' .AND. ( cAlias )->( RecNo() ) == nExclude
      RETURN .F.
   ENDIF

RETURN .T.

// -------------------------------------------------------------- //
// New records used to be appended with ID = 0 (DataFields() only carries the
// validated POST fields).  ID is assigned as max(existing ID) + 1.

METHOD NextId() CLASS UsersController

   LOCAL o      := Self:OpenDbf()
   LOCAL cAlias := o:cAlias
   LOCAL nMax := 0, nId

   ( cAlias )->( DbGoTop() )
   DO WHILE ! ( cAlias )->( Eof() )
      nId := ( cAlias )->( FieldGet( FieldPos( 'ID' ) ) )
      IF nId > nMax
         nMax := nId
      ENDIF
      ( cAlias )->( DbSkip() )
   ENDDO

RETURN nMax + 1

// -------------------------------------------------------------- //

METHOD Search() CLASS UsersController

   LOCAL hFlash := Self:TakeFlash()
   LOCAL hSearch := { => }

   // Pre-fill the per-field search box from the query string
   hSearch[ 'name' ] := Trim( UGet( '_q_name', '' ) )

RETURN UView( 'masters/users/search.html', hSearch, hFlash )

// -------------------------------------------------------------- //

METHOD Show() CLASS UsersController

   LOCAL hRow := { => }
   LOCAL oVal, lFound

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN URedirect( URoute( 'users.search' ) )
   ENDIF

   lFound := Self:OpenDbf():GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )

   // PASS and SALT are hidden on the DAL (models/tusers.prg), so hRow can
   // never carry a credential into the view (D-05).
   IF ! lFound
      hRow := Self:OpenDbf():Blank( .t. )
   ENDIF

RETURN UView( 'masters/users/show.html', lFound, hRow, Self:TakeFlash() )

// -------------------------------------------------------------- //

METHOD Edit() CLASS UsersController

   LOCAL oVal, lFound
   LOCAL hMessage := { => }
   LOCAL hRow := { => }
   LOCAL hErrors := { => }
   LOCAL hInput
   LOCAL hFlash

   oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )

   IF ! oVal:Make()
      RETURN URedirect( URoute( 'users.search' ) )
   ENDIF

   // Recover data flash if it exists — and drain it (D-10)
   hFlash  := Self:TakeFlash()
   hInput  := hFlash[ 'input' ]
   hErrors := hFlash[ 'errors' ]

   hMessage[ 'type' ]    := hFlash[ 'type' ]
   hMessage[ 'message' ] := hFlash[ 'message' ]

   IF !empty( hInput )
      IF ! ValType( hErrors ) == 'H'
         hErrors := { => }
      ENDIF
      RETURN UView( 'masters/users/edit.html', 'edit', .T., hInput, hMessage, hErrors )
   ENDIF

   lFound := Self:OpenDbf():GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )  // .T. == to String Web

   IF !lFound
      hRow := Self:OpenDbf():Blank( .t. )
   ENDIF

   IF empty( hErrors )
      hErrors := { => }
   ENDIF

RETURN UView( 'masters/users/edit.html', 'edit', lFound, hRow, hMessage, hErrors )

// -------------------------------------------------------------- //

METHOD Create() CLASS UsersController

   LOCAL hRow
   LOCAL hMessage := { => }
   LOCAL hErrors := { => }
   LOCAL hInput
   LOCAL hFlash

   hFlash  := Self:TakeFlash()
   hInput  := hFlash[ 'input' ]
   hErrors := hFlash[ 'errors' ]

   hMessage[ 'type' ]    := hFlash[ 'type' ]
   hMessage[ 'message' ] := hFlash[ 'message' ]

   IF ValType( hInput ) == 'H'
      hRow := hInput
   ELSE
      hRow := Self:OpenDbf():Blank( .t. )  // .t. == to web string
   ENDIF

   IF ! ValType( hErrors ) == 'H'
      hErrors := { => }
   ENDIF

RETURN UView( 'masters/users/edit.html', 'create', .F., hRow, hMessage, hErrors )

// -------------------------------------------------------------- //

METHOD Update() CLASS UsersController

   LOCAL oVal, oPost, nId, cError, lSuccess, cName, cPass, cSalt
   LOCAL oUsers
   LOCAL hChanges

   // Get ID from URL route parameter
   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN URedirect( URoute( 'users.search' ) )
   ENDIF

   nId := oVal:Get( 'id' )     // D-13: always name the field

   // 'pass' is deliberately NOT marked as |field: it must never be written
   // verbatim to the DBF.  An empty value means "keep the current password".
   oPost := UValidatePost( { ;
      "name"    => "required|string|max:40|field", ;
      "pass"    => "string|min:4|max:40",          ;
      "roles"   => "required|string|max:255|field" ;
   } )

   IF ! oPost:Make()
      Self:FlashFail( 'Error validacion', oPost:GetErrors(), oPost:Resume() )
      RETURN URedirect( URoute( 'users.edit', nId ) )
   ENDIF

   oUsers := Self:OpenDbf()

   cName := AllTrim( oPost:Get( 'name' ) )

   // D-09: reject a rename that collides with another account
   IF Self:NameExists( cName, nId )
      Self:FlashFail( 'Name ' + cName + ' is already in use', ;
                      { 'name' => 'Name already in use' }, oPost:Resume() )
      RETURN URedirect( URoute( 'users.edit', nId ) )
   ENDIF

   hChanges := oPost:DataFields()      // name + roles only

   // D-07: hash with a fresh salt only when a new password was supplied
   cPass := oPost:Get( 'pass' )
   IF !empty( cPass )
      cSalt            := _PwSalt( cName )
      hChanges[ 'salt' ] := cSalt
      hChanges[ 'pass' ] := _PwHash( AllTrim( cPass ), cSalt )
   ENDIF

   lSuccess := oUsers:Update( nId, hChanges, @cError )

   IF lSuccess
      UFlash( "users" ):Set( { ;
         "type"    => 'success',                              ;
         "message" => 'User ' + ltrim(str(nId)) + ' was updated!' ;
      } )
      RETURN URedirect( URoute( 'users.show', nId ) )
   ELSE
      Self:FlashFail( cError, { => }, NIL )
      RETURN URedirect( URoute( 'users.edit', nId ) )
   ENDIF

RETURN nil

// -------------------------------------------------------------- //

METHOD Store() CLASS UsersController

   LOCAL oVal, cError, lSuccess, nRecno, cName, cPass
   LOCAL oUsers
   LOCAL hData

   // 'pass' is not |field — see Update() for the reason (D-07).
   oVal := UValidatePost( { ;
      "name"    => "required|string|max:40|field", ;
      "pass"    => "required|string|min:4|max:40", ;
      "roles"   => "required|string|max:255|field" ;
   } )

   IF ! oVal:Make()
      Self:FlashFail( 'Error validacion', oVal:GetErrors(), oVal:Resume() )
      RETURN URedirect( URoute( 'users.create' ) )
   ENDIF

   cName := AllTrim( oVal:Get( 'name' ) )
   cPass := AllTrim( oVal:Get( 'pass' ) )

   // D-09: NAME is the login identity and the CDX key — duplicates make
   // DbSeek ambiguous, so they are refused outright.
   IF Self:NameExists( cName, NIL )
      Self:FlashFail( 'Name ' + cName + ' is already in use', ;
                      { 'name' => 'Name already in use' }, oVal:Resume() )
      RETURN URedirect( URoute( 'users.create' ) )
   ENDIF

   oUsers := Self:OpenDbf()

   hData            := hb_HClone( oVal:DataFields() )
   hData[ 'id' ]    := Self:NextId()
   hData[ 'salt' ]  := _PwSalt( cName )
   hData[ 'pass' ]  := _PwHash( cPass, hData[ 'salt' ] )

   lSuccess := oUsers:Insert( hData, @cError, @nRecno )

   IF lSuccess
      UFlash( "users" ):Set( { ;
         "type"    => 'success',                                 ;
         "message" => 'User ' + ltrim(str(nRecno)) + ' was created!' ;
      } )
      RETURN URedirect( URoute( 'users.grid' ) )
   ELSE
      Self:FlashFail( cError, { => }, oVal:Resume() )
      RETURN URedirect( URoute( 'users.create' ) )
   ENDIF

RETURN nil

// -------------------------------------------------------------- //

METHOD delete_confirm() CLASS UsersController

   LOCAL oVal
   LOCAL hRow := { => }
   LOCAL lFound := .F.

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN URedirect( URoute( 'users.grid' ) )
   ENDIF

   lFound := Self:OpenDbf():GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )

RETURN UView( 'masters/users/delete.html', lFound, hRow )

// -------------------------------------------------------------- //

METHOD delete_action() CLASS UsersController

   LOCAL oVal, nId, lIsDeleted
   LOCAL oUsers
   LOCAL hRow := { => }

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      RETURN URedirect( URoute( 'users.grid' ) )
   ENDIF

   nId := oVal:Get( 'id' )     // D-13: always name the field

   oUsers := Self:OpenDbf()

   IF ! oUsers:GetRecno( nId, @hRow )
      RETURN URedirect( URoute( 'users.grid' ) )
   ENDIF

   oUsers:Delete( nId, .T., @lIsDeleted )

RETURN URedirect( URoute( 'users.grid' ) )

// -------------------------------------------------------------- //

METHOD Grid() CLASS UsersController

   LOCAL nPage, nRows, nTotalPages := 0
   LOCAL aPages, aGrid, aAll
   LOCAL cSort, cDir, cSearch
   LOCAL hMessage := { => }
   LOCAL cAction := 'grid'
   LOCAL hErrors := { => }
   LOCAL hSearch := { => }
   LOCAL cSearchUpper
   LOCAL nTotal, nStart, nEnd, nI
   LOCAL aFiltered, lMatch
   LOCAL cAlias, nRecCount, hRec, nJ, cSearchParams
   LOCAL oUsers
   LOCAL hFlash
   // D-05 / D-06: the grid projection and the free-text search share one
   // allow-list.  pass and salt are not in it, so neither can be read,
   // sorted, searched or rendered.
   LOCAL aFields := { 'name', 'roles' }
   LOCAL aSortOk := { 'name', 'roles' }

   // --- Pagination params ---
   nPage    := Iif( Empty( UGet( 'page', '' ) ), 1, Val( UGet( 'page', '' ) ) )
   nRows    := 20   // default page size per FR-READ-2 (DAL SRS)
   // D-08: grid hash keys are lowercase, so the sort key must be too
   cSort    := Lower( UGet( 'sort', 'name' ) )
   IF Ascan( aSortOk, cSort ) == 0
      cSort := 'name'
   ENDIF
   cDir     := Upper( UGet( 'dir', 'ASC' ) )
   IF cDir != 'DESC'
      cDir := 'ASC'
   ENDIF
   cSearch  := Trim( UGet( 'q', '' ) )
   cSearchUpper := Upper( cSearch )
   // --- Per-field search params ---
   hSearch[ 'name' ] := Trim( UGet( '_q_name', '' ) )
   // --- Build query string for pagination links ---
   cSearchParams := ''
   IF !empty( cSearch )
      cSearchParams += '&q=' + cSearch
   ENDIF
   IF !empty( hSearch[ 'name' ] )
      cSearchParams += '&_q_name=' + hSearch[ 'name' ]
   ENDIF

   // --- Recover flash messages (cleared after reading, D-10) ---
   hFlash := Self:TakeFlash()
   hMessage[ 'type' ]    := hFlash[ 'type' ]
   hMessage[ 'message' ] := hFlash[ 'message' ]

   // --- Open Data Access Layer ---
   oUsers := Self:OpenDbf()

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
      // Soft-deleted records are not part of the user list
      IF ! ( cAlias )->( Deleted() )
         hRec := { => }
         hRec[ '_recno' ]   := ( cAlias )->( RecNo() )
         hRec[ '_deleted' ] := ( cAlias )->( Deleted() )
         FOR nI := 1 TO Len( aFields )
            hRec[ aFields[ nI ] ] := ( cAlias )->( FieldGet( ( cAlias )->( FieldPos( aFields[ nI ] ) ) ) )
         NEXT
         aAdd( aGrid, hRec )
         nJ++
      ENDIF
      ( cAlias )->( DbSkip() )
   ENDDO

   // --- FR-READ-3: Per-field search (AND logic between fields) ---
   IF !empty( cSearch ) .OR. !empty( hSearch[ 'name' ] )
      cSearchUpper := Upper( cSearch )
      aFiltered := {}
      FOR nI := 1 TO Len( aGrid )
         lMatch := .T.
         IF !empty( cSearch )
            // D-06: free-text search may only touch allow-listed fields.
            // Containment direction: the query must be a substring of the
            // field (the previous order tested name $ query, which matches
            // only when the whole name is typed).
            IF ! ( cSearchUpper $ Upper( HB_HGetDef( aGrid[ nI ], 'name', '' ) ) )
               lMatch := .F.
            ENDIF
         ENDIF
         IF !empty( hSearch[ 'name' ] )
            IF ! ( Upper( hSearch[ 'name' ] ) $ Upper( HB_HGetDef( aGrid[ nI ], 'name', '' ) ) )
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
// Parameters: aGrid, cField (lowercase, allow-listed by Grid()), cDir (ASC|DESC)
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

#include 'models/tusers.prg'
#include 'models/hpassword.prg'
