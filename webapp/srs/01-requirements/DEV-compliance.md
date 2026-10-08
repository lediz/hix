
Constraints:
WebApp must strictly comply with HIX style only. No SQL. No 3rd Party WEB UI.
Only HIX framework and Harbour language is allowed. Create local git on current project folder.
Adhoc tools, scripts, and alike should only be created in project folder.
No change will be done outside project folder.

Build:
Build the WebApp using "hbmk2 app.hbp" only.
Web service will use pot 9090.

References:
-HIX transpiler for Harbour @repository root (this repo)
-WebApp based on HIX CRUD approach @webapp/
-DAL @webapp/srs/01-requirements/SRS-DAL-CRUD-WEB-UI.md
-SRS @webapp/srs/01-requirements/SRS-Harbour-HIX.md

Exception (2026-10-07), scoped - the clause "No SQL":
"No SQL" did not apply to P1 and the later phases of
the MySQL DAL plan (deleted 2026-10-08; see git log), which put that
MySQL schema behind the DAL on the HIX WDO MySQL/MariaDB pool. It applies
everywhere else, including the audited webapp/ DAL as it ships today
(webapp/www/models, controllers, views) and any other work here.

RETIRED (2026-10-08): the exception no longer applies to anything. The MySQL
DAL, its pool, its schema files and its seeders were removed from the
application, and the store is the RDDCDX RDD (DBF + CDX) again - data/users.dbf
and data/customers.dbf, opened through the framework's UDbf() with the driver
www/config.json names ("dbf" -> "rddname"). No database engine is opened
anywhere in this app, so "No SQL" binds everywhere, with no exception. The
plans and results records that graded themselves against the exception are kept,
unread as obligations, and were **deleted** with the DAL they described - `git log`
is the record of them.

State as of 2026-10-08, so this clause is not read as a green light: the removal
above is done and the framework builds, but the suites over the new shape have
NOT been run to a result. test/test_customer_module.sh reports 21/50 because the
login limiter (www/middlewares/config.json -> setup.ratelimit.login_max 5 per
login_window 60) is smaller than the number of /auth calls the suite makes, so
most of its assertions fail on a 429/302 rather than on what they name. See
@webapp/srs/03-implementation/P0-DBFCDX-STORE-RESULTS-2026-10-08.md §4.

Allowed form of the exception, and nothing wider:
- database access only through the HIX WDO pool: WDO_Get / Prepare / BindParam /
  Execute / Free / Close, and BeginTrans / Commit / Rollback. The driver is
  framework code at @src/wdo/mysql/ (hix_server.hbp:131-136 -> hix_server.hbx),
  so T4 "Only HIX framework and Harbour language" stays true
- the schema, its seeders and its probes live in the project folder (sql/, adhoc
  Harbour CLI tools), so T5 and T6 stay true
- no other database engine, no SQL library of its own, no third-party database
  or database UI, so T1 and T3 stay true
- the WebApp build and port are untouched by the exception: T7 (hbmk2 app.hbp)
  and T8 (port 9090) are unchanged

Recorded because the plan that P1 implements grades itself against these
clauses; the records that graded themselves against it were deleted with the DAL
they described - git log is the record of them.
