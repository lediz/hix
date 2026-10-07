-- InvenTree -- the SHIPPED MySQL/MariaDB schema (P1 of INVENTREE-MYSQL-PLAN.md)
--
-- derived from   INVENTREE-MYSQL-SCHEMA.sql (the 79-table reference artefact)
--              by derive-shipped-schema.py; provenance in INVENTREE-MYSQL-SCHEMA.md
-- subset        the 38 tables the functional flow touches (SRS-DAL-CRUD-WEB-UI.md)
-- order         FK dependency order: every target table precedes its referrers
-- load with     ./create_mysql_sql   (webapp/create_mysql_sql.prg, P1.5)
-- seed with     ./seed_inventree     (webapp/seed_inventree.prg, P1.6)
--
-- DECISIONS (the gaps the artefact left open, closed here)
--   P1.1  CREATE TABLE + KEY inline. The artefact's ALTER ... ADD CONSTRAINT
--         section is a comment; MySQL 8 / MariaDB 13 do not enforce FKs anyway,
--         so the KEY index is all the DB gets and the DAL enforces the policy
--         (INVENTREE-MYSQL-PLAN.md Step 0.3: CASCADE 68 / SET_NULL 69 /
--         DO_NOTHING 3 are the app's job, not the server's).
--   P1.1  NOT NULL policy: every NOT NULL column that is not an AUTO_INCREMENT
--         PK and carries no DEFAULT gets one - '' for varchar/char, 0 for
--         int/bigint/double/bool. MariaDB runs STRICT_TRANS_TABLES (P0.4), so
--         an INSERT that omits a NOT NULL column with no DEFAULT is an error,
--         not a silent 0. date/datetime keep NOT NULL with NO default: a
--         literal would be invented data, so the DAL must always supply them.
--   P1.2a FK targets that are not shipped (auth_user, auth_group,
--         contenttypes_contenttype, and InvenTree tables outside the 38)
--         -> the column stays, a plain int, with NO index. HIX owns users,
--         roles and scopes; importing Django's auth_user would import its
--         password hashing, which www/models/hpassword.prg already replaced.
--   P1.2b users_apitoken is dropped whole - its columns are inherited from
--         djangorestframework.authtoken, which is not in the corpus, and HIX
--         authenticates with JWT + HIX_KEY_TOKEN instead. It is not one of the 38.
--   P1.2c longtext / json columns carry no DEFAULT: MySQL rejects one. Asserted
--         over the artefact, not assumed.
--   P1.4  FULLTEXT KEY ft_name / ft_description / ft_keywords for global
--         search (FR-READ-2); KEY ix_IPN / ix_SKU / ix_barcode_hash for exact-
--         match lookup. UNIQUE only where InvenTree declares one - it does NOT
--         declare IPN / SKU / barcode_hash unique, so none was invented here.
--         MariaDB FULLTEXT honours min_word_size (default 3): tokens shorter
--         than that are not indexed; the flow's search route uses LIKE ? for
--         those, not MATCH (P4.1).

-- ============================================================
-- table `stock_stocklocationtype`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app stock | model StockLocationType | table `stock_stocklocationtype`
--   ==================================================================
-- ============================================================
CREATE TABLE `stock_stocklocationtype` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL DEFAULT '',
  `description` varchar(250) NOT NULL DEFAULT '',
  `icon` varchar(100) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  FULLTEXT KEY `ft_name` (`name`),
  FULLTEXT KEY `ft_description` (`description`)
);

-- ============================================================
-- table `users_owner`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app users | model Owner | table `users_owner`
--   ==================================================================
-- ============================================================
CREATE TABLE `users_owner` (
  `id` int NOT NULL AUTO_INCREMENT,
  -- DECISION P1.2a: FK -> contenttypes_contenttype.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `owner_type` int NULL  /* FK -> contenttypes_contenttype.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `owner_id` int NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
);

-- ============================================================
-- table `stock_stocklocation`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app stock | model StockLocation | table `stock_stocklocation`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `stock_stocklocation` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `name` varchar(100) NOT NULL DEFAULT '',
  `description` varchar(250) NOT NULL DEFAULT '',
  `parent` int NULL  /* FK -> stock_stocklocation.id */,
  `pathstring` varchar(250) NOT NULL DEFAULT '',
  `metadata` json NULL,
  `icon` varchar(100) NULL,
  `owner` int NULL  /* FK -> users_owner.id */,
  `structural` bool NOT NULL DEFAULT 0,
  `external` bool NOT NULL DEFAULT 0,
  `location_type` int NULL  /* FK -> stock_stocklocationtype.id */,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stocklocation_parent` (`parent`)  /* -> stock_stocklocation.id  policy=KEEP */,
  KEY `fk_stock_stocklocation_owner` (`owner`)  /* -> users_owner.id  policy=NULL */,
  KEY `fk_stock_stocklocation_location_type` (`location_type`)  /* -> stock_stocklocationtype.id  policy=NULL */,
  FULLTEXT KEY `ft_name` (`name`),
  FULLTEXT KEY `ft_description` (`description`),
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `part_partcategory`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app part | model PartCategory | table `part_partcategory`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_partcategory` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL DEFAULT '',
  `description` varchar(250) NOT NULL DEFAULT '',
  `parent` int NULL  /* FK -> part_partcategory.id */,
  `pathstring` varchar(250) NOT NULL DEFAULT '',
  `default_location` int NULL  /* FK -> stock_stocklocation.id */,
  `structural` bool NOT NULL DEFAULT 0,
  `default_keywords` varchar(250) NULL,
  `icon` varchar(100) NULL,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_partcategory_parent` (`parent`)  /* -> part_partcategory.id  policy=KEEP */,
  KEY `fk_part_partcategory_default_location` (`default_location`)  /* -> stock_stocklocation.id  policy=NULL */,
  FULLTEXT KEY `ft_name` (`name`),
  FULLTEXT KEY `ft_description` (`description`)
);

-- ============================================================
-- table `part_part`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app part | model Part | table `part_part`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `part_part` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `image` varchar(100) NULL,
  `image_width` int NULL,
  `image_height` int NULL,
  `image_custom_data` json NULL,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL DEFAULT '',
  `is_template` bool NOT NULL DEFAULT 0,
  `variant_of` int NULL  /* FK -> part_part.id */,
  `description` varchar(250) NOT NULL DEFAULT '',
  `keywords` varchar(250) NULL,
  `category` int NULL  /* FK -> part_partcategory.id */,
  `IPN` varchar(100) NULL,
  `revision` varchar(100) NULL,
  `revision_of` int NULL  /* FK -> part_part.id */,
  `link` varchar(2000) NULL,
  `default_location` int NULL  /* FK -> stock_stocklocation.id */,
  `default_expiry` int NOT NULL DEFAULT 0,
  `minimum_stock` decimal(19,6) NOT NULL DEFAULT 0,
  `maximum_stock` decimal(19,6) NOT NULL DEFAULT 0,
  `units` varchar(20) NULL DEFAULT '',
  `assembly` bool NOT NULL DEFAULT 0,
  `component` bool NOT NULL DEFAULT 0,
  `trackable` bool NOT NULL DEFAULT 0,
  `testable` bool NOT NULL DEFAULT 0,
  `purchaseable` bool NOT NULL DEFAULT 0,
  `salable` bool NOT NULL DEFAULT 0,
  `active` bool NOT NULL DEFAULT 1,
  `locked` bool NOT NULL DEFAULT 0,
  `virtual` bool NOT NULL DEFAULT 0,
  `consumable` bool NOT NULL DEFAULT 0,
  `bom_validated` bool NOT NULL DEFAULT 0,
  `bom_checksum` varchar(128) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `bom_checked_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `bom_checked_date` date NULL,
  `creation_date` date NULL  /* auto_now_add */,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `creation_user` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `responsible_owner` int NULL  /* FK -> users_owner.id */,
  `base_cost` decimal(19,6) NOT NULL DEFAULT 0,
  `multiple` int NOT NULL DEFAULT 1,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_part_variant_of` (`variant_of`)  /* -> part_part.id  policy=NULL */,
  KEY `fk_part_part_category` (`category`)  /* -> part_partcategory.id  policy=NULL */,
  KEY `fk_part_part_revision_of` (`revision_of`)  /* -> part_part.id  policy=NULL */,
  KEY `fk_part_part_default_location` (`default_location`)  /* -> stock_stocklocation.id  policy=NULL */,
  KEY `fk_part_part_responsible_owner` (`responsible_owner`)  /* -> users_owner.id  policy=NULL */,
  FULLTEXT KEY `ft_name` (`name`),
  FULLTEXT KEY `ft_description` (`description`),
  FULLTEXT KEY `ft_keywords` (`keywords`),
  KEY `ix_IPN` (`IPN`),
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `part_partparametertemplate`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model ParameterTemplate | table `part_partparametertemplate`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_partparametertemplate` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  -- DECISION P1.2a: FK -> contenttypes_contenttype.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `model_type` int NULL  /* FK -> contenttypes_contenttype.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `name` varchar(100) NOT NULL DEFAULT '',
  `units` varchar(25) NOT NULL DEFAULT '',
  `description` varchar(250) NOT NULL DEFAULT '',
  `checkbox` bool NOT NULL DEFAULT 0,
  `choices` varchar(5000) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> common_selectionlist.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `selectionlist` int NULL  /* FK -> common_selectionlist.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `enabled` bool NOT NULL DEFAULT 1,
  `unique` int NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_part_partparametertemplate_name` (`name`),
  FULLTEXT KEY `ft_name` (`name`),
  FULLTEXT KEY `ft_description` (`description`)
);

-- ============================================================
-- table `part_partparameter`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model Parameter | table `part_partparameter`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_partparameter` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `updated_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `metadata` json NULL,
  -- DECISION P1.2a: FK -> contenttypes_contenttype.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `model_type` int NOT NULL DEFAULT 0  /* FK -> contenttypes_contenttype.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `model_id` int NOT NULL DEFAULT 0,
  `template` int NOT NULL DEFAULT 0  /* FK -> part_partparametertemplate.id */,
  `data` varchar(500) NOT NULL DEFAULT '',
  `data_numeric` double NULL,
  `note` varchar(500) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_partparameter_template` (`template`)  /* -> part_partparametertemplate.id  policy=CASCADE */
);

-- ============================================================
-- table `common_projectcode`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model ProjectCode | table `common_projectcode`
--   ==================================================================
-- ============================================================
CREATE TABLE `common_projectcode` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `code` varchar(50) NOT NULL DEFAULT '',
  `description` varchar(200) NOT NULL DEFAULT '',
  `active` bool NOT NULL DEFAULT 1,
  `responsible` int NULL  /* FK -> users_owner.id */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_projectcode_code` (`code`),
  KEY `fk_common_projectcode_responsible` (`responsible`)  /* -> users_owner.id  policy=NULL */,
  FULLTEXT KEY `ft_description` (`description`)
);

-- ============================================================
-- table `company_company`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app company | model Company | table `company_company`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `company_company` (
  `id` int NOT NULL AUTO_INCREMENT,
  `image` varchar(100) NULL,
  `image_width` int NULL,
  `image_height` int NULL,
  `image_custom_data` json NULL,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL DEFAULT '',
  `description` varchar(500) NOT NULL DEFAULT '',
  `website` varchar(2000) NOT NULL DEFAULT '',
  `phone` varchar(50) NOT NULL DEFAULT '',
  `email` varchar(254) NULL,
  `contact` varchar(100) NOT NULL DEFAULT '',
  `link` varchar(2000) NOT NULL DEFAULT '',
  `active` bool NOT NULL DEFAULT 1,
  `is_customer` bool NOT NULL DEFAULT 0,
  `is_supplier` bool NOT NULL DEFAULT 1,
  `is_manufacturer` bool NOT NULL DEFAULT 0,
  `currency` varchar(3) NOT NULL DEFAULT '',
  `tax_id` varchar(50) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  FULLTEXT KEY `ft_name` (`name`),
  FULLTEXT KEY `ft_description` (`description`)
);

-- ============================================================
-- table `company_address`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app company | model Address | table `company_address`
--   ==================================================================
-- ============================================================
CREATE TABLE `company_address` (
  `id` int NOT NULL AUTO_INCREMENT,
  `company` int NOT NULL DEFAULT 0  /* FK -> company_company.id */,
  `title` varchar(100) NOT NULL DEFAULT '',
  `primary` bool NOT NULL DEFAULT 0,
  `line1` varchar(50) NOT NULL DEFAULT '',
  `line2` varchar(50) NOT NULL DEFAULT '',
  `postal_code` varchar(10) NOT NULL DEFAULT '',
  `postal_city` varchar(50) NOT NULL DEFAULT '',
  `province` varchar(50) NOT NULL DEFAULT '',
  `country` varchar(50) NOT NULL DEFAULT '',
  `shipping_notes` varchar(100) NOT NULL DEFAULT '',
  `internal_shipping_notes` varchar(100) NOT NULL DEFAULT '',
  `link` varchar(2000) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_company_address_company` (`company`)  /* -> company_company.id  policy=CASCADE */
);

-- ============================================================
-- table `company_contact`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app company | model Contact | table `company_contact`
--   ==================================================================
-- ============================================================
CREATE TABLE `company_contact` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `company` int NOT NULL DEFAULT 0  /* FK -> company_company.id */,
  `name` varchar(100) NOT NULL DEFAULT '',
  `phone` varchar(100) NOT NULL DEFAULT '',
  `email` varchar(254) NOT NULL DEFAULT '',
  `role` varchar(100) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_company_contact_company` (`company`)  /* -> company_company.id  policy=CASCADE */,
  FULLTEXT KEY `ft_name` (`name`)
);

-- ============================================================
-- table `order_salesorder`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app order | model SalesOrder | table `order_salesorder`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `order_salesorder` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `metadata` json NULL,
  `reference_int` bigint NOT NULL DEFAULT 0,
  `description` varchar(250) NOT NULL DEFAULT '',
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `link` varchar(2000) NOT NULL DEFAULT '',
  `start_date` date NULL,
  `target_date` date NULL,
  `creation_date` date NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `created_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `issue_date` date NULL,
  `updated_at` datetime NULL,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `contact` int NULL  /* FK -> company_contact.id */,
  `address` int NULL  /* FK -> company_address.id */,
  `reference` varchar(64) NOT NULL DEFAULT '',
  `customer` int NULL  /* FK -> company_company.id */,
  `status` int NOT NULL DEFAULT 0,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `customer_reference` varchar(64) NOT NULL DEFAULT '',
  `shipment_date` date NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `shipped_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_order_salesorder_reference` (`reference`),
  KEY `fk_order_salesorder_project_code` (`project_code`)  /* -> common_projectcode.id  policy=KEEP */,
  KEY `fk_order_salesorder_responsible` (`responsible`)  /* -> users_owner.id  policy=KEEP */,
  KEY `fk_order_salesorder_contact` (`contact`)  /* -> company_contact.id  policy=KEEP */,
  KEY `fk_order_salesorder_address` (`address`)  /* -> company_address.id  policy=KEEP */,
  KEY `fk_order_salesorder_customer` (`customer`)  /* -> company_company.id  policy=KEEP */,
  FULLTEXT KEY `ft_description` (`description`),
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `build_build`  (38-table subset of the artefact's 79)
--   InvenTree -- MySQL 8 column layout, derived from the Django models
--   
--   upstream    github.com/inventree/InvenTree @ 575fbdc9072dee89bc5624cb7b2604829826f552
--   backend     Django 5.2.17, django.db.backends.mysql (MySQL 8 / MariaDB)
--   generated   gen-inventree-mysql-schema.py   (provenance: INVENTREE-MYSQL-SCHEMA.md)
--   
--   InvenTree declares no MySQL schema of its own.  Django's ORM builds one from the
--   model classes in src/backend/InvenTree/<app>/models.py; this file is that layout
--   rendered as ordinary MySQL 8.  It is a reference artefact: the only correct way to
--   create InvenTree's database is InvenTree's own `inventree migrate`.
--   
--   Conventions
--   * identifiers are back-quoted (MySQL reserved words: key, status, default, ...)
--   * int = 32-bit (IntegerField / AutoField / ForeignKey to an int PK)
--   * bigint = BigIntegerField / BigAutoField
--   * FK columns are an ordinary column + KEY + a trailing comment naming the target;
--   MySQL has no FK declaration, so the equivalent ALTER TABLE lines are grouped at
--   the foot of the file, commented out
--   * longtext / json columns carry no DEFAULT (MySQL cannot default those types)
--   * column order is mixin-first-then-own; Django orders by a global registration
--   counter, so order here is indicative, not byte-exact
--   * tables owned by Django / third-party apps (auth.*, sessions, admin, taggit,
--   django-q2, allauth, ...) are named where an FK points at them, not defined here
--   ==================================================================
--   app build | model Build | table `build_build`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `build_build` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `reference_int` bigint NOT NULL DEFAULT 0,
  `metadata` json NULL,
  `reference` varchar(64) NOT NULL DEFAULT '',
  `title` varchar(100) NOT NULL DEFAULT '',
  `parent` int NULL  /* FK -> build_build.id */,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `sales_order` int NULL  /* FK -> order_salesorder.id */,
  `take_from` int NULL  /* FK -> stock_stocklocation.id */,
  `external` bool NOT NULL DEFAULT 0,
  `destination` int NULL  /* FK -> stock_stocklocation.id */,
  `quantity` int NOT NULL DEFAULT 1,
  `completed` int NOT NULL DEFAULT 0,
  `status` int NOT NULL DEFAULT 0,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `batch` varchar(100) NULL,
  -- DECISION P1.1: NOT NULL date, no DEFAULT invented - the DAL must always supply it
  `creation_date` date NOT NULL  /* auto_now_add */,
  `start_date` date NULL,
  `target_date` date NULL,
  `completion_date` date NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `completed_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `issued_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `link` varchar(2000) NOT NULL DEFAULT '',
  `priority` int NOT NULL DEFAULT 0,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_build_build_reference` (`reference`),
  KEY `fk_build_build_parent` (`parent`)  /* -> build_build.id  policy=KEEP */,
  KEY `fk_build_build_part` (`part`)  /* -> part_part.id  policy=KEEP */,
  KEY `fk_build_build_sales_order` (`sales_order`)  /* -> order_salesorder.id  policy=KEEP */,
  KEY `fk_build_build_take_from` (`take_from`)  /* -> stock_stocklocation.id  policy=KEEP */,
  KEY `fk_build_build_destination` (`destination`)  /* -> stock_stocklocation.id  policy=KEEP */,
  KEY `fk_build_build_responsible` (`responsible`)  /* -> users_owner.id  policy=KEEP */,
  KEY `fk_build_build_project_code` (`project_code`)  /* -> common_projectcode.id  policy=KEEP */,
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `order_purchaseorder`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app order | model PurchaseOrder | table `order_purchaseorder`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `order_purchaseorder` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `metadata` json NULL,
  `reference_int` bigint NOT NULL DEFAULT 0,
  `description` varchar(250) NOT NULL DEFAULT '',
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `link` varchar(2000) NOT NULL DEFAULT '',
  `start_date` date NULL,
  `target_date` date NULL,
  `creation_date` date NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `created_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `issue_date` date NULL,
  `updated_at` datetime NULL,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `contact` int NULL  /* FK -> company_contact.id */,
  `address` int NULL  /* FK -> company_address.id */,
  `reference` varchar(64) NOT NULL DEFAULT '',
  `status` int NOT NULL DEFAULT 0,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `supplier` int NULL  /* FK -> company_company.id */,
  `supplier_reference` varchar(64) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `received_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `complete_date` date NULL,
  `destination` int NULL  /* FK -> stock_stocklocation.id */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_order_purchaseorder_reference` (`reference`),
  KEY `fk_order_purchaseorder_project_code` (`project_code`)  /* -> common_projectcode.id  policy=KEEP */,
  KEY `fk_order_purchaseorder_responsible` (`responsible`)  /* -> users_owner.id  policy=KEEP */,
  KEY `fk_order_purchaseorder_contact` (`contact`)  /* -> company_contact.id  policy=KEEP */,
  KEY `fk_order_purchaseorder_address` (`address`)  /* -> company_address.id  policy=KEEP */,
  KEY `fk_order_purchaseorder_supplier` (`supplier`)  /* -> company_company.id  policy=KEEP */,
  KEY `fk_order_purchaseorder_destination` (`destination`)  /* -> stock_stocklocation.id  policy=KEEP */,
  FULLTEXT KEY `ft_description` (`description`),
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `company_manufacturerpart`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app company | model ManufacturerPart | table `company_manufacturerpart`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `company_manufacturerpart` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `metadata` json NULL,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `manufacturer` int NULL  /* FK -> company_company.id */,
  `MPN` varchar(100) NULL,
  `link` varchar(2000) NULL,
  `description` varchar(250) NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_company_manufacturerpart_part` (`part`)  /* -> part_part.id  policy=CASCADE */,
  KEY `fk_company_manufacturerpart_manufacturer` (`manufacturer`)  /* -> company_company.id  policy=NULL */,
  FULLTEXT KEY `ft_description` (`description`),
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `part_supplierpart`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app company | model SupplierPart | table `part_supplierpart`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `part_supplierpart` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `updated` datetime NULL  /* auto_now */,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `supplier` int NOT NULL DEFAULT 0  /* FK -> company_company.id */,
  `SKU` varchar(100) NOT NULL DEFAULT '',
  `active` bool NOT NULL DEFAULT 1,
  `primary` bool NOT NULL DEFAULT 0,
  `manufacturer_part` int NULL  /* FK -> company_manufacturerpart.id */,
  `link` varchar(2000) NULL,
  `description` varchar(250) NULL,
  `note` varchar(100) NULL,
  `base_cost` decimal(10,3) NOT NULL DEFAULT 0,
  `packaging` varchar(50) NULL,
  `pack_quantity` varchar(25) NOT NULL DEFAULT '',
  `pack_quantity_native` decimal(20,10) NULL,
  `multiple` int NOT NULL DEFAULT 1,
  `available` decimal(10,3) NOT NULL DEFAULT 0,
  `availability_updated` datetime NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_supplierpart_part` (`part`)  /* -> part_part.id  policy=CASCADE */,
  KEY `fk_part_supplierpart_supplier` (`supplier`)  /* -> company_company.id  policy=CASCADE */,
  KEY `fk_part_supplierpart_manufacturer_part` (`manufacturer_part`)  /* -> company_manufacturerpart.id  policy=NULL */,
  FULLTEXT KEY `ft_description` (`description`),
  KEY `ix_SKU` (`SKU`),
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `stock_stockitem`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app stock | model StockItem | table `stock_stockitem`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `stock_stockitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `updated` datetime NULL  /* auto_now */,
  `metadata` json NULL,
  `parent` int NULL  /* FK -> stock_stockitem.id */,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `supplier_part` int NULL  /* FK -> part_supplierpart.id */,
  `location` int NULL  /* FK -> stock_stocklocation.id */,
  `packaging` varchar(50) NULL,
  `belongs_to` int NULL  /* FK -> stock_stockitem.id */,
  `customer` int NULL  /* FK -> company_company.id */,
  `serial` varchar(100) NULL,
  `serial_int` int NOT NULL DEFAULT 0,
  `link` varchar(2000) NOT NULL DEFAULT '',
  `batch` varchar(100) NULL,
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `build` int NULL  /* FK -> build_build.id */,
  `consumed_by` int NULL  /* FK -> build_build.id */,
  `is_building` bool NOT NULL DEFAULT 0,
  `purchase_order` int NULL  /* FK -> order_purchaseorder.id */,
  `sales_order` int NULL  /* FK -> order_salesorder.id */,
  `expiry_date` date NULL,
  `stocktake_date` date NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `stocktake_user` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `creation_date` datetime NULL  /* auto_now_add */,
  `delete_on_deplete` bool NOT NULL DEFAULT 0,
  `status` int NOT NULL DEFAULT 0,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `purchase_price` decimal(19,6) NULL,
  `purchase_price_currency` char(3) NULL,
  `owner` int NULL  /* FK -> users_owner.id */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stockitem_parent` (`parent`)  /* -> stock_stockitem.id  policy=KEEP */,
  KEY `fk_stock_stockitem_part` (`part`)  /* -> part_part.id  policy=CASCADE */,
  KEY `fk_stock_stockitem_supplier_part` (`supplier_part`)  /* -> part_supplierpart.id  policy=NULL */,
  KEY `fk_stock_stockitem_location` (`location`)  /* -> stock_stocklocation.id  policy=NULL */,
  KEY `fk_stock_stockitem_belongs_to` (`belongs_to`)  /* -> stock_stockitem.id  policy=KEEP */,
  KEY `fk_stock_stockitem_customer` (`customer`)  /* -> company_company.id  policy=NULL */,
  KEY `fk_stock_stockitem_build` (`build`)  /* -> build_build.id  policy=NULL */,
  KEY `fk_stock_stockitem_consumed_by` (`consumed_by`)  /* -> build_build.id  policy=NULL */,
  KEY `fk_stock_stockitem_purchase_order` (`purchase_order`)  /* -> order_purchaseorder.id  policy=NULL */,
  KEY `fk_stock_stockitem_sales_order` (`sales_order`)  /* -> order_salesorder.id  policy=NULL */,
  KEY `fk_stock_stockitem_owner` (`owner`)  /* -> users_owner.id  policy=NULL */,
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `part_supplierpricebreak`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app company | model SupplierPriceBreak | table `part_supplierpricebreak`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_supplierpricebreak` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL  /* auto_now */,
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_supplierpart.id */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_supplierpricebreak_part` (`part`)  /* -> part_supplierpart.id  policy=CASCADE */
);

-- ============================================================
-- table `part_bomitem`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app part | model BomItem | table `part_bomitem`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_bomitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `sub_part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `raw_amount` varchar(25) NOT NULL DEFAULT '',
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `optional` bool NOT NULL DEFAULT 0,
  `consumable` bool NOT NULL DEFAULT 0,
  `setup_quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `attrition` decimal(6,3) NOT NULL DEFAULT 0,
  `rounding_multiple` decimal(15,5) NULL,
  `piece_count` int NOT NULL DEFAULT 1,
  `reference` varchar(5000) NOT NULL DEFAULT '',
  `note` varchar(500) NOT NULL DEFAULT '',
  `checksum` varchar(128) NOT NULL DEFAULT '',
  `validated` bool NOT NULL DEFAULT 0,
  `inherited` bool NOT NULL DEFAULT 0,
  `allow_variants` bool NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_bomitem_part` (`part`)  /* -> part_part.id  policy=CASCADE */,
  KEY `fk_part_bomitem_sub_part` (`sub_part`)  /* -> part_part.id  policy=CASCADE */
);

-- ============================================================
-- table `part_bomitemsubstitute`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app part | model BomItemSubstitute | table `part_bomitemsubstitute`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_bomitemsubstitute` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `bom_item` int NOT NULL DEFAULT 0  /* FK -> part_bomitem.id */,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_bomitemsubstitute_bom_item` (`bom_item`)  /* -> part_bomitem.id  policy=CASCADE */,
  KEY `fk_part_bomitemsubstitute_part` (`part`)  /* -> part_part.id  policy=CASCADE */
);

-- ============================================================
-- table `part_partrelated`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app part | model PartRelated | table `part_partrelated`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_partrelated` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `part_1` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `part_2` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `note` varchar(500) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_partrelated_part_1` (`part_1`)  /* -> part_part.id  policy=KEEP */,
  KEY `fk_part_partrelated_part_2` (`part_2`)  /* -> part_part.id  policy=KEEP */
);

-- ============================================================
-- table `part_partpricing`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app part | model PartPricing | table `part_partpricing`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_partpricing` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL  /* auto_now */,
  `currency` varchar(10) NOT NULL DEFAULT '',
  `scheduled_for_update` bool NOT NULL DEFAULT 0,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `bom_cost_min` decimal(19,6) NULL,
  `bom_cost_min_currency` char(3) NULL,
  `bom_cost_max` decimal(19,6) NULL,
  `bom_cost_max_currency` char(3) NULL,
  `purchase_cost_min` decimal(19,6) NULL,
  `purchase_cost_min_currency` char(3) NULL,
  `purchase_cost_max` decimal(19,6) NULL,
  `purchase_cost_max_currency` char(3) NULL,
  `internal_cost_min` decimal(19,6) NULL,
  `internal_cost_min_currency` char(3) NULL,
  `internal_cost_max` decimal(19,6) NULL,
  `internal_cost_max_currency` char(3) NULL,
  `supplier_price_min` decimal(19,6) NULL,
  `supplier_price_min_currency` char(3) NULL,
  `supplier_price_max` decimal(19,6) NULL,
  `supplier_price_max_currency` char(3) NULL,
  `variant_cost_min` decimal(19,6) NULL,
  `variant_cost_min_currency` char(3) NULL,
  `variant_cost_max` decimal(19,6) NULL,
  `variant_cost_max_currency` char(3) NULL,
  `override_min` decimal(19,6) NULL,
  `override_min_currency` char(3) NULL,
  `override_max` decimal(19,6) NULL,
  `override_max_currency` char(3) NULL,
  `overall_min` decimal(19,6) NULL,
  `overall_min_currency` char(3) NULL,
  `overall_max` decimal(19,6) NULL,
  `overall_max_currency` char(3) NULL,
  `sale_price_min` decimal(19,6) NULL,
  `sale_price_min_currency` char(3) NULL,
  `sale_price_max` decimal(19,6) NULL,
  `sale_price_max_currency` char(3) NULL,
  `sale_history_min` decimal(19,6) NULL,
  `sale_history_min_currency` char(3) NULL,
  `sale_history_max` decimal(19,6) NULL,
  `sale_history_max_currency` char(3) NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_partpricing_part` (`part`)  /* -> part_part.id  policy=CASCADE */
);

-- ============================================================
-- table `order_purchaseorderlineitem`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app order | model PurchaseOrderLineItem | table `order_purchaseorderlineitem`
--   ==================================================================
-- ============================================================
CREATE TABLE `order_purchaseorderlineitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `discount` decimal(5,2) NOT NULL DEFAULT 0,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL DEFAULT '',
  `notes` varchar(500) NOT NULL DEFAULT '',
  `link` varchar(2000) NOT NULL DEFAULT '',
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `order` int NOT NULL DEFAULT 0  /* FK -> order_purchaseorder.id */,
  `part` int NULL  /* FK -> part_supplierpart.id */,
  `received` decimal(15,5) NOT NULL DEFAULT 0,
  `purchase_price` decimal(19,6) NULL,
  `purchase_price_currency` char(3) NULL,
  `build_order` int NULL  /* FK -> build_build.id */,
  `destination` int NULL  /* FK -> stock_stocklocation.id */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_order_purchaseorderlineitem_project_code` (`project_code`)  /* -> common_projectcode.id  policy=KEEP */,
  KEY `fk_order_purchaseorderlineitem_order` (`order`)  /* -> order_purchaseorder.id  policy=KEEP */,
  KEY `fk_order_purchaseorderlineitem_part` (`part`)  /* -> part_supplierpart.id  policy=KEEP */,
  KEY `fk_order_purchaseorderlineitem_build_order` (`build_order`)  /* -> build_build.id  policy=KEEP */,
  KEY `fk_order_purchaseorderlineitem_destination` (`destination`)  /* -> stock_stocklocation.id  policy=KEEP */
);

-- ============================================================
-- table `order_salesorderlineitem`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app order | model SalesOrderLineItem | table `order_salesorderlineitem`
--   ==================================================================
-- ============================================================
CREATE TABLE `order_salesorderlineitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `discount` decimal(5,2) NOT NULL DEFAULT 0,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL DEFAULT '',
  `notes` varchar(500) NOT NULL DEFAULT '',
  `link` varchar(2000) NOT NULL DEFAULT '',
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `order` int NOT NULL DEFAULT 0  /* FK -> order_salesorder.id */,
  `part` int NULL  /* FK -> part_part.id */,
  `sale_price` decimal(19,6) NULL,
  `sale_price_currency` char(3) NULL,
  `shipped` decimal(15,5) NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_order_salesorderlineitem_project_code` (`project_code`)  /* -> common_projectcode.id  policy=KEEP */,
  KEY `fk_order_salesorderlineitem_order` (`order`)  /* -> order_salesorder.id  policy=KEEP */,
  KEY `fk_order_salesorderlineitem_part` (`part`)  /* -> part_part.id  policy=KEEP */
);

-- ============================================================
-- table `order_salesordershipment`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app order | model SalesOrderShipment | table `order_salesordershipment`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `order_salesordershipment` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL DEFAULT '',
  `barcode_hash` varchar(128) NOT NULL DEFAULT '',
  `metadata` json NULL,
  `order` int NOT NULL DEFAULT 0  /* FK -> order_salesorder.id */,
  `shipment_address` int NULL  /* FK -> company_address.id */,
  `shipment_date` date NULL,
  `delivery_date` date NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `checked_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `reference` varchar(100) NOT NULL DEFAULT '1',
  `tracking_number` varchar(100) NOT NULL DEFAULT '',
  `invoice_number` varchar(100) NOT NULL DEFAULT '',
  `link` varchar(2000) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_order_salesordershipment_order` (`order`)  /* -> order_salesorder.id  policy=KEEP */,
  KEY `fk_order_salesordershipment_shipment_address` (`shipment_address`)  /* -> company_address.id  policy=KEEP */,
  KEY `ix_barcode_hash` (`barcode_hash`)
);

-- ============================================================
-- table `order_salesorderallocation`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app order | model SalesOrderAllocation | table `order_salesorderallocation`
--   ==================================================================
-- ============================================================
CREATE TABLE `order_salesorderallocation` (
  `id` int NOT NULL AUTO_INCREMENT,
  `line` int NOT NULL DEFAULT 0  /* FK -> order_salesorderlineitem.id */,
  `shipment` int NULL  /* FK -> order_salesordershipment.id */,
  `item` int NOT NULL DEFAULT 0  /* FK -> stock_stockitem.id */,
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_order_salesorderallocation_line` (`line`)  /* -> order_salesorderlineitem.id  policy=KEEP */,
  KEY `fk_order_salesorderallocation_shipment` (`shipment`)  /* -> order_salesordershipment.id  policy=KEEP */,
  KEY `fk_order_salesorderallocation_item` (`item`)  /* -> stock_stockitem.id  policy=KEEP */
);

-- ============================================================
-- table `build_buildline`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app build | model BuildLine | table `build_buildline`
--   ==================================================================
-- ============================================================
CREATE TABLE `build_buildline` (
  `id` int NOT NULL AUTO_INCREMENT,
  `build` int NOT NULL DEFAULT 0  /* FK -> build_build.id */,
  `bom_item` int NOT NULL DEFAULT 0  /* FK -> part_bomitem.id */,
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `consumed` decimal(15,5) NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_build_buildline_build_bom_item` (`build`, `bom_item`),
  KEY `fk_build_buildline_build` (`build`)  /* -> build_build.id  policy=KEEP */,
  KEY `fk_build_buildline_bom_item` (`bom_item`)  /* -> part_bomitem.id  policy=KEEP */
);

-- ============================================================
-- table `build_builditem`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app build | model BuildItem | table `build_builditem`
--   ==================================================================
-- ============================================================
CREATE TABLE `build_builditem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `build_line` int NULL  /* FK -> build_buildline.id */,
  `stock_item` int NOT NULL DEFAULT 0  /* FK -> stock_stockitem.id */,
  `quantity` decimal(15,5) NOT NULL DEFAULT 0,
  `install_into` int NULL  /* FK -> stock_stockitem.id */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_build_builditem_build_line_stock_item_install_into` (`build_line`, `stock_item`, `install_into`),
  KEY `fk_build_builditem_build_line` (`build_line`)  /* -> build_buildline.id  policy=KEEP */,
  KEY `fk_build_builditem_stock_item` (`stock_item`)  /* -> stock_stockitem.id  policy=KEEP */,
  KEY `fk_build_builditem_install_into` (`install_into`)  /* -> stock_stockitem.id  policy=KEEP */
);

-- ============================================================
-- table `part_partstocktake`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app part | model PartStocktake | table `part_partstocktake`
--   ==================================================================
-- ============================================================
CREATE TABLE `part_partstocktake` (
  `id` int NOT NULL AUTO_INCREMENT,
  `part` int NOT NULL DEFAULT 0  /* FK -> part_part.id */,
  `item_count` int NOT NULL DEFAULT 1,
  `quantity` decimal(19,5) NOT NULL DEFAULT 0,
  -- DECISION P1.1: NOT NULL date, no DEFAULT invented - the DAL must always supply it
  `date` date NOT NULL  /* auto_now_add */,
  `cost_min` decimal(19,6) NULL,
  `cost_min_currency` char(3) NULL,
  `cost_max` decimal(19,6) NULL,
  `cost_max_currency` char(3) NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_partstocktake_part` (`part`)  /* -> part_part.id  policy=KEEP */
);

-- ============================================================
-- table `stock_stockitemtestresult`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app stock | model StockItemTestResult | table `stock_stockitemtestresult`
--   ==================================================================
-- ============================================================
CREATE TABLE `stock_stockitemtestresult` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `stock_item` int NOT NULL DEFAULT 0  /* FK -> stock_stockitem.id */,
  -- DECISION P1.2a: FK -> part_parttesttemplate.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `template` int NOT NULL DEFAULT 0  /* FK -> part_parttesttemplate.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `result` bool NOT NULL DEFAULT 0,
  `value` varchar(500) NOT NULL DEFAULT '',
  `attachment` varchar(100) NULL,
  `notes` varchar(500) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `user` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `test_station` varchar(500) NOT NULL DEFAULT '',
  `started_datetime` datetime NULL,
  `finished_datetime` datetime NULL,
  -- DECISION P1.1: NOT NULL date, no DEFAULT invented - the DAL must always supply it
  `date` datetime NOT NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stockitemtestresult_stock_item` (`stock_item`)  /* -> stock_stockitem.id  policy=KEEP */
);

-- ============================================================
-- table `stock_stockitemtracking`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app stock | model StockItemTracking | table `stock_stockitemtracking`
--   ==================================================================
-- ============================================================
CREATE TABLE `stock_stockitemtracking` (
  `id` int NOT NULL AUTO_INCREMENT,
  `tracking_type` int NOT NULL DEFAULT 0,
  `item` int NULL  /* FK -> stock_stockitem.id */,
  `part` int NULL  /* FK -> part_part.id */,
  -- DECISION P1.1: NOT NULL date, no DEFAULT invented - the DAL must always supply it
  `date` datetime NOT NULL  /* auto_now_add */,
  `notes` varchar(512) NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `user` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `deltas` json NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stockitemtracking_item` (`item`)  /* -> stock_stockitem.id  policy=KEEP */,
  KEY `fk_stock_stockitemtracking_part` (`part`)  /* -> part_part.id  policy=KEEP */
);

-- ============================================================
-- table `common_inventreesetting`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model InvenTreeSetting | table `common_inventreesetting`
--   ==================================================================
-- ============================================================
CREATE TABLE `common_inventreesetting` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(50) NOT NULL DEFAULT '',
  `value` varchar(2000) NOT NULL DEFAULT '',
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_inventreesetting_key` (`key`)
);

-- ============================================================
-- table `common_inventreeusersetting`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model InvenTreeUserSetting | table `common_inventreeusersetting`
--   ==================================================================
-- ============================================================
CREATE TABLE `common_inventreeusersetting` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(50) NOT NULL DEFAULT '',
  `value` varchar(2000) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `user` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
);

-- ============================================================
-- table `common_note`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model Note | table `common_note`
--   ==================================================================
-- ============================================================
CREATE TABLE `common_note` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `updated_by` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `metadata` json NULL,
  `template` bool NOT NULL DEFAULT 0,
  -- DECISION P1.2a: FK -> contenttypes_contenttype.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `model_type` int NULL  /* FK -> contenttypes_contenttype.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `model_id` int NULL,
  `primary` bool NOT NULL DEFAULT 0,
  `title` varchar(100) NOT NULL DEFAULT '',
  `description` varchar(250) NOT NULL DEFAULT '',
  `content` longtext NOT NULL,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  FULLTEXT KEY `ft_description` (`description`)
);

-- ============================================================
-- table `common_attachment`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model Attachment | table `common_attachment`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
--   ==================================================================
-- ============================================================
CREATE TABLE `common_attachment` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `model_type` varchar(100) NOT NULL DEFAULT '',
  `model_id` int NOT NULL DEFAULT 0,
  `attachment` varchar(100) NULL,
  `thumbnail` varchar(100) NULL,
  `link` varchar(2000) NULL,
  `comment` varchar(250) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `upload_user` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `upload_date` date NULL  /* auto_now_add */,
  `is_image` bool NOT NULL DEFAULT 0,
  `file_size` int NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
);

-- ============================================================
-- table `common_barcodescanresult`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app common | model BarcodeScanResult | table `common_barcodescanresult`
--   ==================================================================
-- ============================================================
CREATE TABLE `common_barcodescanresult` (
  `id` int NOT NULL AUTO_INCREMENT,
  `data` varchar(255) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `user` int NULL  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  -- DECISION P1.1: NOT NULL date, no DEFAULT invented - the DAL must always supply it
  `timestamp` datetime NOT NULL  /* auto_now_add */,
  `endpoint` varchar(250) NULL,
  `context` json NULL,
  `response` json NULL,
  `result` bool NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
);

-- ============================================================
-- table `users_userprofile`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app users | model UserProfile | table `users_userprofile`
--   ==================================================================
-- ============================================================
CREATE TABLE `users_userprofile` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  -- DECISION P1.2a: FK -> auth_user.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `user` int NOT NULL DEFAULT 0  /* FK -> auth_user.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `language` varchar(10) NULL,
  `theme` json NULL,
  `widgets` json NULL,
  `displayname` varchar(255) NULL,
  `position` varchar(255) NULL,
  `status` varchar(2000) NULL,
  `location` varchar(2000) NULL,
  `active` bool NOT NULL DEFAULT 1,
  `contact` varchar(255) NULL,
  `type` varchar(10) NOT NULL DEFAULT '',
  `organisation` varchar(255) NULL,
  -- DECISION P1.2a: FK -> auth_group.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `primary_group` int NULL  /* FK -> auth_group.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
);

-- ============================================================
-- table `users_ruleset`  (38-table subset of the artefact's 79)
--   ==================================================================
--   app users | model RuleSet | table `users_ruleset`
--   ==================================================================
-- ============================================================
CREATE TABLE `users_ruleset` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL DEFAULT '',
  -- DECISION P1.2a: FK -> auth_group.id is not shipped -> plain int column, no index (HIX owns users, roles, scopes)
  `group` int NOT NULL DEFAULT 0  /* FK -> auth_group.id - target not shipped (P1.2a): no KEY, no policy, inert until the target ships */,
  `can_view` bool NOT NULL DEFAULT 0,
  `can_add` bool NOT NULL DEFAULT 0,
  `can_change` bool NOT NULL DEFAULT 0,
  `can_delete` bool NOT NULL DEFAULT 0,
  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact
  `version` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  FULLTEXT KEY `ft_name` (`name`)
);

-- ============================================================
-- foreign keys inside the shipped subset (MySQL does not enforce
-- these; they are the DAL's policy surface - Step 0.3)
-- ============================================================
-- build_build.parent -> build_build.id
-- build_build.part -> part_part.id
-- build_build.sales_order -> order_salesorder.id
-- build_build.take_from -> stock_stocklocation.id
-- build_build.destination -> stock_stocklocation.id
-- build_build.responsible -> users_owner.id
-- build_build.project_code -> common_projectcode.id
-- build_builditem.build_line -> build_buildline.id
-- build_builditem.stock_item -> stock_stockitem.id
-- build_builditem.install_into -> stock_stockitem.id
-- build_buildline.build -> build_build.id
-- build_buildline.bom_item -> part_bomitem.id
-- part_partparameter.template -> part_partparametertemplate.id
-- common_projectcode.responsible -> users_owner.id
-- company_address.company -> company_company.id
-- company_contact.company -> company_company.id
-- company_manufacturerpart.part -> part_part.id
-- company_manufacturerpart.manufacturer -> company_company.id
-- part_supplierpart.part -> part_part.id
-- part_supplierpart.supplier -> company_company.id
-- part_supplierpart.manufacturer_part -> company_manufacturerpart.id
-- part_supplierpricebreak.part -> part_supplierpart.id
-- order_purchaseorder.project_code -> common_projectcode.id
-- order_purchaseorder.responsible -> users_owner.id
-- order_purchaseorder.contact -> company_contact.id
-- order_purchaseorder.address -> company_address.id
-- order_purchaseorder.supplier -> company_company.id
-- order_purchaseorder.destination -> stock_stocklocation.id
-- order_purchaseorderlineitem.project_code -> common_projectcode.id
-- order_purchaseorderlineitem.order -> order_purchaseorder.id
-- order_purchaseorderlineitem.part -> part_supplierpart.id
-- order_purchaseorderlineitem.build_order -> build_build.id
-- order_purchaseorderlineitem.destination -> stock_stocklocation.id
-- order_salesorder.project_code -> common_projectcode.id
-- order_salesorder.responsible -> users_owner.id
-- order_salesorder.contact -> company_contact.id
-- order_salesorder.address -> company_address.id
-- order_salesorder.customer -> company_company.id
-- order_salesorderallocation.line -> order_salesorderlineitem.id
-- order_salesorderallocation.shipment -> order_salesordershipment.id
-- order_salesorderallocation.item -> stock_stockitem.id
-- order_salesorderlineitem.project_code -> common_projectcode.id
-- order_salesorderlineitem.order -> order_salesorder.id
-- order_salesorderlineitem.part -> part_part.id
-- order_salesordershipment.order -> order_salesorder.id
-- order_salesordershipment.shipment_address -> company_address.id
-- part_bomitem.part -> part_part.id
-- part_bomitem.sub_part -> part_part.id
-- part_bomitemsubstitute.bom_item -> part_bomitem.id
-- part_bomitemsubstitute.part -> part_part.id
-- part_part.variant_of -> part_part.id
-- part_part.category -> part_partcategory.id
-- part_part.revision_of -> part_part.id
-- part_part.default_location -> stock_stocklocation.id
-- part_part.responsible_owner -> users_owner.id
-- part_partcategory.parent -> part_partcategory.id
-- part_partcategory.default_location -> stock_stocklocation.id
-- part_partpricing.part -> part_part.id
-- part_partrelated.part_1 -> part_part.id
-- part_partrelated.part_2 -> part_part.id
-- part_partstocktake.part -> part_part.id
-- stock_stockitem.parent -> stock_stockitem.id
-- stock_stockitem.part -> part_part.id
-- stock_stockitem.supplier_part -> part_supplierpart.id
-- stock_stockitem.location -> stock_stocklocation.id
-- stock_stockitem.belongs_to -> stock_stockitem.id
-- stock_stockitem.customer -> company_company.id
-- stock_stockitem.build -> build_build.id
-- stock_stockitem.consumed_by -> build_build.id
-- stock_stockitem.purchase_order -> order_purchaseorder.id
-- stock_stockitem.sales_order -> order_salesorder.id
-- stock_stockitem.owner -> users_owner.id
-- stock_stockitemtestresult.stock_item -> stock_stockitem.id
-- stock_stockitemtracking.item -> stock_stockitem.id
-- stock_stockitemtracking.part -> part_part.id
-- stock_stocklocation.parent -> stock_stocklocation.id
-- stock_stocklocation.owner -> users_owner.id
-- stock_stocklocation.location_type -> stock_stocklocationtype.id

-- FKs dropped: the column is shipped, the relation is not.
-- HIX's own user / role ids live in the users module, not here.
-- build_build.completed_by -> (auth_user.id) not shipped
-- build_build.issued_by -> (auth_user.id) not shipped
-- common_attachment.upload_user -> (auth_user.id) not shipped
-- common_barcodescanresult.user -> (auth_user.id) not shipped
-- common_inventreeusersetting.user -> (auth_user.id) not shipped
-- common_note.updated_by -> (auth_user.id) not shipped
-- common_note.model_type -> (contenttypes_contenttype.id) not shipped
-- part_partparameter.updated_by -> (auth_user.id) not shipped
-- part_partparameter.model_type -> (contenttypes_contenttype.id) not shipped
-- part_partparametertemplate.model_type -> (contenttypes_contenttype.id) not shipped
-- part_partparametertemplate.selectionlist -> (common_selectionlist.id) not shipped
-- order_purchaseorder.created_by -> (auth_user.id) not shipped
-- order_purchaseorder.received_by -> (auth_user.id) not shipped
-- order_salesorder.created_by -> (auth_user.id) not shipped
-- order_salesorder.shipped_by -> (auth_user.id) not shipped
-- order_salesordershipment.checked_by -> (auth_user.id) not shipped
-- part_part.bom_checked_by -> (auth_user.id) not shipped
-- part_part.creation_user -> (auth_user.id) not shipped
-- stock_stockitem.stocktake_user -> (auth_user.id) not shipped
-- stock_stockitemtestresult.template -> (part_parttesttemplate.id) not shipped
-- stock_stockitemtestresult.user -> (auth_user.id) not shipped
-- stock_stockitemtracking.user -> (auth_user.id) not shipped
-- users_owner.owner_type -> (contenttypes_contenttype.id) not shipped
-- users_ruleset.group -> (auth_group.id) not shipped
-- users_userprofile.user -> (auth_user.id) not shipped
-- users_userprofile.primary_group -> (auth_group.id) not shipped

-- ============================================================
-- index
-- ============================================================
-- stock_stocklocationtype                        6 cols   1 idx  2 added
-- users_owner                                    4 cols   1 idx  0 added
-- stock_stocklocation                           17 cols   4 idx  3 added
-- part_partcategory                             14 cols   3 idx  2 added
-- part_part                                     46 cols   6 idx  5 added
-- part_partparametertemplate                    12 cols   2 idx  2 added
-- part_partparameter                            11 cols   2 idx  0 added
-- common_projectcode                             7 cols   3 idx  1 added
-- company_company                               20 cols   1 idx  2 added
-- company_address                               14 cols   2 idx  0 added
-- company_contact                                8 cols   2 idx  1 added
-- order_salesorder                              25 cols   7 idx  2 added
-- build_build                                   32 cols   9 idx  1 added
-- order_purchaseorder                           26 cols   8 idx  2 added
-- company_manufacturerpart                      10 cols   3 idx  2 added
-- part_supplierpart                             22 cols   4 idx  3 added
-- stock_stockitem                               33 cols  12 idx  1 added
-- part_supplierpricebreak                        7 cols   2 idx  0 added
-- part_bomitem                                  19 cols   3 idx  0 added
-- part_bomitemsubstitute                         5 cols   3 idx  0 added
-- part_partrelated                               6 cols   3 idx  0 added
-- part_partpricing                              42 cols   2 idx  0 added
-- order_purchaseorderlineitem                   19 cols   6 idx  0 added
-- order_salesorderlineitem                      17 cols   4 idx  0 added
-- order_salesordershipment                      14 cols   3 idx  1 added
-- order_salesorderallocation                     6 cols   4 idx  0 added
-- build_buildline                                6 cols   4 idx  0 added
-- build_builditem                                7 cols   5 idx  0 added
-- part_partstocktake                            10 cols   2 idx  0 added
-- stock_stockitemtestresult                     14 cols   2 idx  0 added
-- stock_stockitemtracking                        9 cols   3 idx  0 added
-- common_inventreesetting                        4 cols   2 idx  0 added
-- common_inventreeusersetting                    5 cols   1 idx  0 added
-- common_note                                   12 cols   1 idx  1 added
-- common_attachment                             13 cols   1 idx  0 added
-- common_barcodescanresult                       9 cols   1 idx  0 added
-- users_userprofile                             16 cols   1 idx  0 added
-- users_ruleset                                  8 cols   1 idx  1 added
-- 38 tables
