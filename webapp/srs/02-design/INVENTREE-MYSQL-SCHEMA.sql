-- InvenTree -- MySQL 8 column layout, derived from the Django models
--
-- upstream    github.com/inventree/InvenTree @ 575fbdc9072dee89bc5624cb7b2604829826f552
-- backend     Django 5.2.17, django.db.backends.mysql (MySQL 8 / MariaDB)
-- generated   gen-inventree-mysql-schema.py   (provenance: INVENTREE-MYSQL-SCHEMA.md)
--
-- InvenTree declares no MySQL schema of its own.  Django's ORM builds one from the
-- model classes in src/backend/InvenTree/<app>/models.py; this file is that layout
-- rendered as ordinary MySQL 8.  It is a reference artefact: the only correct way to
-- create InvenTree's database is InvenTree's own `inventree migrate`.
--
-- Conventions
--   * identifiers are back-quoted (MySQL reserved words: key, status, default, ...)
--   * int = 32-bit (IntegerField / AutoField / ForeignKey to an int PK)
--   * bigint = BigIntegerField / BigAutoField
--   * FK columns are an ordinary column + KEY + a trailing comment naming the target;
--     MySQL has no FK declaration, so the equivalent ALTER TABLE lines are grouped at
--     the foot of the file, commented out
--   * longtext / json columns carry no DEFAULT (MySQL cannot default those types)
--   * column order is mixin-first-then-own; Django orders by a global registration
--     counter, so order here is indicative, not byte-exact
--   * tables owned by Django / third-party apps (auth.*, sessions, admin, taggit,
--     django-q2, allauth, ...) are named where an FK points at them, not defined here


-- ==================================================================
-- app build | model Build | table `build_build`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `build_build` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `reference_int` bigint NOT NULL DEFAULT 0,
  `metadata` json NULL,
  `reference` varchar(64) NOT NULL,
  `title` varchar(100) NOT NULL,
  `parent` int NULL  /* FK -> build_build.id */,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `sales_order` int NULL  /* FK -> order_salesorder.id */,
  `take_from` int NULL  /* FK -> stock_stocklocation.id */,
  `external` bool NOT NULL DEFAULT 0,
  `destination` int NULL  /* FK -> stock_stocklocation.id */,
  `quantity` int NOT NULL DEFAULT 1,
  `completed` int NOT NULL DEFAULT 0,
  `status` int NOT NULL,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `batch` varchar(100) NULL,
  `creation_date` date NOT NULL  /* auto_now_add */,
  `start_date` date NULL,
  `target_date` date NULL,
  `completion_date` date NULL,
  `completed_by` int NULL  /* FK -> auth_user.id */,
  `issued_by` int NULL  /* FK -> auth_user.id */,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `link` varchar(2000) NOT NULL,
  `priority` int NOT NULL DEFAULT 0,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_build_build_reference` (`reference`),
  KEY `fk_build_build_parent` (`parent`)  /* -> build_build.id */,
  KEY `fk_build_build_part` (`part`)  /* -> part_part.id */,
  KEY `fk_build_build_sales_order` (`sales_order`)  /* -> order_salesorder.id */,
  KEY `fk_build_build_take_from` (`take_from`)  /* -> stock_stocklocation.id */,
  KEY `fk_build_build_destination` (`destination`)  /* -> stock_stocklocation.id */,
  KEY `fk_build_build_completed_by` (`completed_by`)  /* -> auth_user.id */,
  KEY `fk_build_build_issued_by` (`issued_by`)  /* -> auth_user.id */,
  KEY `fk_build_build_responsible` (`responsible`)  /* -> users_owner.id */,
  KEY `fk_build_build_project_code` (`project_code`)  /* -> common_projectcode.id */
);

-- ==================================================================
-- app build | model BuildItem | table `build_builditem`
-- ==================================================================
CREATE TABLE `build_builditem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `build_line` int NULL  /* FK -> build_buildline.id */,
  `stock_item` int NOT NULL  /* FK -> stock_stockitem.id */,
  `quantity` decimal(15,5) NOT NULL,
  `install_into` int NULL  /* FK -> stock_stockitem.id */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_build_builditem_build_line_stock_item_install_into` (`build_line`, `stock_item`, `install_into`),
  KEY `fk_build_builditem_build_line` (`build_line`)  /* -> build_buildline.id */,
  KEY `fk_build_builditem_stock_item` (`stock_item`)  /* -> stock_stockitem.id */,
  KEY `fk_build_builditem_install_into` (`install_into`)  /* -> stock_stockitem.id */
);

-- ==================================================================
-- app build | model BuildLine | table `build_buildline`
-- ==================================================================
CREATE TABLE `build_buildline` (
  `id` int NOT NULL AUTO_INCREMENT,
  `build` int NOT NULL  /* FK -> build_build.id */,
  `bom_item` int NOT NULL  /* FK -> part_bomitem.id */,
  `quantity` decimal(15,5) NOT NULL,
  `consumed` decimal(15,5) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_build_buildline_build_bom_item` (`build`, `bom_item`),
  KEY `fk_build_buildline_build` (`build`)  /* -> build_build.id */,
  KEY `fk_build_buildline_bom_item` (`bom_item`)  /* -> part_bomitem.id */
);

-- ==================================================================
-- app common | model Attachment | table `common_attachment`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `common_attachment` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `model_type` varchar(100) NOT NULL,
  `model_id` int NOT NULL,
  `attachment` varchar(100) NULL,
  `thumbnail` varchar(100) NULL,
  `link` varchar(2000) NULL,
  `comment` varchar(250) NOT NULL,
  `upload_user` int NULL  /* FK -> auth_user.id */,
  `upload_date` date NULL  /* auto_now_add */,
  `is_image` bool NOT NULL DEFAULT 0,
  `file_size` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_common_attachment_upload_user` (`upload_user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app common | model BarcodeScanResult | table `common_barcodescanresult`
-- ==================================================================
CREATE TABLE `common_barcodescanresult` (
  `id` int NOT NULL AUTO_INCREMENT,
  `data` varchar(255) NOT NULL,
  `user` int NULL  /* FK -> auth_user.id */,
  `timestamp` datetime NOT NULL  /* auto_now_add */,
  `endpoint` varchar(250) NULL,
  `context` json NULL,
  `response` json NULL,
  `result` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_common_barcodescanresult_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app common | model CustomUnit | table `common_customunit`
-- ==================================================================
CREATE TABLE `common_customunit` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  `symbol` varchar(10) NOT NULL,
  `definition` varchar(50) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_customunit_name` (`name`)
);

-- ==================================================================
-- app common | model DataOutput | table `common_dataoutput`
-- ==================================================================
CREATE TABLE `common_dataoutput` (
  `id` int NOT NULL AUTO_INCREMENT,
  `created` date NOT NULL  /* auto_now_add */,
  `user` int NULL  /* FK -> auth_user.id */,
  `total` int NOT NULL DEFAULT 1,
  `progress` int NOT NULL DEFAULT 0,
  `complete` bool NOT NULL DEFAULT 0,
  `output_type` varchar(100) NULL,
  `template_name` varchar(100) NULL,
  `plugin` varchar(100) NULL,
  `output` varchar(100) NULL,
  `errors` json NULL,
  PRIMARY KEY (`id`),
  KEY `fk_common_dataoutput_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app common | model EmailMessage | table `common_emailmessage`
-- ==================================================================
CREATE TABLE `common_emailmessage` (
  `global_id` char(32) NOT NULL,
  `message_id_key` varchar(250) NULL,
  `thread_id_key` varchar(250) NULL,
  `thread` int NULL  /* FK -> common_emailthread.global_id */,
  `subject` varchar(250) NOT NULL,
  `body` longtext NOT NULL,
  `to` varchar(254) NOT NULL,
  `sender` varchar(254) NOT NULL,
  `status` varchar(50) NULL,
  `timestamp` datetime NOT NULL  /* auto_now_add */,
  `headers` json NULL,
  `full_message` longtext NULL,
  `direction` varchar(50) NULL,
  `priority` int NOT NULL,
  `delivery_options` json NULL,
  `error_code` varchar(50) NULL,
  `error_message` longtext NULL,
  `error_timestamp` datetime NULL,
  PRIMARY KEY (`global_id`),
  UNIQUE KEY `u_common_emailmessage_global_id` (`global_id`),
  KEY `fk_common_emailmessage_thread` (`thread`)  /* -> common_emailthread.global_id */
);

-- ==================================================================
-- app common | model EmailThread | table `common_emailthread`
-- ==================================================================
CREATE TABLE `common_emailthread` (
  `metadata` json NULL,
  `key` varchar(250) NULL,
  `global_id` char(32) NOT NULL,
  `started_internal` bool NOT NULL DEFAULT 0,
  `created` datetime NOT NULL  /* auto_now_add */,
  `updated` datetime NOT NULL  /* auto_now */,
  PRIMARY KEY (`global_id`)
);

-- ==================================================================
-- app common | model InvenTreeCustomUserStateModel | table `common_inventreecustomuserstatemodel`
-- ==================================================================
CREATE TABLE `common_inventreecustomuserstatemodel` (
  `id` int NOT NULL AUTO_INCREMENT,
  `reference_status` varchar(250) NOT NULL,
  `logical_key` int NOT NULL,
  `key` int NOT NULL,
  `name` varchar(250) NOT NULL,
  `label` varchar(250) NOT NULL,
  `color` varchar(10) NOT NULL,
  `model` int NULL  /* FK -> contenttypes_contenttype.id */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_inventreecustomuserstatemodel_reference_status_key` (`reference_status`, `key`),
  UNIQUE KEY `u_common_inventreecustomuserstatemodel_reference_status_name` (`reference_status`, `name`),
  KEY `fk_common_inventreecustomuserstatemodel_model` (`model`)  /* -> contenttypes_contenttype.id */
);

-- ==================================================================
-- app common | model InvenTreeSetting | table `common_inventreesetting`
-- ==================================================================
CREATE TABLE `common_inventreesetting` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(50) NOT NULL,
  `value` varchar(2000) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_inventreesetting_key` (`key`)
);

-- ==================================================================
-- app common | model InvenTreeUserSetting | table `common_inventreeusersetting`
-- ==================================================================
CREATE TABLE `common_inventreeusersetting` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(50) NOT NULL,
  `value` varchar(2000) NOT NULL,
  `user` int NULL  /* FK -> auth_user.id */,
  PRIMARY KEY (`id`),
  KEY `fk_common_inventreeusersetting_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app common | model NewsFeedEntry | table `common_newsfeedentry`
-- ==================================================================
CREATE TABLE `common_newsfeedentry` (
  `id` int NOT NULL AUTO_INCREMENT,
  `feed_id` varchar(250) NOT NULL,
  `title` varchar(250) NOT NULL,
  `link` varchar(200) NOT NULL,
  `published` datetime NOT NULL,
  `author` varchar(250) NOT NULL,
  `summary` varchar(250) NOT NULL,
  `read` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_newsfeedentry_feed_id` (`feed_id`)
);

-- ==================================================================
-- app common | model Note | table `common_note`
-- ==================================================================
CREATE TABLE `common_note` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL,
  `updated_by` int NULL  /* FK -> auth_user.id */,
  `metadata` json NULL,
  `template` bool NOT NULL DEFAULT 0,
  `model_type` int NULL  /* FK -> contenttypes_contenttype.id */,
  `model_id` int NULL,
  `primary` bool NOT NULL DEFAULT 0,
  `title` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  `content` longtext NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_common_note_updated_by` (`updated_by`)  /* -> auth_user.id */,
  KEY `fk_common_note_model_type` (`model_type`)  /* -> contenttypes_contenttype.id */
);

-- ==================================================================
-- app common | model NotesImage | table `common_notesimage`
-- ==================================================================
CREATE TABLE `common_notesimage` (
  `id` int NOT NULL AUTO_INCREMENT,
  `image` varchar(100) NOT NULL,
  `user` int NULL  /* FK -> auth_user.id */,
  `date` datetime NOT NULL  /* auto_now_add */,
  `note` int NOT NULL  /* FK -> common_note.id */,
  PRIMARY KEY (`id`),
  KEY `fk_common_notesimage_user` (`user`)  /* -> auth_user.id */,
  KEY `fk_common_notesimage_note` (`note`)  /* -> common_note.id */
);

-- ==================================================================
-- app common | model NotificationEntry | table `common_notificationentry`
-- ==================================================================
CREATE TABLE `common_notificationentry` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL  /* auto_now */,
  `key` varchar(250) NOT NULL,
  `uid` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_notificationentry_key_uid` (`key`, `uid`)
);

-- ==================================================================
-- app common | model NotificationMessage | table `common_notificationmessage`
-- ==================================================================
CREATE TABLE `common_notificationmessage` (
  `id` int NOT NULL AUTO_INCREMENT,
  `target_content_type` int NOT NULL  /* FK -> contenttypes_contenttype.id */,
  `target_object_id` varchar(255) NOT NULL,
  `source_content_type` int NULL  /* FK -> contenttypes_contenttype.id */,
  `source_object_id` varchar(255) NULL,
  `user` int NULL  /* FK -> auth_user.id */,
  `category` varchar(250) NOT NULL,
  `name` varchar(250) NOT NULL,
  `message` varchar(250) NULL,
  `link` varchar(200) NULL,
  `creation` datetime NOT NULL  /* auto_now_add */,
  `read` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_common_notificationmessage_target_content_type` (`target_content_type`)  /* -> contenttypes_contenttype.id */,
  KEY `fk_common_notificationmessage_source_content_type` (`source_content_type`)  /* -> contenttypes_contenttype.id */,
  KEY `fk_common_notificationmessage_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app common | model Parameter | table `part_partparameter`
-- ==================================================================
CREATE TABLE `part_partparameter` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL,
  `updated_by` int NULL  /* FK -> auth_user.id */,
  `metadata` json NULL,
  `model_type` int NOT NULL  /* FK -> contenttypes_contenttype.id */,
  `model_id` int NOT NULL,
  `template` int NOT NULL  /* FK -> part_partparametertemplate.id */,
  `data` varchar(500) NOT NULL,
  `data_numeric` double NULL,
  `note` varchar(500) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_part_partparameter_updated_by` (`updated_by`)  /* -> auth_user.id */,
  KEY `fk_part_partparameter_model_type` (`model_type`)  /* -> contenttypes_contenttype.id */,
  KEY `fk_part_partparameter_template` (`template`)  /* -> part_partparametertemplate.id */
);

-- ==================================================================
-- app common | model ParameterTemplate | table `part_partparametertemplate`
-- ==================================================================
CREATE TABLE `part_partparametertemplate` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `model_type` int NULL  /* FK -> contenttypes_contenttype.id */,
  `name` varchar(100) NOT NULL,
  `units` varchar(25) NOT NULL,
  `description` varchar(250) NOT NULL,
  `checkbox` bool NOT NULL DEFAULT 0,
  `choices` varchar(5000) NOT NULL,
  `selectionlist` int NULL  /* FK -> common_selectionlist.id */,
  `enabled` bool NOT NULL DEFAULT 1,
  `unique` int NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_part_partparametertemplate_name` (`name`),
  KEY `fk_part_partparametertemplate_model_type` (`model_type`)  /* -> contenttypes_contenttype.id */,
  KEY `fk_part_partparametertemplate_selectionlist` (`selectionlist`)  /* -> common_selectionlist.id */
);

-- ==================================================================
-- app common | model ProjectCode | table `common_projectcode`
-- ==================================================================
CREATE TABLE `common_projectcode` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `code` varchar(50) NOT NULL,
  `description` varchar(200) NOT NULL,
  `active` bool NOT NULL DEFAULT 1,
  `responsible` int NULL  /* FK -> users_owner.id */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_projectcode_code` (`code`),
  KEY `fk_common_projectcode_responsible` (`responsible`)  /* -> users_owner.id */
);

-- ==================================================================
-- app common | model SelectionList | table `common_selectionlist`
-- ==================================================================
CREATE TABLE `common_selectionlist` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  `locked` bool NOT NULL DEFAULT 0,
  `active` bool NOT NULL DEFAULT 1,
  `source_plugin` int NULL  /* FK -> plugin_pluginconfig.id */,
  `source_string` varchar(1000) NOT NULL,
  `default` int NULL  /* FK -> common_selectionlistentry.id */,
  `created` datetime NOT NULL  /* auto_now_add */,
  `last_updated` datetime NOT NULL  /* auto_now */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_common_selectionlist_name` (`name`),
  KEY `fk_common_selectionlist_source_plugin` (`source_plugin`)  /* -> plugin_pluginconfig.id */,
  KEY `fk_common_selectionlist_default` (`default`)  /* -> common_selectionlistentry.id */
);

-- ==================================================================
-- app common | model SelectionListEntry | table `common_selectionlistentry`
-- ==================================================================
CREATE TABLE `common_selectionlistentry` (
  `id` int NOT NULL AUTO_INCREMENT,
  `list` int NULL  /* FK -> common_selectionlist.id */,
  `value` varchar(255) NOT NULL,
  `label` varchar(255) NOT NULL,
  `description` varchar(250) NOT NULL,
  `active` bool NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `fk_common_selectionlistentry_list` (`list`)  /* -> common_selectionlist.id */
);

-- ==================================================================
-- app common | model WebhookEndpoint | table `common_webhookendpoint`
-- ==================================================================
CREATE TABLE `common_webhookendpoint` (
  `id` int NOT NULL AUTO_INCREMENT,
  `endpoint_id` varchar(255) NOT NULL,
  `name` varchar(255) NULL,
  `active` bool NOT NULL DEFAULT 1,
  `user` int NULL  /* FK -> auth_user.id */,
  `token` varchar(255) NULL,
  `secret` varchar(255) NULL,
  PRIMARY KEY (`id`),
  KEY `fk_common_webhookendpoint_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app common | model WebhookMessage | table `common_webhookmessage`
-- ==================================================================
CREATE TABLE `common_webhookmessage` (
  `message_id` char(32) NOT NULL,
  `host` varchar(255) NOT NULL,
  `header` varchar(255) NULL,
  `body` json NULL,
  `endpoint` int NULL  /* FK -> common_webhookendpoint.id */,
  `worked_on` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`message_id`),
  KEY `fk_common_webhookmessage_endpoint` (`endpoint`)  /* -> common_webhookendpoint.id */
);

-- ==================================================================
-- app company | model Address | table `company_address`
-- ==================================================================
CREATE TABLE `company_address` (
  `id` int NOT NULL AUTO_INCREMENT,
  `company` int NOT NULL  /* FK -> company_company.id */,
  `title` varchar(100) NOT NULL,
  `primary` bool NOT NULL DEFAULT 0,
  `line1` varchar(50) NOT NULL,
  `line2` varchar(50) NOT NULL,
  `postal_code` varchar(10) NOT NULL,
  `postal_city` varchar(50) NOT NULL,
  `province` varchar(50) NOT NULL,
  `country` varchar(50) NOT NULL,
  `shipping_notes` varchar(100) NOT NULL,
  `internal_shipping_notes` varchar(100) NOT NULL,
  `link` varchar(2000) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_company_address_company` (`company`)  /* -> company_company.id */
);

-- ==================================================================
-- app company | model Company | table `company_company`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `company_company` (
  `id` int NOT NULL AUTO_INCREMENT,
  `image` varchar(100) NULL,
  `image_width` int NULL,
  `image_height` int NULL,
  `image_custom_data` json NULL,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(500) NOT NULL,
  `website` varchar(2000) NOT NULL,
  `phone` varchar(50) NOT NULL,
  `email` varchar(254) NULL,
  `contact` varchar(100) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `active` bool NOT NULL DEFAULT 1,
  `is_customer` bool NOT NULL DEFAULT 0,
  `is_supplier` bool NOT NULL DEFAULT 1,
  `is_manufacturer` bool NOT NULL DEFAULT 0,
  `currency` varchar(3) NOT NULL,
  `tax_id` varchar(50) NOT NULL,
  PRIMARY KEY (`id`)
);

-- ==================================================================
-- app company | model Contact | table `company_contact`
-- ==================================================================
CREATE TABLE `company_contact` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `company` int NOT NULL  /* FK -> company_company.id */,
  `name` varchar(100) NOT NULL,
  `phone` varchar(100) NOT NULL,
  `email` varchar(254) NOT NULL,
  `role` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_company_contact_company` (`company`)  /* -> company_company.id */
);

-- ==================================================================
-- app company | model ManufacturerPart | table `company_manufacturerpart`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `company_manufacturerpart` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `metadata` json NULL,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `manufacturer` int NULL  /* FK -> company_company.id */,
  `MPN` varchar(100) NULL,
  `link` varchar(2000) NULL,
  `description` varchar(250) NULL,
  PRIMARY KEY (`id`),
  KEY `fk_company_manufacturerpart_part` (`part`)  /* -> part_part.id */,
  KEY `fk_company_manufacturerpart_manufacturer` (`manufacturer`)  /* -> company_company.id */
);

-- ==================================================================
-- app company | model SupplierPart | table `part_supplierpart`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `part_supplierpart` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `updated` datetime NULL  /* auto_now */,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `supplier` int NOT NULL  /* FK -> company_company.id */,
  `SKU` varchar(100) NOT NULL,
  `active` bool NOT NULL DEFAULT 1,
  `primary` bool NOT NULL DEFAULT 0,
  `manufacturer_part` int NULL  /* FK -> company_manufacturerpart.id */,
  `link` varchar(2000) NULL,
  `description` varchar(250) NULL,
  `note` varchar(100) NULL,
  `base_cost` decimal(10,3) NOT NULL,
  `packaging` varchar(50) NULL,
  `pack_quantity` varchar(25) NOT NULL,
  `pack_quantity_native` decimal(20,10) NULL,
  `multiple` int NOT NULL DEFAULT 1,
  `available` decimal(10,3) NOT NULL,
  `availability_updated` datetime NULL,
  PRIMARY KEY (`id`),
  KEY `fk_part_supplierpart_part` (`part`)  /* -> part_part.id */,
  KEY `fk_part_supplierpart_supplier` (`supplier`)  /* -> company_company.id */,
  KEY `fk_part_supplierpart_manufacturer_part` (`manufacturer_part`)  /* -> company_manufacturerpart.id */
);

-- ==================================================================
-- app company | model SupplierPriceBreak | table `part_supplierpricebreak`
-- ==================================================================
CREATE TABLE `part_supplierpricebreak` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL  /* auto_now */,
  `quantity` decimal(15,5) NOT NULL,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  `part` int NOT NULL  /* FK -> part_supplierpart.id */,
  PRIMARY KEY (`id`),
  KEY `fk_part_supplierpricebreak_part` (`part`)  /* -> part_supplierpart.id */
);

-- ==================================================================
-- app importer | model DataImportColumnMap | table `importer_dataimportcolumnmap`
-- ==================================================================
CREATE TABLE `importer_dataimportcolumnmap` (
  `id` int NOT NULL AUTO_INCREMENT,
  `session` int NOT NULL  /* FK -> importer_dataimportsession.id */,
  `field` varchar(100) NOT NULL,
  `column` varchar(100) NOT NULL,
  `lookup_field` varchar(100) NULL,
  PRIMARY KEY (`id`),
  KEY `fk_importer_dataimportcolumnmap_session` (`session`)  /* -> importer_dataimportsession.id */
);

-- ==================================================================
-- app importer | model DataImportRow | table `importer_dataimportrow`
-- ==================================================================
CREATE TABLE `importer_dataimportrow` (
  `id` int NOT NULL AUTO_INCREMENT,
  `session` int NOT NULL  /* FK -> importer_dataimportsession.id */,
  `row_index` int NOT NULL DEFAULT 0,
  `row_data` json NULL,
  `data` json NULL,
  `errors` json NULL,
  `valid` bool NOT NULL DEFAULT 0,
  `complete` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_importer_dataimportrow_session` (`session`)  /* -> importer_dataimportsession.id */
);

-- ==================================================================
-- app importer | model DataImportSession | table `importer_dataimportsession`
-- ==================================================================
CREATE TABLE `importer_dataimportsession` (
  `id` int NOT NULL AUTO_INCREMENT,
  `timestamp` datetime NOT NULL  /* auto_now_add */,
  `data_file` varchar(100) NOT NULL,
  `columns` json NULL,
  `model_type` varchar(100) NOT NULL,
  `status` int NOT NULL,
  `user` int NULL  /* FK -> auth_user.id */,
  `field_defaults` json NULL,
  `field_overrides` json NULL,
  `field_filters` json NULL,
  `update_records` bool NOT NULL DEFAULT 0,
  `completed_row_count_history` int NULL,
  `row_count_history` int NULL,
  PRIMARY KEY (`id`),
  KEY `fk_importer_dataimportsession_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app machine | model MachineConfig | table `machine_machineconfig`
-- ==================================================================
CREATE TABLE `machine_machineconfig` (
  `id` char(32) NOT NULL,
  `name` varchar(255) NOT NULL,
  `machine_type` varchar(255) NOT NULL,
  `driver` varchar(255) NOT NULL,
  `active` bool NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_machine_machineconfig_name` (`name`)
);

-- ==================================================================
-- app machine | model MachineSetting | table `machine_machinesetting`
-- ==================================================================
CREATE TABLE `machine_machinesetting` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(50) NOT NULL,
  `value` varchar(2000) NOT NULL,
  `machine_config` int NOT NULL  /* FK -> machine_machineconfig.id */,
  `config_type` varchar(1) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_machine_machinesetting_machine_config_config_type_key` (`machine_config`, `config_type`, `key`),
  KEY `fk_machine_machinesetting_machine_config` (`machine_config`)  /* -> machine_machineconfig.id */
);

-- ==================================================================
-- app order | model PurchaseOrder | table `order_purchaseorder`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `order_purchaseorder` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `metadata` json NULL,
  `reference_int` bigint NOT NULL DEFAULT 0,
  `description` varchar(250) NOT NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `link` varchar(2000) NOT NULL,
  `start_date` date NULL,
  `target_date` date NULL,
  `creation_date` date NULL,
  `created_by` int NULL  /* FK -> auth_user.id */,
  `issue_date` date NULL,
  `updated_at` datetime NULL,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `contact` int NULL  /* FK -> company_contact.id */,
  `address` int NULL  /* FK -> company_address.id */,
  `reference` varchar(64) NOT NULL,
  `status` int NOT NULL,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `supplier` int NULL  /* FK -> company_company.id */,
  `supplier_reference` varchar(64) NOT NULL,
  `received_by` int NULL  /* FK -> auth_user.id */,
  `complete_date` date NULL,
  `destination` int NULL  /* FK -> stock_stocklocation.id */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_order_purchaseorder_reference` (`reference`),
  KEY `fk_order_purchaseorder_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_purchaseorder_created_by` (`created_by`)  /* -> auth_user.id */,
  KEY `fk_order_purchaseorder_responsible` (`responsible`)  /* -> users_owner.id */,
  KEY `fk_order_purchaseorder_contact` (`contact`)  /* -> company_contact.id */,
  KEY `fk_order_purchaseorder_address` (`address`)  /* -> company_address.id */,
  KEY `fk_order_purchaseorder_supplier` (`supplier`)  /* -> company_company.id */,
  KEY `fk_order_purchaseorder_received_by` (`received_by`)  /* -> auth_user.id */,
  KEY `fk_order_purchaseorder_destination` (`destination`)  /* -> stock_stocklocation.id */
);

-- ==================================================================
-- app order | model PurchaseOrderExtraLine | table `order_purchaseorderextraline`
-- ==================================================================
CREATE TABLE `order_purchaseorderextraline` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL,
  `discount` decimal(5,2) NOT NULL,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL,
  `notes` varchar(500) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `description` varchar(250) NOT NULL,
  `context` json NULL,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  `order` int NOT NULL  /* FK -> order_purchaseorder.id */,
  PRIMARY KEY (`id`),
  KEY `fk_order_purchaseorderextraline_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_purchaseorderextraline_order` (`order`)  /* -> order_purchaseorder.id */
);

-- ==================================================================
-- app order | model PurchaseOrderLineItem | table `order_purchaseorderlineitem`
-- ==================================================================
CREATE TABLE `order_purchaseorderlineitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL,
  `discount` decimal(5,2) NOT NULL,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL,
  `notes` varchar(500) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `order` int NOT NULL  /* FK -> order_purchaseorder.id */,
  `part` int NULL  /* FK -> part_supplierpart.id */,
  `received` decimal(15,5) NOT NULL,
  `purchase_price` decimal(19,6) NULL,
  `purchase_price_currency` char(3) NULL,
  `build_order` int NULL  /* FK -> build_build.id */,
  `destination` int NULL  /* FK -> stock_stocklocation.id */,
  PRIMARY KEY (`id`),
  KEY `fk_order_purchaseorderlineitem_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_purchaseorderlineitem_order` (`order`)  /* -> order_purchaseorder.id */,
  KEY `fk_order_purchaseorderlineitem_part` (`part`)  /* -> part_supplierpart.id */,
  KEY `fk_order_purchaseorderlineitem_build_order` (`build_order`)  /* -> build_build.id */,
  KEY `fk_order_purchaseorderlineitem_destination` (`destination`)  /* -> stock_stocklocation.id */
);

-- ==================================================================
-- app order | model ReturnOrder | table `order_returnorder`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `order_returnorder` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `metadata` json NULL,
  `reference_int` bigint NOT NULL DEFAULT 0,
  `description` varchar(250) NOT NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `link` varchar(2000) NOT NULL,
  `start_date` date NULL,
  `target_date` date NULL,
  `creation_date` date NULL,
  `created_by` int NULL  /* FK -> auth_user.id */,
  `issue_date` date NULL,
  `updated_at` datetime NULL,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `contact` int NULL  /* FK -> company_contact.id */,
  `address` int NULL  /* FK -> company_address.id */,
  `reference` varchar(64) NOT NULL,
  `customer` int NULL  /* FK -> company_company.id */,
  `status` int NOT NULL,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `customer_reference` varchar(64) NOT NULL,
  `complete_date` date NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_order_returnorder_reference` (`reference`),
  KEY `fk_order_returnorder_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_returnorder_created_by` (`created_by`)  /* -> auth_user.id */,
  KEY `fk_order_returnorder_responsible` (`responsible`)  /* -> users_owner.id */,
  KEY `fk_order_returnorder_contact` (`contact`)  /* -> company_contact.id */,
  KEY `fk_order_returnorder_address` (`address`)  /* -> company_address.id */,
  KEY `fk_order_returnorder_customer` (`customer`)  /* -> company_company.id */
);

-- ==================================================================
-- app order | model ReturnOrderExtraLine | table `order_returnorderextraline`
-- ==================================================================
CREATE TABLE `order_returnorderextraline` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL,
  `discount` decimal(5,2) NOT NULL,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL,
  `notes` varchar(500) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `description` varchar(250) NOT NULL,
  `context` json NULL,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  `order` int NOT NULL  /* FK -> order_returnorder.id */,
  PRIMARY KEY (`id`),
  KEY `fk_order_returnorderextraline_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_returnorderextraline_order` (`order`)  /* -> order_returnorder.id */
);

-- ==================================================================
-- app order | model ReturnOrderLineItem | table `order_returnorderlineitem`
-- ==================================================================
CREATE TABLE `order_returnorderlineitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL,
  `discount` decimal(5,2) NOT NULL,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL,
  `notes` varchar(500) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `order` int NOT NULL  /* FK -> order_returnorder.id */,
  `item` int NOT NULL  /* FK -> stock_stockitem.id */,
  `received_date` date NULL,
  `outcome` int NOT NULL,
  `outcome_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_order_returnorderlineitem_order_item` (`order`, `item`),
  KEY `fk_order_returnorderlineitem_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_returnorderlineitem_order` (`order`)  /* -> order_returnorder.id */,
  KEY `fk_order_returnorderlineitem_item` (`item`)  /* -> stock_stockitem.id */
);

-- ==================================================================
-- app order | model SalesOrder | table `order_salesorder`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `order_salesorder` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `metadata` json NULL,
  `reference_int` bigint NOT NULL DEFAULT 0,
  `description` varchar(250) NOT NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `link` varchar(2000) NOT NULL,
  `start_date` date NULL,
  `target_date` date NULL,
  `creation_date` date NULL,
  `created_by` int NULL  /* FK -> auth_user.id */,
  `issue_date` date NULL,
  `updated_at` datetime NULL,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `contact` int NULL  /* FK -> company_contact.id */,
  `address` int NULL  /* FK -> company_address.id */,
  `reference` varchar(64) NOT NULL,
  `customer` int NULL  /* FK -> company_company.id */,
  `status` int NOT NULL,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `customer_reference` varchar(64) NOT NULL,
  `shipment_date` date NULL,
  `shipped_by` int NULL  /* FK -> auth_user.id */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_order_salesorder_reference` (`reference`),
  KEY `fk_order_salesorder_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_salesorder_created_by` (`created_by`)  /* -> auth_user.id */,
  KEY `fk_order_salesorder_responsible` (`responsible`)  /* -> users_owner.id */,
  KEY `fk_order_salesorder_contact` (`contact`)  /* -> company_contact.id */,
  KEY `fk_order_salesorder_address` (`address`)  /* -> company_address.id */,
  KEY `fk_order_salesorder_customer` (`customer`)  /* -> company_company.id */,
  KEY `fk_order_salesorder_shipped_by` (`shipped_by`)  /* -> auth_user.id */
);

-- ==================================================================
-- app order | model SalesOrderAllocation | table `order_salesorderallocation`
-- ==================================================================
CREATE TABLE `order_salesorderallocation` (
  `id` int NOT NULL AUTO_INCREMENT,
  `line` int NOT NULL  /* FK -> order_salesorderlineitem.id */,
  `shipment` int NULL  /* FK -> order_salesordershipment.id */,
  `item` int NOT NULL  /* FK -> stock_stockitem.id */,
  `quantity` decimal(15,5) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_order_salesorderallocation_line` (`line`)  /* -> order_salesorderlineitem.id */,
  KEY `fk_order_salesorderallocation_shipment` (`shipment`)  /* -> order_salesordershipment.id */,
  KEY `fk_order_salesorderallocation_item` (`item`)  /* -> stock_stockitem.id */
);

-- ==================================================================
-- app order | model SalesOrderExtraLine | table `order_salesorderextraline`
-- ==================================================================
CREATE TABLE `order_salesorderextraline` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL,
  `discount` decimal(5,2) NOT NULL,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL,
  `notes` varchar(500) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `description` varchar(250) NOT NULL,
  `context` json NULL,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  `order` int NOT NULL  /* FK -> order_salesorder.id */,
  PRIMARY KEY (`id`),
  KEY `fk_order_salesorderextraline_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_salesorderextraline_order` (`order`)  /* -> order_salesorder.id */
);

-- ==================================================================
-- app order | model SalesOrderLineItem | table `order_salesorderlineitem`
-- ==================================================================
CREATE TABLE `order_salesorderlineitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL,
  `discount` decimal(5,2) NOT NULL,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL,
  `notes` varchar(500) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `order` int NOT NULL  /* FK -> order_salesorder.id */,
  `part` int NULL  /* FK -> part_part.id */,
  `sale_price` decimal(19,6) NULL,
  `sale_price_currency` char(3) NULL,
  `shipped` decimal(15,5) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_order_salesorderlineitem_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_salesorderlineitem_order` (`order`)  /* -> order_salesorder.id */,
  KEY `fk_order_salesorderlineitem_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app order | model SalesOrderShipment | table `order_salesordershipment`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `order_salesordershipment` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `metadata` json NULL,
  `order` int NOT NULL  /* FK -> order_salesorder.id */,
  `shipment_address` int NULL  /* FK -> company_address.id */,
  `shipment_date` date NULL,
  `delivery_date` date NULL,
  `checked_by` int NULL  /* FK -> auth_user.id */,
  `reference` varchar(100) NOT NULL DEFAULT '1',
  `tracking_number` varchar(100) NOT NULL,
  `invoice_number` varchar(100) NOT NULL,
  `link` varchar(2000) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_order_salesordershipment_order` (`order`)  /* -> order_salesorder.id */,
  KEY `fk_order_salesordershipment_shipment_address` (`shipment_address`)  /* -> company_address.id */,
  KEY `fk_order_salesordershipment_checked_by` (`checked_by`)  /* -> auth_user.id */
);

-- ==================================================================
-- app order | model TransferOrder | table `order_transferorder`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `order_transferorder` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `metadata` json NULL,
  `reference_int` bigint NOT NULL DEFAULT 0,
  `description` varchar(250) NOT NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `link` varchar(2000) NOT NULL,
  `start_date` date NULL,
  `target_date` date NULL,
  `creation_date` date NULL,
  `created_by` int NULL  /* FK -> auth_user.id */,
  `issue_date` date NULL,
  `updated_at` datetime NULL,
  `responsible` int NULL  /* FK -> users_owner.id */,
  `contact` int NULL  /* FK -> company_contact.id */,
  `address` int NULL  /* FK -> company_address.id */,
  `reference` varchar(64) NOT NULL,
  `status` int NOT NULL,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `take_from` int NULL  /* FK -> stock_stocklocation.id */,
  `destination` int NULL  /* FK -> stock_stocklocation.id */,
  `consume` bool NOT NULL DEFAULT 0,
  `complete_date` date NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_order_transferorder_reference` (`reference`),
  KEY `fk_order_transferorder_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_transferorder_created_by` (`created_by`)  /* -> auth_user.id */,
  KEY `fk_order_transferorder_responsible` (`responsible`)  /* -> users_owner.id */,
  KEY `fk_order_transferorder_contact` (`contact`)  /* -> company_contact.id */,
  KEY `fk_order_transferorder_address` (`address`)  /* -> company_address.id */,
  KEY `fk_order_transferorder_take_from` (`take_from`)  /* -> stock_stocklocation.id */,
  KEY `fk_order_transferorder_destination` (`destination`)  /* -> stock_stocklocation.id */
);

-- ==================================================================
-- app order | model TransferOrderAllocation | table `order_transferorderallocation`
-- ==================================================================
CREATE TABLE `order_transferorderallocation` (
  `id` int NOT NULL AUTO_INCREMENT,
  `line` int NOT NULL  /* FK -> order_transferorderlineitem.id */,
  `item` int NOT NULL  /* FK -> stock_stockitem.id */,
  `quantity` decimal(15,5) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_order_transferorderallocation_line` (`line`)  /* -> order_transferorderlineitem.id */,
  KEY `fk_order_transferorderallocation_item` (`item`)  /* -> stock_stockitem.id */
);

-- ==================================================================
-- app order | model TransferOrderLineItem | table `order_transferorderlineitem`
-- ==================================================================
CREATE TABLE `order_transferorderlineitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `quantity` decimal(15,5) NOT NULL,
  `discount` decimal(5,2) NOT NULL,
  `line` varchar(20) NOT NULL DEFAULT '',
  `line_int` int NOT NULL DEFAULT 0,
  `reference` varchar(100) NOT NULL,
  `notes` varchar(500) NOT NULL,
  `link` varchar(2000) NOT NULL,
  `target_date` date NULL,
  `project_code` int NULL  /* FK -> common_projectcode.id */,
  `order` int NOT NULL  /* FK -> order_transferorder.id */,
  `part` int NULL  /* FK -> part_part.id */,
  `transferred` decimal(15,5) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_order_transferorderlineitem_project_code` (`project_code`)  /* -> common_projectcode.id */,
  KEY `fk_order_transferorderlineitem_order` (`order`)  /* -> order_transferorder.id */,
  KEY `fk_order_transferorderlineitem_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model BomItem | table `part_bomitem`
-- ==================================================================
CREATE TABLE `part_bomitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `sub_part` int NOT NULL  /* FK -> part_part.id */,
  `raw_amount` varchar(25) NOT NULL,
  `quantity` decimal(15,5) NOT NULL,
  `optional` bool NOT NULL DEFAULT 0,
  `consumable` bool NOT NULL DEFAULT 0,
  `setup_quantity` decimal(15,5) NOT NULL,
  `attrition` decimal(6,3) NOT NULL,
  `rounding_multiple` decimal(15,5) NULL,
  `piece_count` int NOT NULL DEFAULT 1,
  `reference` varchar(5000) NOT NULL,
  `note` varchar(500) NOT NULL,
  `checksum` varchar(128) NOT NULL,
  `validated` bool NOT NULL DEFAULT 0,
  `inherited` bool NOT NULL DEFAULT 0,
  `allow_variants` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_part_bomitem_part` (`part`)  /* -> part_part.id */,
  KEY `fk_part_bomitem_sub_part` (`sub_part`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model BomItemSubstitute | table `part_bomitemsubstitute`
-- ==================================================================
CREATE TABLE `part_bomitemsubstitute` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `bom_item` int NOT NULL  /* FK -> part_bomitem.id */,
  `part` int NOT NULL  /* FK -> part_part.id */,
  PRIMARY KEY (`id`),
  KEY `fk_part_bomitemsubstitute_bom_item` (`bom_item`)  /* -> part_bomitem.id */,
  KEY `fk_part_bomitemsubstitute_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model Part | table `part_part`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `part_part` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `image` varchar(100) NULL,
  `image_width` int NULL,
  `image_height` int NULL,
  `image_custom_data` json NULL,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL,
  `is_template` bool NOT NULL,
  `variant_of` int NULL  /* FK -> part_part.id */,
  `description` varchar(250) NOT NULL,
  `keywords` varchar(250) NULL,
  `category` int NULL  /* FK -> part_partcategory.id */,
  `IPN` varchar(100) NULL,
  `revision` varchar(100) NULL,
  `revision_of` int NULL  /* FK -> part_part.id */,
  `link` varchar(2000) NULL,
  `default_location` int NULL  /* FK -> stock_stocklocation.id */,
  `default_expiry` int NOT NULL DEFAULT 0,
  `minimum_stock` decimal(19,6) NOT NULL,
  `maximum_stock` decimal(19,6) NOT NULL,
  `units` varchar(20) NULL DEFAULT '',
  `assembly` bool NOT NULL,
  `component` bool NOT NULL,
  `trackable` bool NOT NULL,
  `testable` bool NOT NULL DEFAULT 0,
  `purchaseable` bool NOT NULL,
  `salable` bool NOT NULL,
  `active` bool NOT NULL DEFAULT 1,
  `locked` bool NOT NULL DEFAULT 0,
  `virtual` bool NOT NULL,
  `consumable` bool NOT NULL DEFAULT 0,
  `bom_validated` bool NOT NULL DEFAULT 0,
  `bom_checksum` varchar(128) NOT NULL,
  `bom_checked_by` int NULL  /* FK -> auth_user.id */,
  `bom_checked_date` date NULL,
  `creation_date` date NULL  /* auto_now_add */,
  `creation_user` int NULL  /* FK -> auth_user.id */,
  `responsible_owner` int NULL  /* FK -> users_owner.id */,
  `base_cost` decimal(19,6) NOT NULL,
  `multiple` int NOT NULL DEFAULT 1,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  PRIMARY KEY (`id`),
  KEY `fk_part_part_variant_of` (`variant_of`)  /* -> part_part.id */,
  KEY `fk_part_part_category` (`category`)  /* -> part_partcategory.id */,
  KEY `fk_part_part_revision_of` (`revision_of`)  /* -> part_part.id */,
  KEY `fk_part_part_default_location` (`default_location`)  /* -> stock_stocklocation.id */,
  KEY `fk_part_part_bom_checked_by` (`bom_checked_by`)  /* -> auth_user.id */,
  KEY `fk_part_part_creation_user` (`creation_user`)  /* -> auth_user.id */,
  KEY `fk_part_part_responsible_owner` (`responsible_owner`)  /* -> users_owner.id */
);

-- ==================================================================
-- app part | model PartCategory | table `part_partcategory`
-- ==================================================================
CREATE TABLE `part_partcategory` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  `parent` int NULL  /* FK -> part_partcategory.id */,
  `pathstring` varchar(250) NOT NULL,
  `default_location` int NULL  /* FK -> stock_stocklocation.id */,
  `structural` bool NOT NULL DEFAULT 0,
  `default_keywords` varchar(250) NULL,
  `icon` varchar(100) NULL,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  PRIMARY KEY (`id`),
  KEY `fk_part_partcategory_parent` (`parent`)  /* -> part_partcategory.id */,
  KEY `fk_part_partcategory_default_location` (`default_location`)  /* -> stock_stocklocation.id */
);

-- ==================================================================
-- app part | model PartCategoryParameterTemplate | table `part_partcategoryparametertemplate`
-- ==================================================================
CREATE TABLE `part_partcategoryparametertemplate` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `category` int NOT NULL  /* FK -> part_partcategory.id */,
  `template` int NOT NULL  /* FK -> part_partparametertemplate.id */,
  `default_value` varchar(500) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_part_partcategoryparametertemplate_category` (`category`)  /* -> part_partcategory.id */,
  KEY `fk_part_partcategoryparametertemplate_template` (`template`)  /* -> part_partparametertemplate.id */
);

-- ==================================================================
-- app part | model PartCategoryStar | table `part_partcategorystar`
-- ==================================================================
CREATE TABLE `part_partcategorystar` (
  `id` int NOT NULL AUTO_INCREMENT,
  `category` int NOT NULL  /* FK -> part_partcategory.id */,
  `user` int NOT NULL  /* FK -> auth_user.id */,
  PRIMARY KEY (`id`),
  KEY `fk_part_partcategorystar_category` (`category`)  /* -> part_partcategory.id */,
  KEY `fk_part_partcategorystar_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app part | model PartInternalPriceBreak | table `part_partinternalpricebreak`
-- ==================================================================
CREATE TABLE `part_partinternalpricebreak` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL  /* auto_now */,
  `quantity` decimal(15,5) NOT NULL,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  `part` int NOT NULL  /* FK -> part_part.id */,
  PRIMARY KEY (`id`),
  KEY `fk_part_partinternalpricebreak_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model PartPricing | table `part_partpricing`
-- ==================================================================
CREATE TABLE `part_partpricing` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL  /* auto_now */,
  `currency` varchar(10) NOT NULL,
  `scheduled_for_update` bool NOT NULL DEFAULT 0,
  `part` int NOT NULL  /* FK -> part_part.id */,
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
  PRIMARY KEY (`id`),
  KEY `fk_part_partpricing_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model PartRelated | table `part_partrelated`
-- ==================================================================
CREATE TABLE `part_partrelated` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `part_1` int NOT NULL  /* FK -> part_part.id */,
  `part_2` int NOT NULL  /* FK -> part_part.id */,
  `note` varchar(500) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_part_partrelated_part_1` (`part_1`)  /* -> part_part.id */,
  KEY `fk_part_partrelated_part_2` (`part_2`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model PartSellPriceBreak | table `part_partsellpricebreak`
-- ==================================================================
CREATE TABLE `part_partsellpricebreak` (
  `id` int NOT NULL AUTO_INCREMENT,
  `updated` datetime NULL  /* auto_now */,
  `quantity` decimal(15,5) NOT NULL,
  `price` decimal(19,6) NULL,
  `price_currency` char(3) NULL,
  `part` int NOT NULL  /* FK -> part_part.id */,
  PRIMARY KEY (`id`),
  KEY `fk_part_partsellpricebreak_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model PartStar | table `part_partstar`
-- ==================================================================
CREATE TABLE `part_partstar` (
  `id` int NOT NULL AUTO_INCREMENT,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `user` int NOT NULL  /* FK -> auth_user.id */,
  PRIMARY KEY (`id`),
  KEY `fk_part_partstar_part` (`part`)  /* -> part_part.id */,
  KEY `fk_part_partstar_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app part | model PartStocktake | table `part_partstocktake`
-- ==================================================================
CREATE TABLE `part_partstocktake` (
  `id` int NOT NULL AUTO_INCREMENT,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `item_count` int NOT NULL DEFAULT 1,
  `quantity` decimal(19,5) NOT NULL,
  `date` date NOT NULL  /* auto_now_add */,
  `cost_min` decimal(19,6) NULL,
  `cost_min_currency` char(3) NULL,
  `cost_max` decimal(19,6) NULL,
  `cost_max_currency` char(3) NULL,
  PRIMARY KEY (`id`),
  KEY `fk_part_partstocktake_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app part | model PartTestTemplate | table `part_parttesttemplate`
-- ==================================================================
CREATE TABLE `part_parttesttemplate` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `test_name` varchar(100) NOT NULL,
  `key` varchar(100) NOT NULL,
  `description` varchar(100) NULL,
  `enabled` bool NOT NULL DEFAULT 1,
  `required` bool NOT NULL DEFAULT 1,
  `requires_value` bool NOT NULL DEFAULT 0,
  `requires_attachment` bool NOT NULL DEFAULT 0,
  `choices` varchar(5000) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_part_parttesttemplate_part` (`part`)  /* -> part_part.id */
);

-- ==================================================================
-- app plugin | model PluginConfig | table `plugin_pluginconfig`
-- ==================================================================
CREATE TABLE `plugin_pluginconfig` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `key` varchar(255) NOT NULL,
  `name` varchar(255) NULL,
  `package_name` varchar(255) NULL,
  `active` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_plugin_pluginconfig_key` (`key`)
);

-- ==================================================================
-- app plugin | model PluginSetting | table `plugin_pluginsetting`
-- ==================================================================
CREATE TABLE `plugin_pluginsetting` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(50) NOT NULL,
  `value` varchar(2000) NOT NULL,
  `plugin` int NOT NULL  /* FK -> plugin_pluginconfig.id */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_plugin_pluginsetting_plugin_key` (`plugin`, `key`),
  KEY `fk_plugin_pluginsetting_plugin` (`plugin`)  /* -> plugin_pluginconfig.id */
);

-- ==================================================================
-- app plugin | model PluginUserSetting | table `plugin_pluginusersetting`
-- ==================================================================
CREATE TABLE `plugin_pluginusersetting` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(50) NOT NULL,
  `value` varchar(2000) NOT NULL,
  `plugin` int NOT NULL  /* FK -> plugin_pluginconfig.id */,
  `user` int NOT NULL  /* FK -> auth_user.id */,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_plugin_pluginusersetting_plugin_user_key` (`plugin`, `user`, `key`),
  KEY `fk_plugin_pluginusersetting_plugin` (`plugin`)  /* -> plugin_pluginconfig.id */,
  KEY `fk_plugin_pluginusersetting_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app report | model LabelTemplate | table `report_labeltemplate`
-- ==================================================================
CREATE TABLE `report_labeltemplate` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `updated` datetime NULL,
  `updated_by` int NULL  /* FK -> auth_user.id */,
  `name` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  `revision` int NOT NULL DEFAULT 1,
  `attach_to_model` bool NOT NULL DEFAULT 0,
  `filename_pattern` varchar(100) NOT NULL DEFAULT 'output.pdf',
  `enabled` bool NOT NULL DEFAULT 1,
  `model_type` varchar(100) NOT NULL,
  `filters` varchar(250) NOT NULL,
  `template` varchar(100) NOT NULL,
  `width` double NOT NULL,
  `height` double NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_report_labeltemplate_updated_by` (`updated_by`)  /* -> auth_user.id */
);

-- ==================================================================
-- app report | model ReportAsset | table `report_reportasset`
-- ==================================================================
CREATE TABLE `report_reportasset` (
  `id` int NOT NULL AUTO_INCREMENT,
  `asset` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  PRIMARY KEY (`id`)
);

-- ==================================================================
-- app report | model ReportSnippet | table `report_reportsnippet`
-- ==================================================================
CREATE TABLE `report_reportsnippet` (
  `id` int NOT NULL AUTO_INCREMENT,
  `snippet` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  PRIMARY KEY (`id`)
);

-- ==================================================================
-- app report | model ReportTemplate | table `report_reporttemplate`
-- ==================================================================
CREATE TABLE `report_reporttemplate` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `updated` datetime NULL,
  `updated_by` int NULL  /* FK -> auth_user.id */,
  `name` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  `revision` int NOT NULL DEFAULT 1,
  `attach_to_model` bool NOT NULL DEFAULT 0,
  `filename_pattern` varchar(100) NOT NULL DEFAULT 'output.pdf',
  `enabled` bool NOT NULL DEFAULT 1,
  `model_type` varchar(100) NOT NULL,
  `filters` varchar(250) NOT NULL,
  `template` varchar(100) NOT NULL,
  `page_size` varchar(20) NOT NULL,
  `landscape` bool NOT NULL DEFAULT 0,
  `merge` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_report_reporttemplate_updated_by` (`updated_by`)  /* -> auth_user.id */
);

-- ==================================================================
-- app scim | model ScimConfiguration | table `scim_scimconfiguration`
-- ==================================================================
CREATE TABLE `scim_scimconfiguration` (
  `id` int NOT NULL AUTO_INCREMENT,
  `enabled` bool NOT NULL DEFAULT 0,
  `secret_digest` varchar(64) NOT NULL,
  `secret_generated` datetime NULL,
  `last_used` datetime NULL,
  PRIMARY KEY (`id`)
);

-- ==================================================================
-- app stock | model StockItem | table `stock_stockitem`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `stock_stockitem` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `updated` datetime NULL  /* auto_now */,
  `metadata` json NULL,
  `parent` int NULL  /* FK -> stock_stockitem.id */,
  `part` int NOT NULL  /* FK -> part_part.id */,
  `supplier_part` int NULL  /* FK -> part_supplierpart.id */,
  `location` int NULL  /* FK -> stock_stocklocation.id */,
  `packaging` varchar(50) NULL,
  `belongs_to` int NULL  /* FK -> stock_stockitem.id */,
  `customer` int NULL  /* FK -> company_company.id */,
  `serial` varchar(100) NULL,
  `serial_int` int NOT NULL DEFAULT 0,
  `link` varchar(2000) NOT NULL,
  `batch` varchar(100) NULL,
  `quantity` decimal(15,5) NOT NULL,
  `build` int NULL  /* FK -> build_build.id */,
  `consumed_by` int NULL  /* FK -> build_build.id */,
  `is_building` bool NOT NULL DEFAULT 0,
  `purchase_order` int NULL  /* FK -> order_purchaseorder.id */,
  `sales_order` int NULL  /* FK -> order_salesorder.id */,
  `expiry_date` date NULL,
  `stocktake_date` date NULL,
  `stocktake_user` int NULL  /* FK -> auth_user.id */,
  `creation_date` datetime NULL  /* auto_now_add */,
  `delete_on_deplete` bool NOT NULL,
  `status` int NOT NULL,
  `status_custom_key` int NULL  /* added by InvenTreeCustomStatusModelField */,
  `purchase_price` decimal(19,6) NULL,
  `purchase_price_currency` char(3) NULL,
  `owner` int NULL  /* FK -> users_owner.id */,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stockitem_parent` (`parent`)  /* -> stock_stockitem.id */,
  KEY `fk_stock_stockitem_part` (`part`)  /* -> part_part.id */,
  KEY `fk_stock_stockitem_supplier_part` (`supplier_part`)  /* -> part_supplierpart.id */,
  KEY `fk_stock_stockitem_location` (`location`)  /* -> stock_stocklocation.id */,
  KEY `fk_stock_stockitem_belongs_to` (`belongs_to`)  /* -> stock_stockitem.id */,
  KEY `fk_stock_stockitem_customer` (`customer`)  /* -> company_company.id */,
  KEY `fk_stock_stockitem_build` (`build`)  /* -> build_build.id */,
  KEY `fk_stock_stockitem_consumed_by` (`consumed_by`)  /* -> build_build.id */,
  KEY `fk_stock_stockitem_purchase_order` (`purchase_order`)  /* -> order_purchaseorder.id */,
  KEY `fk_stock_stockitem_sales_order` (`sales_order`)  /* -> order_salesorder.id */,
  KEY `fk_stock_stockitem_stocktake_user` (`stocktake_user`)  /* -> auth_user.id */,
  KEY `fk_stock_stockitem_owner` (`owner`)  /* -> users_owner.id */
);

-- ==================================================================
-- app stock | model StockItemTestResult | table `stock_stockitemtestresult`
-- ==================================================================
CREATE TABLE `stock_stockitemtestresult` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `stock_item` int NOT NULL  /* FK -> stock_stockitem.id */,
  `template` int NOT NULL  /* FK -> part_parttesttemplate.id */,
  `result` bool NOT NULL DEFAULT 0,
  `value` varchar(500) NOT NULL,
  `attachment` varchar(100) NULL,
  `notes` varchar(500) NOT NULL,
  `user` int NULL  /* FK -> auth_user.id */,
  `test_station` varchar(500) NOT NULL,
  `started_datetime` datetime NULL,
  `finished_datetime` datetime NULL,
  `date` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stockitemtestresult_stock_item` (`stock_item`)  /* -> stock_stockitem.id */,
  KEY `fk_stock_stockitemtestresult_template` (`template`)  /* -> part_parttesttemplate.id */,
  KEY `fk_stock_stockitemtestresult_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app stock | model StockItemTracking | table `stock_stockitemtracking`
-- ==================================================================
CREATE TABLE `stock_stockitemtracking` (
  `id` int NOT NULL AUTO_INCREMENT,
  `tracking_type` int NOT NULL,
  `item` int NULL  /* FK -> stock_stockitem.id */,
  `part` int NULL  /* FK -> part_part.id */,
  `date` datetime NOT NULL  /* auto_now_add */,
  `notes` varchar(512) NULL,
  `user` int NULL  /* FK -> auth_user.id */,
  `deltas` json NULL,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stockitemtracking_item` (`item`)  /* -> stock_stockitem.id */,
  KEY `fk_stock_stockitemtracking_part` (`part`)  /* -> part_part.id */,
  KEY `fk_stock_stockitemtracking_user` (`user`)  /* -> auth_user.id */
);

-- ==================================================================
-- app stock | model StockLocation | table `stock_stocklocation`
--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)
-- ==================================================================
CREATE TABLE `stock_stocklocation` (
  `id` int NOT NULL AUTO_INCREMENT,
  `barcode_data` varchar(500) NOT NULL,
  `barcode_hash` varchar(128) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  `parent` int NULL  /* FK -> stock_stocklocation.id */,
  `pathstring` varchar(250) NOT NULL,
  `metadata` json NULL,
  `icon` varchar(100) NULL,
  `owner` int NULL  /* FK -> users_owner.id */,
  `structural` bool NOT NULL DEFAULT 0,
  `external` bool NOT NULL DEFAULT 0,
  `location_type` int NULL  /* FK -> stock_stocklocationtype.id */,
  `tree_id` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `lft` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  `rght` int NOT NULL DEFAULT 0  /* django-mptt TreeModel */,
  PRIMARY KEY (`id`),
  KEY `fk_stock_stocklocation_parent` (`parent`)  /* -> stock_stocklocation.id */,
  KEY `fk_stock_stocklocation_owner` (`owner`)  /* -> users_owner.id */,
  KEY `fk_stock_stocklocation_location_type` (`location_type`)  /* -> stock_stocklocationtype.id */
);

-- ==================================================================
-- app stock | model StockLocationType | table `stock_stocklocationtype`
-- ==================================================================
CREATE TABLE `stock_stocklocationtype` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(250) NOT NULL,
  `icon` varchar(100) NOT NULL,
  PRIMARY KEY (`id`)
);

-- ==================================================================
-- app users | model ApiToken | table `users_apitoken`
--   inherits columns from rest_framework.authtoken.Token (djangorestframework) (outside this source tree)
-- ==================================================================
CREATE TABLE `users_apitoken` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `key` varchar(100) NOT NULL,
  `hmac_digest` varchar(200) NULL,
  `user` int NOT NULL  /* FK -> auth_user.id */,
  `name` varchar(100) NOT NULL,
  `expiry` date NOT NULL,
  `last_seen` date NULL,
  `revoked` bool NOT NULL DEFAULT 0,
  `revocation_reason` longtext NULL,
  `revoked_by` int NULL  /* FK -> auth_user.id */,
  `issued_by` int NULL  /* FK -> auth_user.id */,
  `token_version` int NOT NULL DEFAULT 2,
  `pepper_id` varchar(100) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `u_users_apitoken_key` (`key`),
  KEY `fk_users_apitoken_user` (`user`)  /* -> auth_user.id */,
  KEY `fk_users_apitoken_revoked_by` (`revoked_by`)  /* -> auth_user.id */,
  KEY `fk_users_apitoken_issued_by` (`issued_by`)  /* -> auth_user.id */
);

-- ==================================================================
-- app users | model Owner | table `users_owner`
-- ==================================================================
CREATE TABLE `users_owner` (
  `id` int NOT NULL AUTO_INCREMENT,
  `owner_type` int NULL  /* FK -> contenttypes_contenttype.id */,
  `owner_id` int NULL,
  PRIMARY KEY (`id`),
  KEY `fk_users_owner_owner_type` (`owner_type`)  /* -> contenttypes_contenttype.id */
);

-- ==================================================================
-- app users | model RuleSet | table `users_ruleset`
-- ==================================================================
CREATE TABLE `users_ruleset` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  `group` int NOT NULL  /* FK -> auth_group.id */,
  `can_view` bool NOT NULL DEFAULT 0,
  `can_add` bool NOT NULL DEFAULT 0,
  `can_change` bool NOT NULL DEFAULT 0,
  `can_delete` bool NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `fk_users_ruleset_group` (`group`)  /* -> auth_group.id */
);

-- ==================================================================
-- app users | model UserProfile | table `users_userprofile`
-- ==================================================================
CREATE TABLE `users_userprofile` (
  `id` int NOT NULL AUTO_INCREMENT,
  `metadata` json NULL,
  `user` int NOT NULL  /* FK -> auth_user.id */,
  `language` varchar(10) NULL,
  `theme` json NULL,
  `widgets` json NULL,
  `displayname` varchar(255) NULL,
  `position` varchar(255) NULL,
  `status` varchar(2000) NULL,
  `location` varchar(2000) NULL,
  `active` bool NOT NULL DEFAULT 1,
  `contact` varchar(255) NULL,
  `type` varchar(10) NOT NULL,
  `organisation` varchar(255) NULL,
  `primary_group` int NULL  /* FK -> auth_group.id */,
  PRIMARY KEY (`id`),
  KEY `fk_users_userprofile_user` (`user`)  /* -> auth_user.id */,
  KEY `fk_users_userprofile_primary_group` (`primary_group`)  /* -> auth_group.id */
);

-- ==================================================================
-- Foreign-key relationships, one line each (commented out)
-- MySQL 8 does not enforce foreign keys: the FKs above are backed only by the
-- KEY indexes, and InvenTree checks them in Django's ORM.  These lines state the
-- same facts as source.column -> target.column, for a reader who wants to declare
-- real constraints on a DB that does enforce them.
-- ==================================================================
-- build_build.parent -> build_build.id
-- build_build.part -> part_part.id
-- build_build.sales_order -> order_salesorder.id
-- build_build.take_from -> stock_stocklocation.id
-- build_build.destination -> stock_stocklocation.id
-- build_build.completed_by -> auth_user.id
-- build_build.issued_by -> auth_user.id
-- build_build.responsible -> users_owner.id
-- build_build.project_code -> common_projectcode.id
-- build_builditem.build_line -> build_buildline.id
-- build_builditem.stock_item -> stock_stockitem.id
-- build_builditem.install_into -> stock_stockitem.id
-- build_buildline.build -> build_build.id
-- build_buildline.bom_item -> part_bomitem.id
-- common_attachment.upload_user -> auth_user.id
-- common_barcodescanresult.user -> auth_user.id
-- common_dataoutput.user -> auth_user.id
-- common_emailmessage.thread -> common_emailthread.global_id
-- common_inventreecustomuserstatemodel.model -> contenttypes_contenttype.id
-- common_inventreeusersetting.user -> auth_user.id
-- common_note.updated_by -> auth_user.id
-- common_note.model_type -> contenttypes_contenttype.id
-- common_notesimage.user -> auth_user.id
-- common_notesimage.note -> common_note.id
-- common_notificationmessage.target_content_type -> contenttypes_contenttype.id
-- common_notificationmessage.source_content_type -> contenttypes_contenttype.id
-- common_notificationmessage.user -> auth_user.id
-- part_partparameter.updated_by -> auth_user.id
-- part_partparameter.model_type -> contenttypes_contenttype.id
-- part_partparameter.template -> part_partparametertemplate.id
-- part_partparametertemplate.model_type -> contenttypes_contenttype.id
-- part_partparametertemplate.selectionlist -> common_selectionlist.id
-- common_projectcode.responsible -> users_owner.id
-- common_selectionlist.source_plugin -> plugin_pluginconfig.id
-- common_selectionlist.default -> common_selectionlistentry.id
-- common_selectionlistentry.list -> common_selectionlist.id
-- common_webhookendpoint.user -> auth_user.id
-- common_webhookmessage.endpoint -> common_webhookendpoint.id
-- company_address.company -> company_company.id
-- company_contact.company -> company_company.id
-- company_manufacturerpart.part -> part_part.id
-- company_manufacturerpart.manufacturer -> company_company.id
-- part_supplierpart.part -> part_part.id
-- part_supplierpart.supplier -> company_company.id
-- part_supplierpart.manufacturer_part -> company_manufacturerpart.id
-- part_supplierpricebreak.part -> part_supplierpart.id
-- importer_dataimportcolumnmap.session -> importer_dataimportsession.id
-- importer_dataimportrow.session -> importer_dataimportsession.id
-- importer_dataimportsession.user -> auth_user.id
-- machine_machinesetting.machine_config -> machine_machineconfig.id
-- order_purchaseorder.project_code -> common_projectcode.id
-- order_purchaseorder.created_by -> auth_user.id
-- order_purchaseorder.responsible -> users_owner.id
-- order_purchaseorder.contact -> company_contact.id
-- order_purchaseorder.address -> company_address.id
-- order_purchaseorder.supplier -> company_company.id
-- order_purchaseorder.received_by -> auth_user.id
-- order_purchaseorder.destination -> stock_stocklocation.id
-- order_purchaseorderextraline.project_code -> common_projectcode.id
-- order_purchaseorderextraline.order -> order_purchaseorder.id
-- order_purchaseorderlineitem.project_code -> common_projectcode.id
-- order_purchaseorderlineitem.order -> order_purchaseorder.id
-- order_purchaseorderlineitem.part -> part_supplierpart.id
-- order_purchaseorderlineitem.build_order -> build_build.id
-- order_purchaseorderlineitem.destination -> stock_stocklocation.id
-- order_returnorder.project_code -> common_projectcode.id
-- order_returnorder.created_by -> auth_user.id
-- order_returnorder.responsible -> users_owner.id
-- order_returnorder.contact -> company_contact.id
-- order_returnorder.address -> company_address.id
-- order_returnorder.customer -> company_company.id
-- order_returnorderextraline.project_code -> common_projectcode.id
-- order_returnorderextraline.order -> order_returnorder.id
-- order_returnorderlineitem.project_code -> common_projectcode.id
-- order_returnorderlineitem.order -> order_returnorder.id
-- order_returnorderlineitem.item -> stock_stockitem.id
-- order_salesorder.project_code -> common_projectcode.id
-- order_salesorder.created_by -> auth_user.id
-- order_salesorder.responsible -> users_owner.id
-- order_salesorder.contact -> company_contact.id
-- order_salesorder.address -> company_address.id
-- order_salesorder.customer -> company_company.id
-- order_salesorder.shipped_by -> auth_user.id
-- order_salesorderallocation.line -> order_salesorderlineitem.id
-- order_salesorderallocation.shipment -> order_salesordershipment.id
-- order_salesorderallocation.item -> stock_stockitem.id
-- order_salesorderextraline.project_code -> common_projectcode.id
-- order_salesorderextraline.order -> order_salesorder.id
-- order_salesorderlineitem.project_code -> common_projectcode.id
-- order_salesorderlineitem.order -> order_salesorder.id
-- order_salesorderlineitem.part -> part_part.id
-- order_salesordershipment.order -> order_salesorder.id
-- order_salesordershipment.shipment_address -> company_address.id
-- order_salesordershipment.checked_by -> auth_user.id
-- order_transferorder.project_code -> common_projectcode.id
-- order_transferorder.created_by -> auth_user.id
-- order_transferorder.responsible -> users_owner.id
-- order_transferorder.contact -> company_contact.id
-- order_transferorder.address -> company_address.id
-- order_transferorder.take_from -> stock_stocklocation.id
-- order_transferorder.destination -> stock_stocklocation.id
-- order_transferorderallocation.line -> order_transferorderlineitem.id
-- order_transferorderallocation.item -> stock_stockitem.id
-- order_transferorderlineitem.project_code -> common_projectcode.id
-- order_transferorderlineitem.order -> order_transferorder.id
-- order_transferorderlineitem.part -> part_part.id
-- part_bomitem.part -> part_part.id
-- part_bomitem.sub_part -> part_part.id
-- part_bomitemsubstitute.bom_item -> part_bomitem.id
-- part_bomitemsubstitute.part -> part_part.id
-- part_part.variant_of -> part_part.id
-- part_part.category -> part_partcategory.id
-- part_part.revision_of -> part_part.id
-- part_part.default_location -> stock_stocklocation.id
-- part_part.bom_checked_by -> auth_user.id
-- part_part.creation_user -> auth_user.id
-- part_part.responsible_owner -> users_owner.id
-- part_partcategory.parent -> part_partcategory.id
-- part_partcategory.default_location -> stock_stocklocation.id
-- part_partcategoryparametertemplate.category -> part_partcategory.id
-- part_partcategoryparametertemplate.template -> part_partparametertemplate.id
-- part_partcategorystar.category -> part_partcategory.id
-- part_partcategorystar.user -> auth_user.id
-- part_partinternalpricebreak.part -> part_part.id
-- part_partpricing.part -> part_part.id
-- part_partrelated.part_1 -> part_part.id
-- part_partrelated.part_2 -> part_part.id
-- part_partsellpricebreak.part -> part_part.id
-- part_partstar.part -> part_part.id
-- part_partstar.user -> auth_user.id
-- part_partstocktake.part -> part_part.id
-- part_parttesttemplate.part -> part_part.id
-- plugin_pluginsetting.plugin -> plugin_pluginconfig.id
-- plugin_pluginusersetting.plugin -> plugin_pluginconfig.id
-- plugin_pluginusersetting.user -> auth_user.id
-- report_labeltemplate.updated_by -> auth_user.id
-- report_reporttemplate.updated_by -> auth_user.id
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
-- stock_stockitem.stocktake_user -> auth_user.id
-- stock_stockitem.owner -> users_owner.id
-- stock_stockitemtestresult.stock_item -> stock_stockitem.id
-- stock_stockitemtestresult.template -> part_parttesttemplate.id
-- stock_stockitemtestresult.user -> auth_user.id
-- stock_stockitemtracking.item -> stock_stockitem.id
-- stock_stockitemtracking.part -> part_part.id
-- stock_stockitemtracking.user -> auth_user.id
-- stock_stocklocation.parent -> stock_stocklocation.id
-- stock_stocklocation.owner -> users_owner.id
-- stock_stocklocation.location_type -> stock_stocklocationtype.id
-- users_apitoken.user -> auth_user.id
-- users_apitoken.revoked_by -> auth_user.id
-- users_apitoken.issued_by -> auth_user.id
-- users_owner.owner_type -> contenttypes_contenttype.id
-- users_ruleset.group -> auth_group.id
-- users_userprofile.user -> auth_user.id
-- users_userprofile.primary_group -> auth_group.id

-- ==================================================================
-- index
-- ==================================================================
-- build        Build                              build_build                         31 cols  9 fk
-- build        BuildItem                          build_builditem                      6 cols  3 fk
-- build        BuildLine                          build_buildline                      5 cols  2 fk
-- common       Attachment                         common_attachment                   12 cols  1 fk
-- common       BarcodeScanResult                  common_barcodescanresult             8 cols  1 fk
-- common       CustomUnit                         common_customunit                    4 cols  0 fk
-- common       DataOutput                         common_dataoutput                   11 cols  1 fk
-- common       EmailMessage                       common_emailmessage                 18 cols  1 fk
-- common       EmailThread                        common_emailthread                   6 cols  0 fk
-- common       InvenTreeCustomUserStateModel      common_inventreecustomuserstatemodel   8 cols  1 fk
-- common       InvenTreeSetting                   common_inventreesetting              4 cols  0 fk
-- common       InvenTreeUserSetting               common_inventreeusersetting          5 cols  1 fk
-- common       NewsFeedEntry                      common_newsfeedentry                 8 cols  0 fk
-- common       Note                               common_note                         11 cols  2 fk
-- common       NotesImage                         common_notesimage                    5 cols  2 fk
-- common       NotificationEntry                  common_notificationentry             4 cols  0 fk
-- common       NotificationMessage                common_notificationmessage          12 cols  3 fk
-- common       Parameter                          part_partparameter                  10 cols  3 fk
-- common       ParameterTemplate                  part_partparametertemplate          11 cols  2 fk
-- common       ProjectCode                        common_projectcode                   6 cols  1 fk
-- common       SelectionList                      common_selectionlist                11 cols  2 fk
-- common       SelectionListEntry                 common_selectionlistentry            6 cols  1 fk
-- common       WebhookEndpoint                    common_webhookendpoint               7 cols  1 fk
-- common       WebhookMessage                     common_webhookmessage                6 cols  1 fk
-- company      Address                            company_address                     13 cols  1 fk
-- company      Company                            company_company                     19 cols  0 fk
-- company      Contact                            company_contact                      7 cols  1 fk
-- company      ManufacturerPart                   company_manufacturerpart             9 cols  2 fk
-- company      SupplierPart                       part_supplierpart                   21 cols  3 fk
-- company      SupplierPriceBreak                 part_supplierpricebreak              6 cols  1 fk
-- importer     DataImportColumnMap                importer_dataimportcolumnmap         5 cols  1 fk
-- importer     DataImportRow                      importer_dataimportrow               8 cols  1 fk
-- importer     DataImportSession                  importer_dataimportsession          13 cols  1 fk
-- machine      MachineConfig                      machine_machineconfig                5 cols  0 fk
-- machine      MachineSetting                     machine_machinesetting               5 cols  1 fk
-- order        PurchaseOrder                      order_purchaseorder                 25 cols  8 fk
-- order        PurchaseOrderExtraLine             order_purchaseorderextraline        16 cols  2 fk
-- order        PurchaseOrderLineItem              order_purchaseorderlineitem         18 cols  5 fk
-- order        ReturnOrder                        order_returnorder                   23 cols  6 fk
-- order        ReturnOrderExtraLine               order_returnorderextraline          16 cols  2 fk
-- order        ReturnOrderLineItem                order_returnorderlineitem           19 cols  3 fk
-- order        SalesOrder                         order_salesorder                    24 cols  7 fk
-- order        SalesOrderAllocation               order_salesorderallocation           5 cols  3 fk
-- order        SalesOrderExtraLine                order_salesorderextraline           16 cols  2 fk
-- order        SalesOrderLineItem                 order_salesorderlineitem            16 cols  3 fk
-- order        SalesOrderShipment                 order_salesordershipment            13 cols  3 fk
-- order        TransferOrder                      order_transferorder                 24 cols  7 fk
-- order        TransferOrderAllocation            order_transferorderallocation        4 cols  2 fk
-- order        TransferOrderLineItem              order_transferorderlineitem         14 cols  3 fk
-- part         BomItem                            part_bomitem                        18 cols  2 fk
-- part         BomItemSubstitute                  part_bomitemsubstitute               4 cols  2 fk
-- part         Part                               part_part                           45 cols  7 fk
-- part         PartCategory                       part_partcategory                   13 cols  2 fk
-- part         PartCategoryParameterTemplate      part_partcategoryparametertemplate   5 cols  2 fk
-- part         PartCategoryStar                   part_partcategorystar                3 cols  2 fk
-- part         PartInternalPriceBreak             part_partinternalpricebreak          6 cols  1 fk
-- part         PartPricing                        part_partpricing                    41 cols  1 fk
-- part         PartRelated                        part_partrelated                     5 cols  2 fk
-- part         PartSellPriceBreak                 part_partsellpricebreak              6 cols  1 fk
-- part         PartStar                           part_partstar                        3 cols  2 fk
-- part         PartStocktake                      part_partstocktake                   9 cols  1 fk
-- part         PartTestTemplate                   part_parttesttemplate               11 cols  1 fk
-- plugin       PluginConfig                       plugin_pluginconfig                  6 cols  0 fk
-- plugin       PluginSetting                      plugin_pluginsetting                 4 cols  1 fk
-- plugin       PluginUserSetting                  plugin_pluginusersetting             5 cols  2 fk
-- report       LabelTemplate                      report_labeltemplate                15 cols  1 fk
-- report       ReportAsset                        report_reportasset                   3 cols  0 fk
-- report       ReportSnippet                      report_reportsnippet                 3 cols  0 fk
-- report       ReportTemplate                     report_reporttemplate               16 cols  1 fk
-- scim         ScimConfiguration                  scim_scimconfiguration               5 cols  0 fk
-- stock        StockItem                          stock_stockitem                     32 cols 12 fk
-- stock        StockItemTestResult                stock_stockitemtestresult           13 cols  3 fk
-- stock        StockItemTracking                  stock_stockitemtracking              8 cols  3 fk
-- stock        StockLocation                      stock_stocklocation                 16 cols  3 fk
-- stock        StockLocationType                  stock_stocklocationtype              5 cols  0 fk
-- users        ApiToken                           users_apitoken                      14 cols  3 fk
-- users        Owner                              users_owner                          3 cols  1 fk
-- users        RuleSet                            users_ruleset                        7 cols  1 fk
-- users        UserProfile                        users_userprofile                   15 cols  2 fk
-- 79 tables owned by InvenTree's own apps
