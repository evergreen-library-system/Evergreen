-- Evergreen DB patch xxxx.data.authority_thesaurus_update.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0773', :eg_version);


INSERT INTO authority.thesaurus (code, name, control_set) VALUES
    (' ', oils_i18n_gettext(' ','Alternate no attempt to code','at','name'), NULL);

COMMIT;
