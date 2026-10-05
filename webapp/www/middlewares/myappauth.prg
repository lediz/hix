/*-----------------------------------------------------------
  File ......: myappauth.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-07-17
  Version....: 5.1.0
  Description: Session-based auth middleware group for Fenix.
               MyAppAuth — SecHeaders + Session + HIX_MwIsAuth.
               HIX_MwSecHeaders first in the chain (PENTEST-REPORT.md §8).
  Usage      : "middleware": "MyAppAuth"
 -----------------------------------------------------------*/

FUNCTION MyAppAuth( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )
   
   o:Add( UMiddleware():New( "HIX_MwSecHeaders" ) )
   o:Add( UMiddleware():New( "HIX_MwSession"  ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"   ) )
   
RETURN o:Run()
