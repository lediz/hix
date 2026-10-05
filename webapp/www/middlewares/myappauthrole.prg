/*-----------------------------------------------------------
  File ......: myappauthrole.prg
  Author.....: Charly 9000
  Created....: 2026-07-17
  Modified...: 2026-07-17
  Version....: 1.1.0
  Description: Session-based auth + role/scope middleware group for Fenix.
               MyAppAuthRole — SecHeaders + Session + HIX_MwIsAuth + HIX_MwHasRole.
               HIX_MwSecHeaders first in the chain (PENTEST-REPORT.md §8).
  Usage      : "middleware": "MyAppAuthRole", "scope": "customers"
               "middleware": "MyAppAuthRole", "scope": "customers:edit"
 -----------------------------------------------------------*/

FUNCTION MyAppAuthRole( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )
   
   o:Add( UMiddleware():New( "HIX_MwSecHeaders" ) )
   o:Add( UMiddleware():New( "HIX_MwSession"  ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"   ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole"  ) )
   
RETURN o:Run()
