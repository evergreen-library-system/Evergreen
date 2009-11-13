BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0082'); -- miker

CREATE TABLE config.usr_setting_type (

    name TEXT PRIMARY KEY,
    opac_visible BOOL NOT NULL DEFAULT FALSE,
    label TEXT UNIQUE NOT NULL,
    description TEXT,
    datatype TEXT NOT NULL DEFAULT 'string',
    fm_class TEXT,

    --
    -- define valid datatypes
    --
    CONSTRAINT coust_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
        'date', 'string', 'object', 'array', 'link' ) ),

    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT coust_no_empty_link CHECK
    ( ( datatype = 'link' AND fm_class IS NOT NULL ) OR
        ( datatype <> 'link' AND fm_class IS NULL ) )

);

-- Yeah, this is data, but I need it for the schema bit at the end
INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_font', TRUE, 'OPAC Font Size', 'OPAC Font Size', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_search_depth', TRUE, 'OPAC Search Depth', 'OPAC Search Depth', 'integer');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_search_location', TRUE, 'OPAC Search Location', 'OPAC Search Location', 'integer');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.hits_per_page', TRUE, 'Hits per Page', 'Hits per Page', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.hold_notify', TRUE, 'Hold Notification Format', 'Hold Notification Format', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('staff_client.catalog.record_view.default', TRUE, 'Default Record View', 'Default Record View', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('staff_client.copy_editor.templates', TRUE, 'Copy Editor Template', 'Copy Editor Template', 'object');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('circ.holds_behind_desk', FALSE, 'Hold is behind Circ Desk', 'Hold is behind Circ Desk', 'bool');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    SELECT  DISTINCT name, FALSE, name, name, 'string'
      FROM  actor.usr_setting
      WHERE name NOT IN (
                'circ.holds_behind_desk',
                'opac.default_font',
                'opac.default_search_depth',
                'opac.default_search_location',
                'opac.hits_per_page',
                'opac.hold_notify',
                'staff_client.catalog.record_view.default',
                'staff_client.copy_editor.templates'
            );


ALTER TABLE actor.usr_setting
    ADD CONSTRAINT user_setting_type_fkey
    FOREIGN KEY (name) REFERENCES config.usr_setting_type (name) 
    ON DELETE CASCADE ON UPDATE CASCADE
    DEFERRABLE INITIALLY DEFERRED;

COMMIT;

