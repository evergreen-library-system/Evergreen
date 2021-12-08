BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE asset.course_module_term
        DROP CONSTRAINT course_module_term_name_key;

ALTER TABLE asset.course_module_term
        ADD CONSTRAINT cmt_once_per_owning_lib UNIQUE (owning_lib, name);

COMMIT;
