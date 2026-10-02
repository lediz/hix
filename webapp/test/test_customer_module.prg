// ---------------------------------------------------------------
// test_customer_module.prg
// Functional test script for the Customer module only.
// Tests: Create, Read (Search/Show), Update, Delete, Grid
// Complies with: SRS-Harbour-HIX.md (REQ-FUNC-010..016, REQ-FUNC-035)
//         and DAL SRS (FR-CREATE-1..4, FR-READ-1..5, FR-UPDATE-1..5, FR-DELETE-1..4)
// ---------------------------------------------------------------

#include "hbclass.ch"
#include "inkey.ch"

#define TEST_PASS   0
#define TEST_FAIL   1

LOCAL nTotalPass
LOCAL nTotalFail
LOCAL nTotalTests
LOCAL cDataDir

nTotalPass   := 0
nTotalFail   := 0
nTotalTests  := 0
cDataDir     := hb_dirbase() + "data"

FUNCTION Main()
   LOCAL cTestName, lResult

   ? ""
   ? "============================================================="
   ? "  CUSTOMER MODULE — FUNCTIONAL TEST SUITE"
   ? "============================================================="
   ? ""
   ? "Data directory: " + cDataDir
   ? "DBF: customers.dbf / customers.cdx"
   ? "Tag: first"
   ? ""

   // Ensure fresh DBF for testing
   EnsureFreshDbf()

   // Run all test cases
   cTestName := "T01 - Grid: Load all records (FR-READ-1, FR-READ-2)"
   lResult := TestGridLoadAll()
   ReportResult(cTestName, lResult)

   cTestName := "T02 - Grid: Pagination (FR-READ-2)"
   lResult := TestGridPagination()
   ReportResult(cTestName, lResult)

   cTestName := "T03 - Grid: Column Sort ASC (FR-READ-4)"
   lResult := TestGridSortAsc()
   ReportResult(cTestName, lResult)

   cTestName := "T04 - Grid: Column Sort DESC (FR-READ-4)"
   lResult := TestGridSortDesc()
   ReportResult(cTestName, lResult)

   cTestName := "T05 - Grid: Multi-record Search (FR-READ-3)"
   lResult := TestGridSearch()
   ReportResult(cTestName, lResult)

   cTestName := "T06 - Search: Find by ID (FR-READ-5)"
   lResult := TestSearchById()
   ReportResult(cTestName, lResult)

   cTestName := "T07 - Search: Show non-existent (FR-READ-5)"
   lResult := TestSearchNonExistent()
   ReportResult(cTestName, lResult)

   cTestName := "T08 - Show: Display customer fields (FR-READ-1)"
   lResult := TestShowFields()
   ReportResult(cTestName, lResult)

   cTestName := "T09 - Create: Insert new record (FR-CREATE-1, FR-CREATE-4)"
   lResult := TestCreate()
   ReportResult(cTestName, lResult)

   cTestName := "T10 - Create: Validate required fields (FR-CREATE-3)"
   lResult := TestCreateValidation()
   ReportResult(cTestName, lResult)

   cTestName := "T11 - Update: Modify existing record (FR-UPDATE-4)"
   lResult := TestUpdate()
   ReportResult(cTestName, lResult)

   cTestName := "T12 - Update: Validate edit fields (FR-UPDATE-3)"
   lResult := TestUpdateValidation()
   ReportResult(cTestName, lResult)

   cTestName := "T13 - Update: Validation failure (FR-UPDATE-5)"
   lResult := TestUpdateValidationFailure()
   ReportResult(cTestName, lResult)

   cTestName := "T14 - Delete: Soft delete toggle (FR-DELETE-2, FR-DELETE-3)"
   lResult := TestDeleteToggle()
   ReportResult(cTestName, lResult)

   cTestName := "T15 - Delete: Confirm record removed from grid (FR-DELETE-4)"
   lResult := TestDeleteGridRemoval()
   ReportResult(cTestName, lResult)

   cTestName := "T16 - Show: State lookup (external table join)"
   lResult := TestStateLookup()
   ReportResult(cTestName, lResult)

   cTestName := "T17 - DAL: UDbf Open/Close lifecycle"
   lResult := TestDbfLifecycle()
   ReportResult(cTestName, lResult)

   cTestName := "T18 - DAL: Field visibility control (REQ-FUNC-016)"
   lResult := TestFieldVisibility()
   ReportResult(cTestName, lResult)

   cTestName := "T19 - DAL: Blank record template"
   lResult := TestBlankRecord()
   ReportResult(cTestName, lResult)

   cTestName := "T20 - Grid: Empty table handling"
   lResult := TestEmptyGrid()
   ReportResult(cTestName, lResult)

   // Summary
   ? ""
   ? "============================================================="
   ? "  TEST RESULTS SUMMARY"
   ? "============================================================="
   ? "  Total tests : " + ltrim(str(nTotalTests))
   ? "  Passed      : " + ltrim(str(nTotalPass))
   ? "  Failed      : " + ltrim(str(nTotalFail))
   ? "  Pass rate   : " + ltrim(str(nTotalPass)) + "/" + ltrim(str(nTotalTests))
   ? "============================================================="
   ? ""

RETURN

// Helper: Ensure fresh DBF with known test data
FUNCTION EnsureFreshDbf()
   LOCAL cPath, cCdx, i, aTestData

   cPath := cDataDir + "/customers.dbf"
   cCdx  := cDataDir + "/customers.cdx"
   hb_fdelete(cPath)
   hb_fdelete(cCdx)

   DBCREATE(cPath, { ;
      {"FIRST","C",20,0},{"LAST","C",20,0},{"STREET","C",30,0}, ;
      {"CITY","C",30,0},{"STATE","C",2,0},{"ZIP","C",10,0}, ;
      {"NOTES","C",70,0},{"HIREDATE","D",8,0},{"AGE","N",7,0}, ;
      {"MARRIED","L",1,0},{"_deleted","L",1,0} ;
   })

   USE (cPath) ALIAS cust SHARED
   DBSETRECORDLOCKING(.T.)
   DBCREATEINDEX("first", "FIRST")

   aTestData := { ;
      {{"FIRST","John"},{"LAST","Doe"},{"STREET","123 Main St"},{"CITY","Springfield"},{"STATE","IL"},{"ZIP","62701"},{"NOTES","First test customer"},{"HIREDATE",CToD("01/15/2023")},{"AGE",30},{"MARRIED",.T.}}, ;
      {{"FIRST","Jane"},{"LAST","Smith"},{"STREET","456 Oak Ave"},{"CITY","Portland"},{"STATE","OR"},{"ZIP","97201"},{"NOTES","Second test customer"},{"HIREDATE",CToD("03/22/2024")},{"AGE",28},{"MARRIED",.F.}}, ;
      {{"FIRST","Bob"},{"LAST","Johnson"},{"STREET","789 Pine Rd"},{"CITY","Austin"},{"STATE","TX"},{"ZIP","73301"},{"NOTES","Third test customer"},{"HIREDATE",CToD("06/10/2022")},{"AGE",45},{"MARRIED",.T.}}, ;
      {{"FIRST","Alice"},{"LAST","Williams"},{"STREET","321 Elm Blvd"},{"CITY","Denver"},{"STATE","CO"},{"ZIP","80201"},{"NOTES","Fourth test customer"},{"HIREDATE",CToD("09/05/2023")},{"AGE",35},{"MARRIED",.F.}}, ;
      {{"FIRST","Charlie"},{"LAST","Brown"},{"STREET","654 Maple Dr"},{"CITY","Seattle"},{"STATE","WA"},{"ZIP","98101"},{"NOTES","Fifth test customer"},{"HIREDATE",CToD("11/18/2021")},{"AGE",52},{"MARRIED",.T.}} ;
   }

   FOR i := 1 TO Len(aTestData)
      APPEND BLANK
      DBPUTFIELD("FIRST",   aTestData[i]["FIRST"])
      DBPUTFIELD("LAST",    aTestData[i]["LAST"])
      DBPUTFIELD("STREET",  aTestData[i]["STREET"])
      DBPUTFIELD("CITY",    aTestData[i]["CITY"])
      DBPUTFIELD("STATE",   aTestData[i]["STATE"])
      DBPUTFIELD("ZIP",     aTestData[i]["ZIP"])
      DBPUTFIELD("NOTES",   aTestData[i]["NOTES"])
      DBPUTFIELD("HIREDATE",aTestData[i]["HIREDATE"])
      DBPUTFIELD("AGE",     aTestData[i]["AGE"])
      DBPUTFIELD("MARRIED", aTestData[i]["MARRIED"])
      DBPUTFIELD("_deleted",.F.)
      DBSKIP()
   NEXT
   DBGOBOTTOM()
   ? "  Created fresh DBF with " + ltrim(str(RecCount())) + " test records"
   DBCLOSEALL()
RETURN

// Helper: Report test result
FUNCTION ReportResult(cTestName, lResult)
   LOCAL cStatus
   nTotalTests++
   IF lResult
      nTotalPass++
      cStatus := "[PASS]"
   ELSE
      nTotalFail++
      cStatus := "[FAIL]"
   ENDIF
   ? cStatus + " " + cTestName
RETURN lResult

// TEST T01 - Grid: Load all records (FR-READ-1, FR-READ-2)
FUNCTION TestGridLoadAll()
   LOCAL oDbf, aAll, aFields, hRec, nCount, lConnected
   oDbf := CustomerDbf()
   lConnected := oDbf:lConnect
   IF !lConnected
      ? "    ERROR: DBF not connected"
      RETURN .F.
   ENDIF
   aFields := {"FIRST","LAST","STREET","CITY","STATE","ZIP","NOTES","HIREDATE","AGE","MARRIED"}
   aAll := oDbf:LoadAll(aFields)
   IF Len(aAll) < 5
      ? "    ERROR: Expected >= 5 records, got " + ltrim(str(Len(aAll)))
      RETURN .F.
   ENDIF
   hRec := aAll[1]
   IF !HB_HGetDef(hRec, "_recno", 0) > 0
      ? "    ERROR: Missing _recno in first record"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hRec, "_deleted", .F.)
      ? "    ERROR: First record is deleted"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hRec, "FIRST", "") != "John"
      ? "    ERROR: First record FIRST should be 'John', got '" + HB_HGetDef(hRec, "FIRST", "") + "'"
      RETURN .F.
   ENDIF
   ? "    OK: Loaded " + ltrim(str(Len(aAll))) + " records, first = '" + HB_HGetDef(aAll[1], "FIRST", "") + " " + HB_HGetDef(aAll[1], "LAST", "") + "'"
RETURN .T.

// TEST T02 - Grid: Pagination (FR-READ-2)
FUNCTION TestGridPagination()
   LOCAL oDbf, aPage, nTotalPages, nRecCount, cAlias
   oDbf := CustomerDbf()
   cAlias := oDbf:cAlias
   nRecCount := (cAlias)->(RecCount())
   aPage := oDbf:Page(1, 2, NIL, @nTotalPages)
   IF Len(aPage) != 2
      ? "    ERROR: Page 1 should have 2 records, got " + ltrim(str(Len(aPage)))
      RETURN .F.
   ENDIF
   IF nTotalPages < 3
      ? "    ERROR: Expected nTotalPages >= 3, got " + ltrim(str(nTotalPages))
      RETURN .F.
   ENDIF
   aPage := oDbf:Page(2, 2, NIL, @nTotalPages)
   IF Len(aPage) != 2
      ? "    ERROR: Page 2 should have 2 records, got " + ltrim(str(Len(aPage)))
      RETURN .F.
   ENDIF
   aPage := oDbf:Page(3, 2, NIL, @nTotalPages)
   IF Len(aPage) != 1
      ? "    ERROR: Page 3 should have 1 record, got " + ltrim(str(Len(aPage)))
      RETURN .F.
   ENDIF
   aPage := oDbf:Page(4, 2, NIL, @nTotalPages)
   IF Len(aPage) != 1
      ? "    ERROR: Page 4 (beyond total) should return last page"
      RETURN .F.
   ENDIF
   ? "    OK: Pagination verified — " + ltrim(str(nTotalPages)) + " pages, page sizes [2,2,1]"
RETURN .T.

// TEST T03 - Grid: Column Sort ASC (FR-READ-4)
FUNCTION TestGridSortAsc()
   LOCAL aAll, hRec, cFirst, cLast, oDbf
   oDbf := CustomerDbf()
   aAll := SortGrid(aAll := oDbf:LoadAll({"FIRST","LAST"}), "FIRST", "ASC")
   cFirst := HB_HGetDef(aAll[1], "FIRST", "")
   IF cFirst != "Alice"
      ? "    ERROR: Sort ASC first record should be 'Alice', got '" + cFirst + "'"
      RETURN .F.
   ENDIF
   cLast := HB_HGetDef(aAll[Len(aAll)], "FIRST", "")
   IF cLast != "John"
      ? "    ERROR: Sort ASC last record should be 'John', got '" + cLast + "'"
      RETURN .F.
   ENDIF
   ? "    OK: Sort ASC verified — first='" + cFirst + "', last='" + cLast + "'"
RETURN .T.

// TEST T04 - Grid: Column Sort DESC (FR-READ-4)
FUNCTION TestGridSortDesc()
   LOCAL aAll, cFirst, cLast, oDbf
   oDbf := CustomerDbf()
   aAll := SortGrid(aAll := oDbf:LoadAll({"FIRST","LAST"}), "FIRST", "DESC")
   cFirst := HB_HGetDef(aAll[1], "FIRST", "")
   IF cFirst != "John"
      ? "    ERROR: Sort DESC first record should be 'John', got '" + cFirst + "'"
      RETURN .F.
   ENDIF
   cLast := HB_HGetDef(aAll[Len(aAll)], "FIRST", "")
   IF cLast != "Alice"
      ? "    ERROR: Sort DESC last record should be 'Alice', got '" + cLast + "'"
      RETURN .F.
   ENDIF
   ? "    OK: Sort DESC verified — first='" + cFirst + "', last='" + cLast + "'"
RETURN .T.

// TEST T05 - Grid: Multi-record Search (FR-READ-3)
FUNCTION TestGridSearch()
   LOCAL oDbf, aAll, aFiltered, cSearch, cSearchUpper, nI, hRec, lFound
   oDbf := CustomerDbf()
   aAll := oDbf:LoadAll({"FIRST","LAST","CITY","STREET"})
   cSearch := "ain"
   cSearchUpper := Upper(cSearch)
   aFiltered := {}
   FOR nI := 1 TO Len(aAll)
      hRec := aAll[nI]
      IF Upper(HB_HGetDef(hRec, "FIRST", "")) $ cSearchUpper .OR. ;
         Upper(HB_HGetDef(hRec, "LAST", "")) $ cSearchUpper .OR. ;
         Upper(HB_HGetDef(hRec, "CITY", "")) $ cSearchUpper .OR. ;
         Upper(HB_HGetDef(hRec, "STREET", "")) $ cSearchUpper
         aAdd(aFiltered, hRec)
      ENDIF
   NEXT
   IF Len(aFiltered) == 0
      ? "    ERROR: Search for 'ain' found 0 records"
      RETURN .F.
   ENDIF
   lFound := .F.
   FOR nI := 1 TO Len(aFiltered)
      IF "AIN" $ Upper(HB_HGetDef(aFiltered[nI], "FIRST", "")) .OR. ;
         "AIN" $ Upper(HB_HGetDef(aFiltered[nI], "LAST", "")) .OR. ;
         "AIN" $ Upper(HB_HGetDef(aFiltered[nI], "CITY", "")) .OR. ;
         "AIN" $ Upper(HB_HGetDef(aFiltered[nI], "STREET", ""))
         lFound := .T.
         EXIT
      ENDIF
   NEXT
   IF !lFound
      ? "    ERROR: No record contained 'ain' substring"
      RETURN .F.
   ENDIF
   ? "    OK: Search 'ain' found " + ltrim(str(Len(aFiltered))) + " records"
RETURN .T.

// TEST T06 - Search: Find by ID (FR-READ-5)
FUNCTION TestSearchById()
   LOCAL oDbf, hRow, lFound, cFirst
   oDbf := CustomerDbf()
   lFound := oDbf:GetRecno(1, @hRow, NIL, .T.)
   IF !lFound
      ? "    ERROR: GetRecno(1) failed"
      RETURN .F.
   ENDIF
   cFirst := HB_HGetDef(hRow, "FIRST", "")
   IF cFirst != "John"
      ? "    ERROR: Recno 1 FIRST should be 'John', got '" + cFirst + "'"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hRow, "_recno", 0) != 1
      ? "    ERROR: _recno should be 1"
      RETURN .F.
   ENDIF
   ? "    OK: GetRecno(1) returned FIRST='" + cFirst + "' _recno=" + ltrim(str(HB_HGetDef(hRow, "_recno", 0)))
RETURN .T.

// TEST T07 - Search: Show non-existent (FR-READ-5)
FUNCTION TestSearchNonExistent()
   LOCAL oDbf, hRow, lFound
   oDbf := CustomerDbf()
   lFound := oDbf:GetRecno(0, @hRow, NIL, .T.)
   IF lFound
      ? "    ERROR: GetRecno(0) should NOT find a record"
      RETURN .F.
   ENDIF
   lFound := oDbf:GetRecno(999, @hRow, NIL, .T.)
   IF lFound
      ? "    ERROR: GetRecno(999) should NOT find a record"
      RETURN .F.
   ENDIF
   ? "    OK: GetRecno(0) and GetRecno(999) correctly return .F."
RETURN .T.

// TEST T08 - Show: Display customer fields (FR-READ-1)
FUNCTION TestShowFields()
   LOCAL oDbf, hRow, lFound, cFirst, cLast, cState, cZip
   oDbf := CustomerDbf()
   lFound := oDbf:GetRecno(1, @hRow, NIL, .T.)
   IF !lFound
      ? "    ERROR: Could not retrieve record 1"
      RETURN .F.
   ENDIF
   cFirst := HB_HGetDef(hRow, "FIRST", "")
   cLast  := HB_HGetDef(hRow, "LAST", "")
   cState := HB_HGetDef(hRow, "STATE", "")
   cZip   := HB_HGetDef(hRow, "ZIP", "")
   IF cFirst != "John"
      ? "    ERROR: FIRST mismatch: '" + cFirst + "'"
      RETURN .F.
   ENDIF
   IF cLast != "Doe"
      ? "    ERROR: LAST mismatch: '" + cLast + "'"
      RETURN .F.
   ENDIF
   IF cState != "IL"
      ? "    ERROR: STATE mismatch: '" + cState + "'"
      RETURN .F.
   ENDIF
   IF cZip != "62701"
      ? "    ERROR: ZIP mismatch: '" + cZip + "'"
      RETURN .F.
   ENDIF
   ? "    OK: Show record 1 — '" + cFirst + " " + cLast + "' [" + cState + " " + cZip + "]"
RETURN .T.

// TEST T09 - Create: Insert new record (FR-CREATE-1, FR-CREATE-4)
FUNCTION TestCreate()
   LOCAL oDbf, hFields, cError, nRecno, lSuccess, hRow, cFirst, cLast
   oDbf := CustomerDbf()
   hFields := { ;
      "FIRST"   => "Test", ;
      "LAST"    => "Create", ;
      "STREET"  => "999 Test St", ;
      "CITY"    => "Testville", ;
      "STATE"   => "TX", ;
      "ZIP"     => "75001", ;
      "NOTES"   => "Created by test script", ;
      "HIREDATE"=> CToD("01/01/2025"), ;
      "AGE"     => 25, ;
      "MARRIED" => .F., ;
      "_deleted"=> .F. ;
   }
   lSuccess := oDbf:Insert(hFields, @cError, @nRecno)
   IF !lSuccess
      ? "    ERROR: Insert failed: " + cError
      RETURN .F.
   ENDIF
   IF nRecno <= 0
      ? "    ERROR: nRecno = " + ltrim(str(nRecno))
      RETURN .F.
   ENDIF
   hRow := {=>}
   lSuccess := oDbf:GetRecno(nRecno, @hRow, NIL, .T.)
   IF !lSuccess
      ? "    ERROR: Cannot retrieve inserted record nRecno=" + ltrim(str(nRecno))
      RETURN .F.
   ENDIF
   cFirst := HB_HGetDef(hRow, "FIRST", "")
   cLast  := HB_HGetDef(hRow, "LAST", "")
   IF cFirst != "Test"
      ? "    ERROR: Inserted FIRST mismatch: '" + cFirst + "'"
      RETURN .F.
   ENDIF
   IF cLast != "Create"
      ? "    ERROR: Inserted LAST mismatch: '" + cLast + "'"
      RETURN .F.
   ENDIF
   ? "    OK: Create — inserted record nRecno=" + ltrim(str(nRecno)) + " '" + cFirst + " " + cLast + "'"
RETURN .T.

// TEST T10 - Create: Validate required fields (FR-CREATE-3)
FUNCTION TestCreateValidation()
   LOCAL oVal, hFields, lSuccess
   oVal := UValidatePost({ ;
      "first"  => "required|string|max:20|field", ;
      "last"   => "required|string|max:20|field", ;
      "street" => "required|string|max:30|field", ;
      "city"   => "required|string|max:30|field", ;
      "state"  => "required|string|max:2|field", ;
      "zip"    => "required|string|max:10|field", ;
      "hiredate"=> "required|date|field", ;
      "age"    => "required|numeric|max:70|field" ;
   })
   lSuccess := oVal:Make()
   IF !lSuccess
      ? "    ERROR: Validation should pass with valid data"
      RETURN .F.
   ENDIF
   hFields := oVal:DataFields()
   IF Len(hFields) < 7
      ? "    ERROR: DataFields should contain >= 7 fields, got " + ltrim(str(Len(hFields)))
      RETURN .F.
   ENDIF
   ? "    OK: Validation passed, DataFields has " + ltrim(str(Len(hFields))) + " fields"
RETURN .T.

// TEST T11 - Update: Modify existing record (FR-UPDATE-4)
FUNCTION TestUpdate()
   LOCAL oDbf, hChanges, cError, lSuccess, hRow, cFirst
   oDbf := CustomerDbf()
   hChanges := { ;
      "FIRST"  => "Updated", ;
      "LAST"   => "ByTest", ;
      "CITY"   => "UpdatedCity", ;
      "ZIP"    => "99999" ;
   }
   lSuccess := oDbf:Update(1, hChanges, @cError)
   IF !lSuccess
      ? "    ERROR: Update failed: " + cError
      RETURN .F.
   ENDIF
   hRow := {=>}
   lSuccess := oDbf:GetRecno(1, @hRow, NIL, .T.)
   IF !lSuccess
      ? "    ERROR: Cannot retrieve updated record"
      RETURN .F.
   ENDIF
   cFirst := HB_HGetDef(hRow, "FIRST", "")
   IF cFirst != "Updated"
      ? "    ERROR: FIRST after update = '" + cFirst + "', expected 'Updated'"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hRow, "MARRIED", "") != ".T."
      ? "    ERROR: MARRIED should be preserved as .T."
      RETURN .F.
   ENDIF
   ? "    OK: Update verified — FIRST='Updated', MARRIED preserved"
RETURN .T.

// TEST T12 - Update: Validate edit fields (FR-UPDATE-3)
FUNCTION TestUpdateValidation()
   LOCAL oVal, hFields
   oVal := UValidatePost({ ;
      "first"  => "required|string|max:20|field", ;
      "last"   => "required|string|max:20|field", ;
      "street" => "required|string|max:30|field", ;
      "city"   => "required|string|max:30|field", ;
      "state"  => "required|string|max:2|field", ;
      "zip"    => "required|string|max:10|field", ;
      "hiredate"=> "required|date|field", ;
      "age"    => "required|numeric|max:70|field", ;
      "notes"  => "string|field", ;
      "married"=> "logic|field" ;
   })
   IF !oVal:Make()
      ? "    ERROR: Validation should pass"
      RETURN .F.
   ENDIF
   hFields := oVal:DataFields()
   IF HB_HGetDef(hFields, "_deleted", NIL) != NIL
      ? "    ERROR: _deleted should NOT be in DataFields"
      RETURN .F.
   ENDIF
   ? "    OK: Update validation passed, DataFields has " + ltrim(str(Len(hFields))) + " fields, no _deleted"
RETURN .T.

// TEST T13 - Update: Validation failure (FR-UPDATE-5)
FUNCTION TestUpdateValidationFailure()
   LOCAL oVal, hErrors
   oVal := UValidatePost({ ;
      "first" => { "required|string|max:20|field", "First Name" }, ;
      "last"  => { "required|string|max:20|field", "Last Name" } ;
   })
   oVal:DataFields()["first"] := ""
   oVal:DataFields()["last"] := ""
   IF oVal:Make()
      ? "    ERROR: Validation should FAIL with empty required fields"
      RETURN .F.
   ENDIF
   hErrors := oVal:GetErrors()
   IF empty(hErrors)
      ? "    ERROR: GetErrors() should return errors"
      RETURN .F.
   ENDIF
   ? "    OK: Validation correctly failed with errors"
RETURN .T.

// TEST T14 - Delete: Soft delete toggle (FR-DELETE-2, FR-DELETE-3)
FUNCTION TestDeleteToggle()
   LOCAL oDbf, hRow, lIsDeleted, lFound
   oDbf := CustomerDbf()
   lFound := oDbf:GetRecno(5, @hRow, NIL, .T.)
   IF !lFound
      ? "    ERROR: Cannot retrieve record 5"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hRow, "_deleted", .F.)
      ? "    ERROR: Record 5 should not be deleted yet"
      RETURN .F.
   ENDIF
   lIsDeleted := .F.
   IF !oDbf:Delete(5, .T., @lIsDeleted)
      ? "    ERROR: Delete toggle failed"
      RETURN .F.
   ENDIF
   IF !lIsDeleted
      ? "    ERROR: lIsDeleted should be .T. after toggle"
      RETURN .F.
   ENDIF
   hRow := {=>}
   oDbf:GetRecno(5, @hRow, NIL, .T.)
   IF !HB_HGetDef(hRow, "_deleted", .F.)
      ? "    ERROR: Record 5 should be marked deleted"
      RETURN .F.
   ENDIF
   ? "    OK: Delete toggle — record 5 marked _deleted=.T."
RETURN .T.

// TEST T15 - Delete: Confirm record removed from grid (FR-DELETE-4)
FUNCTION TestDeleteGridRemoval()
   LOCAL oDbf, aAll, nCount, hRec, i
   oDbf := CustomerDbf()
   aAll := oDbf:LoadAll({"FIRST","LAST"})
   FOR i := 1 TO Len(aAll)
      hRec := aAll[i]
      IF HB_HGetDef(hRec, "FIRST", "") == "Charlie"
         ? "    ERROR: Deleted record 'Charlie' found in LoadAll"
         RETURN .F.
      ENDIF
   NEXT
   IF Len(aAll) >= 5
      ? "    ERROR: LoadAll should return < 5 records, got " + ltrim(str(Len(aAll)))
      RETURN .F.
   ENDIF
   ? "    OK: Deleted record removed from LoadAll — " + ltrim(str(Len(aAll))) + " records returned"
RETURN .T.

// TEST T16 - Show: State lookup (external table join)
FUNCTION TestStateLookup()
   LOCAL oStates, oDbf, hRow, lFound, cState, cStateName
   oDbf := CustomerDbf()
   oStates := TStates()
   lFound := oDbf:GetRecno(1, @hRow, NIL, .T.)
   IF !lFound
      ? "    ERROR: Cannot retrieve record 1"
      RETURN .F.
   ENDIF
   cState := HB_HGetDef(hRow, "STATE", "")
   lFound := oStates:Seek(cState, NIL, "code")
   IF !lFound
      ? "    ERROR: State seek failed for code='" + cState + "'"
      RETURN .F.
   ENDIF
   cStateName := oStates:FieldGet("name")
   IF empty(cStateName)
      ? "    ERROR: State name is empty for code='" + cState + "'"
      RETURN .F.
   ENDIF
   ? "    OK: State lookup — code='" + cState + "' -> name='" + cStateName + "'"
RETURN .T.

// TEST T17 - DAL: UDbf Open/Close lifecycle
FUNCTION TestDbfLifecycle()
   LOCAL oDbf, lConnected
   oDbf := CustomerDbf()
   lConnected := oDbf:lConnect
   IF !lConnected
      ? "    ERROR: DBF not connected after Open()"
      RETURN .F.
   ENDIF
   IF empty(oDbf:hFields)
      ? "    ERROR: hFields hash is empty after Open()"
      RETURN .F.
   ENDIF
   ? "    OK: Open — lConnect=.T., hFields has " + ltrim(str(Len(oDbf:hFields))) + " fields"
   oDbf:Close()
   IF oDbf:lConnect
      ? "    ERROR: lConnect should be .F. after Close()"
      RETURN .F.
   ENDIF
   ? "    OK: Close — lConnect=.F."
RETURN .T.

// TEST T18 - DAL: Field visibility control (REQ-FUNC-016)
FUNCTION TestFieldVisibility()
   LOCAL oDbf, aAll, hRec, i, cFirst
   oDbf := CustomerDbf()
   oDbf:Hide("NOTES")
   aAll := oDbf:LoadAll()
   FOR i := 1 TO Len(aAll)
      hRec := aAll[i]
      IF HB_HGetDef(hRec, "NOTES", NIL) != NIL
         ? "    ERROR: NOTES should be hidden but found in record " + ltrim(str(i))
         RETURN .F.
      ENDIF
   NEXT
   hRec := aAll[1]
   IF HB_HGetDef(hRec, "_recno", NIL) == NIL
      ? "    ERROR: _recno should always be present"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hRec, "_deleted", NIL) == NIL
      ? "    ERROR: _deleted should always be present"
      RETURN .F.
   ENDIF
   ? "    OK: Hide('NOTES') works — NOTES absent, _recno and _deleted present"
RETURN .T.

// TEST T19 - DAL: Blank record template
FUNCTION TestBlankRecord()
   LOCAL oDbf, hBlank, cFirst
   oDbf := CustomerDbf()
   hBlank := oDbf:Blank(.T.)
   IF HB_HGetDef(hBlank, "FIRST", "X") != ""
      ? "    ERROR: Blank FIRST should be empty string"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hBlank, "AGE", -1) != 0
      ? "    ERROR: Blank AGE should be 0"
      RETURN .F.
   ENDIF
   IF HB_HGetDef(hBlank, "MARRIED", "X") != ""
      ? "    ERROR: Blank MARRIED should be empty string"
      RETURN .F.
   ENDIF
   ? "    OK: Blank record — FIRST='', AGE=0, MARRIED=''"
RETURN .T.

// TEST T20 - Grid: Empty table handling
FUNCTION TestEmptyGrid()
   LOCAL oDbf, aAll, hRec
   oDbf := CustomerDbf()
   aAll := oDbf:LoadAll()
   IF Len(aAll) != 0
      ? "    ERROR: All records deleted, LoadAll should return empty array"
      RETURN .F.
   ENDIF
   ? "    OK: Empty table — LoadAll returns {}"
RETURN .T.

// Helper: Get CustomerDbf instance
FUNCTION CustomerDbf()
   LOCAL oDbf
   oDbf := UDbf()
   oDbf:cPath := cDataDir
   oDbf:cDbf  := "customers.dbf"
   oDbf:cCdx  := "customers.cdx"
   oDbf:cTag  := "first"
   oDbf:Open()
RETURN oDbf

// Helper: SortGrid (copy from controller for testing)
FUNCTION SortGrid(aGrid, cField, cDir)
   LOCAL aCopy, nI, nLen, nJ, lSwap, cKey, cValI, cValJ
   aCopy := {}
   FOR nI := 1 TO Len(aGrid)
      aAdd(aCopy, aGrid[nI])
   NEXT
   nLen := Len(aCopy)
   FOR nI := 1 TO nLen - 1
      lSwap := .F.
      FOR nJ := 1 TO nLen - nI
         cKey := aCopy[nJ]
         cValI := HB_HGetDef(cKey, cField, "")
         cValJ := HB_HGetDef(aCopy[nJ + 1], cField, "")
         IF cDir == "ASC"
            IF cValI > cValJ
               lSwap := .T.
            ENDIF
         ELSE
            IF cValI < cValJ
               lSwap := .T.
            ENDIF
         ENDIF
         IF lSwap
            aCopy[nJ] := aCopy[nJ + 1]
            aCopy[nJ + 1] := cKey
         ENDIF
      NEXT
   NEXT
RETURN aCopy
