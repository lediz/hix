/*
 * probe_fmode.prg - what can the app see and control about file modes?
 *
 * Adhoc tool, lives inside the project folder (webapp/srs/DEV-compliance.md).
 * Harbour core only, no contrib, no SQL, no external process call.
 *
 * Purpose: HIX writes session files with hb_MemoWrit() + FRename() and never
 * sets a mode, so they inherit the process umask; under the usual 0022 they
 * land 0644 (group/other readable) inside the 0700 store (PENTEST-REPORT.md
 * §7).  The application may not patch HIX (no change outside the project
 * folder), so this probe answers two questions:
 *
 *   1. Can Harbour CHANGE a mode?  umask() and chmod() are documented POSIX
 *      wrappers but are not linked into the core libraries: a version of this
 *      probe that calls them fails to link with "undefined reference to
 *      HB_FUN_UMASK / HB_FUN_CHMOD".  So no Harbour-side chmod exists.
 *   2. Can Harbour READ a mode?  Tested below with Directory(); the attribute
 *      string is printed so the POSIX group/other bits can be checked.
 *
 * Build: hbmk2 probe_fmode.hbp
 * Run:   timeout 30 ./probe_fmode < /dev/null
 *        Time-bounded and non-interactive on purpose: an unguarded runtime
 *        error in this project's probes pops Harbour's GT error dialog, which
 *        waits for a keypress and wedges an unattended run.  Every risky call
 *        is wrapped in BEGIN SEQUENCE ... RECOVER, and the runner adds the
 *        wall-clock bound.  Same policy as test/verify-users-fixes.sh.
 *
 * The modes themselves are created by the shell (chmod) and read back here.
 */

#DEFINE C_DIR    ".tmp_probe_fmode"
#DEFINE N_PROBE_TIMEOUT 30

// _Safe - run uFunc, return its value, or the error description on failure.
STATIC FUNCTION _Safe( uFunc )

   LOCAL oErr
   LOCAL uVal

   BEGIN SEQUENCE WITH {| oE | Break( oE ) }
      uVal := Eval( uFunc )
   RECOVER USING oErr
      uVal := "ERROR: " + If( Valtype( oErr:description ) == "C", oErr:description, "failed" )
   END SEQUENCE

RETURN uVal

// _Attr - attribute string Harbour reports for cFile, or a marker.
STATIC FUNCTION _Attr( cFile )

   LOCAL aList
   LOCAL cOut

   aList := _Safe( {| | Directory( cFile ) } )
   IF Valtype( aList ) != "A" .OR. Len( aList ) == 0
      RETURN "<no dir entry>"
   ENDIF
   IF Valtype( aList[ 1 ] ) != "A" .OR. Len( aList[ 1 ] ) < 2
      RETURN "<entry has no attribute field>"
   ENDIF

   cOut := aList[ 1 ][ 2 ]
   IF Valtype( cOut ) != "C"
      RETURN "<attribute field is not character>"
   ENDIF

RETURN "attr=[" + cOut + "]"

FUNCTION Main()

   LOCAL aNames := { "m0644", "m0600", "m0640", "m0400" }
   LOCAL cFile
   LOCAL cDirNew
   LOCAL nI

   // Nothing here may block: the whole body is evaluated under the runner's
   // timeout, and every call that can raise goes through _Safe().
   ? "=== probe_fmode (timeout " + hb_NToS( N_PROBE_TIMEOUT ) + "s, non-interactive) ==="

   // (1) was established by the linker: umask()/chmod() are not in the core
   // libraries, so an existing file's mode cannot be changed from Harbour.
   ? "change mode from Harbour : impossible (umask/chmod not linked)"

   IF ! hb_DirExists( C_DIR )
      ? "create probe dir       :", _Safe( {| | hb_DirCreate( C_DIR ) } )
   ENDIF

   ? ""
   ? "--- reading modes Harbour can see ---"
   FOR nI := 1 TO Len( aNames )
      cFile := C_DIR + hb_ps() + aNames[ nI ]
      ? Pad( cFile, 30 ), _Attr( cFile )
   NEXT

   ? ""
   ? "--- directory created by hb_DirCreate() (what HIX uses for .sessions) ---"
   cDirNew := C_DIR + hb_ps() + "d_probe"
   IF ! hb_DirExists( cDirNew )
      ? "hb_DirCreate           :", _Safe( {| | hb_DirCreate( cDirNew ) } )
   ENDIF
   ? Pad( cDirNew, 30 ), _Attr( cDirNew + hb_ps() + "*" )

RETURN NIL
