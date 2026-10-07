/*-----------------------------------------------------------
  File ......: healthdb.prg
  Author.....: Charles 9000
  Created....: 2026-10-07
  Modified...: 2026-10-07
  Version....: 1.0.0
  Description: P2.3 of INVENTREE-MYSQL-PLAN.md - the pool's own
               metrics, so the cascade can be read instead of
               guessed: "MySQL max_connections > HIX workers >=
               WDO pool_size", verified by "free never 0".

               GET /health/db, middleware MyAppAuth (SecHeaders +
               Session + IsAuth): a diagnostic, so it needs a
               session, but no scope - it reports pool counters
               only. No table name, no host, no user, no password
               is in the response; WDO_PoolStats returns driver /
               size / busy / free / closed and nothing else.

               No connection is borrowed here. A health route must
               answer while every slot is busy, and WDO_Get() would
               block for one. P3.4's discipline (one WDO_Get per
               handler, Close() on every exit path) belongs to the
               handlers that use the pool, not to this route.

  Usage      : GET /health/db        (session required)
               200  { ok, driver, size, busy, free, closed }
               503  { ok: false, error, hint }  - no pool registered
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL hStats, hOut

   hStats := WDO_PoolStats( "mysql" )

   IF ! ValType( hStats ) == 'H'
      USendJson( { "ok"    => .F., ;
                   "error" => "no MySQL/MariaDB pool registered", ;
                   "hint"  => "the pool is started by app.prg from DB_PWD/DB_USER/" ;
                              + "DB_NAME in the environment, not from www/config.json" ;
                              + " (that file is inside the document root)" }, ;
                 503 )
      RETURN NIL
   ENDIF

   //  Fields copied on purpose: the response is this route's own shape,
   //  not the framework's hash, so a future WDO_PoolStats field cannot
   //  leak through it.
   hOut := { "ok"     => .T., ;
             "driver" => hStats[ "driver" ], ;
             "size"   => hStats[ "size" ],   ;
             "busy"   => hStats[ "busy" ],   ;
             "free"   => hStats[ "free" ],   ;
             "closed" => hStats[ "closed" ] }

RETURN USendJson( hOut, 200 )
