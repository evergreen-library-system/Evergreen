-- Add bib bucket related columns to reporter.schedule

BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE reporter.schedule ADD COLUMN new_record_bucket BOOL NOT NULL DEFAULT 'false';
ALTER TABLE reporter.schedule ADD COLUMN existing_record_bucket BOOL NOT NULL DEFAULT 'false';

CREATE TABLE container.biblio_record_entry_bucket_shares (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    share_org   INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT brebs_org_once_per_bucket UNIQUE (bucket, share_org)
);

CREATE TYPE container.usr_flag_type AS ENUM ('favorite');
CREATE TABLE container.biblio_record_entry_bucket_usr_flags (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    usr         INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    flag        container.usr_flag_type NOT NULL DEFAULT 'favorite',
    CONSTRAINT brebs_flag_once_per_usr_per_bucket UNIQUE (bucket, usr, flag)
);

-- Add settings for record bucket interfaces

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record_buckets', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record_buckets',
        'Grid Config: catalog.record_buckets',
        'cwst', 'label'
    )
), (
    'eg.grid.catalog.record_bucket.content', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record_bucket.content',
        'Grid Config: catalog.record_bucket.content',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.record_buckets', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.record_buckets',
        'Grid Filters: catalog.record_buckets',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.record_bucket.content', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.record_bucket.content',
        'Grid Filters: catalog.record_bucket.content',
        'cwst', 'label'
    )
), (
    'eg.grid.buckets.user_shares', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.buckets.user_shares',
        'Grid Config: eg.grid.buckets.user_shares',
        'cwst', 'label'
    )
);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   659,
   'TRANSFER_CONTAINER',
   oils_i18n_gettext(659,
     'Allow for transferring ownership of a bucket.', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'TRANSFER_CONTAINER');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   660,
   'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE',
   oils_i18n_gettext(660,
     'Allow sharing of record buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   661,
   'ADMIN_CONTAINER_CALL_NUMBER_USER_SHARE',
   oils_i18n_gettext(661,
     'Allow sharing of call number buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_CALL_NUMBER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   662,
   'ADMIN_CONTAINER_COPY_USER_SHARE',
   oils_i18n_gettext(662,
     'Allow sharing of copy buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_COPY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   663,
   'ADMIN_CONTAINER_USER_USER_SHARE',
   oils_i18n_gettext(663,
     'Allow sharing of user buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_USER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   664,
   'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE',
   oils_i18n_gettext(664,
     'Allow viewing of record bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   665,
   'VIEW_CONTAINER_CALL_NUMBER_USER_SHARE',
   oils_i18n_gettext(665,
     'Allow viewing of call number bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_CALL_NUMBER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   666,
   'VIEW_CONTAINER_COPY_USER_SHARE',
   oils_i18n_gettext(666,
     'Allow viewing of copy bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_COPY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   667,
   'VIEW_CONTAINER_USER_USER_SHARE',
   oils_i18n_gettext(667,
     'Allow viewing of user bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_USER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   668,
   'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE',
   oils_i18n_gettext(668,
     'Allow sharing of record buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   669,
   'ADMIN_CONTAINER_CALL_NUMBER_ORG_SHARE',
   oils_i18n_gettext(669,
     'Allow sharing of call number buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_CALL_NUMBER_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   670,
   'ADMIN_CONTAINER_COPY_ORG_SHARE',
   oils_i18n_gettext(670,
     'Allow sharing of copy buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_COPY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   671,
   'ADMIN_CONTAINER_USER_ORG_SHARE',
   oils_i18n_gettext(671,
     'Allow sharing of user buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_USER_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   672,
   'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE',
   oils_i18n_gettext(672,
     'Allow viewing of record bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   673,
   'VIEW_CONTAINER_CALL_NUMBER_ORG_SHARE',
   oils_i18n_gettext(673,
     'Allow viewing of call number bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_CALL_NUMBER_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   674,
   'VIEW_CONTAINER_COPY_ORG_SHARE',
   oils_i18n_gettext(674,
     'Allow viewing of copy bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_COPY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   675,
   'VIEW_CONTAINER_USER_ORG_SHARE',
   oils_i18n_gettext(675,
     'Allow viewing of user bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_USER_ORG_SHARE');

UPDATE  config.ui_staff_portal_page_entry
  SET   target_url = '/eg2/staff/cat/bucket/record'
  WHERE id = 7
        AND entry_type = 'menuitem'
        AND target_url = '/eg/staff/cat/bucket/record/'
;

COMMIT;
