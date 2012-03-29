-- Evergreen DB patch 0697.data.place_currently_unfillable_hold.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0697', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 524, 'PLACE_UNFILLABLE_HOLD', oils_i18n_gettext( 524,
    'Allows a user to place a hold that cannot currently be filled.', 'ppl', 'description' ));


COMMIT;
