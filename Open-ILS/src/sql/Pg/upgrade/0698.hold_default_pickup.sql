-- Evergreen DB patch 0698.hold_default_pickup.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0698', :eg_version);

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_pickup_location', TRUE, 'Default Hold Pickup Location', 'Default location for holds pickup', 'integer');

COMMIT;
