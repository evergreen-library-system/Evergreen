-- Evergreen DB patch 0669.data.recall_and_force_holds.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0669', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 517, 'COPY_HOLDS_FORCE', oils_i18n_gettext( 517, 
    'Allow a user to place a force hold on a specific copy', 'ppl', 'description' )),
 ( 518, 'COPY_HOLDS_RECALL', oils_i18n_gettext( 518, 
    'Allow a user to place a recall hold on a specific copy', 'ppl', 'description' ));


COMMIT;
