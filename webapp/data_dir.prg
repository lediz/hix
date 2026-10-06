/*
 * data_dir.prg - shared helper for the adhoc data tools in webapp/
 *
 * Include it (#include "data_dir.prg") and call DataDir() to find out where
 * the DBF/CDX files live.  Every one of these tools used to hardcode
 * /home/jack/Projects/pi-agent/webapp/data, the path of an earlier checkout
 * of this project, so run from here they rewrote a different tree's data in
 * silence - and once that checkout moved, they simply failed.
 *
 * Resolution order:
 *   1. HIX_DATA_DIR, if set
 *   2. "data" relative to the current directory - webapp/data when the tool
 *      is run from webapp/, which is where its binary lands
 *
 * The directory is created if it is missing, and every tool prints where it
 * is writing.  DataDir() returns NIL (and sets exit code 1) if the directory
 * can be neither found nor created; callers must check.
 */

STATIC FUNCTION DataDir()
   LOCAL cDir := GetEnv( "HIX_DATA_DIR" )

   IF Empty( cDir )
      cDir := "data"
   ENDIF

   IF ! hb_DirExists( cDir )
      IF hb_DirCreate( cDir ) <> 0
         QOut( "cannot create " + cDir + " (cwd is " + CurDir() + ")" )
         QOut( "aborted; nothing was written." )
         ErrorLevel( 1 )
         RETURN NIL
      ENDIF
      QOut( "created " + cDir )
   ENDIF

   QOut( "data dir: " + cDir + "   (cwd: " + CurDir() + ")" )

RETURN cDir
