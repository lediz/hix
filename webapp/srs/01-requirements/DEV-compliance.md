
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
"No SQL" does not apply to P1 and the later phases of
@webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md, which put InvenTree's MySQL
schema behind the DAL on the HIX WDO MySQL/MariaDB pool. It applies
everywhere else, including the audited webapp/ DAL as it ships today
(webapp/www/models, controllers, views) and any other work here.

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
clauses; see @webapp/srs/03-implementation/P0-MYSQL-HOST-RESULTS-2026-10-07.md
for what P0 did against them.
