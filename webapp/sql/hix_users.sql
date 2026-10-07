-- ============================================================
-- HIX's own credential store — NOT part of the InvenTree artefact
--
--   DECISION P4.8 (Step 0.2, Option A for `users`, taken 2026-10-07):
--   P1.2a dropped the artefact's `auth_user` on the grounds that "HIX owns
--   users, roles, scopes". That is what this table is: the store that owns
--   the login identity of THIS app, in the file that owns the app's own
--   tables. It is kept out of sql/inventree.sql on purpose - that file is
--   the InvenTree artefact and stays byte-faithful to it, and nothing here
--   joins the FK graph (no FK points at users_users, and users_users points
--   nowhere), so the DAL's graph and the 38-table corpus are untouched.
--
--   The columns mirror the store being replaced, data/users.dbf
--   (ID/NAME/PASS/SALT/ROLES), so the audited defect closures of the users
--   module keep meaning the same thing over the new store:
--     name   the login identity. UNIQUE KEY ix_name is D-09 ("NAME is the
--            login identity, duplicates are refused outright") enforced by
--            the database instead of by a CDX tag; the collation is the
--            server's utf8mb4_unicode_ci (P0.4), which is what replaces the
--            CDX tag keyed on Lower(name) for D-16's case handling.
--     pass   64 hex of 10 000 rounds of salted SHA-256
--            (www/models/hpassword.prg, D-07). Never the password.
--     salt   32 hex from a CSPRNG, per account.
--     roles  "role:ops;ops|role:ops" - the scope string the middlewares
--            read. varchar(255), the same width as the DBF field.
--     version P3.7's optimistic-concurrency column, so a users edit carries
--            the same conflict contract as every other module.
--
--   Seeded by ./seed_users_mysql (runtime hashing, never a committed digest).
-- ============================================================

CREATE TABLE `users_users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(40) NOT NULL DEFAULT '',
  `pass` varchar(128) NOT NULL DEFAULT '',
  `salt` varchar(32) NOT NULL DEFAULT '',
  `roles` varchar(255) NOT NULL DEFAULT '',
  `active` bool NOT NULL DEFAULT 1,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ix_name` (`name`),
  FULLTEXT KEY `ft_name` (`name`)
);
