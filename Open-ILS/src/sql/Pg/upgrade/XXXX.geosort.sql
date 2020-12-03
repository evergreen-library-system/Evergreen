BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- 005.schema.actors.sql

-- CREATE TABLE actor.org_address (
--     ...
--     latitude    FLOAT,
--     longitude   FLOAT
-- );

ALTER TABLE actor.org_address ADD COLUMN latitude FLOAT;
ALTER TABLE actor.org_address ADD COLUMN longitude FLOAT;

-- 002.schema.config.sql

CREATE TABLE config.geolocation_service (
    id           SERIAL PRIMARY KEY,
    active       BOOLEAN,
    owner        INT NOT NULL, -- REFERENCES actor.org_unit (id)
    name         TEXT,
    service_code TEXT,
    api_key      TEXT
);

-- 800.fkeys.sql

ALTER TABLE config.geolocation_service ADD CONSTRAINT cgs_owner_fkey
    FOREIGN KEY (owner) REFERENCES  actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED;

-- 950.data.seed-values.sql

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'opac.use_geolocation',
    NULL,
    FALSE,
    oils_i18n_gettext(
        'opac.use_geolocation',
        'Offer use of geographic location services in the public catalog',
        'cgf', 'label'
    )
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'opac.holdings_sort_by_geographic_proximity',
    oils_i18n_gettext('opac.holdings_sort_by_geographic_proximity',
        'Enable Holdings Sort by Geographic Proximity',
        'coust', 'label'),
    'opac',
    oils_i18n_gettext('opac.holdings_sort_by_geographic_proximity',
        'When set to TRUE, will cause the record details page to display the controls for sorting holdings by geographic proximity. This also depends on the global flag opac.use_geolocation being enabled.',
        'coust', 'description'),
    'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'opac.geographic_proximity_in_miles',
    oils_i18n_gettext('opac.geographic_proximity_in_miles',
        'Show Geographic Proximity in Miles',
        'coust', 'label'),
    'opac',
    oils_i18n_gettext('opac.geographic_proximity_in_miles',
        'When set to TRUE, will cause the record details page to show distances for geographic proximity in miles instead of kilometers.',
        'coust', 'description'),
    'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype, fm_class)
VALUES (
    'opac.geographic_location_service_for_address',
    oils_i18n_gettext('opac.geographic_location_service_for_address',
        'Geographic Location Service to use for Addresses',
        'coust', 'label'),
    'opac',
    oils_i18n_gettext('opac.geographic_location_service_for_address',
        'Specifies which geographic location service to use for converting address input to geographic coordinates.',
        'coust', 'description'),
    'link', 'cgs'
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 630, 'VIEW_GEOLOCATION_SERVICES', oils_i18n_gettext(630,
    'View geographic location services', 'ppl', 'description')),
 ( 631, 'ADMIN_GEOLOCATION_SERVICES', oils_i18n_gettext(631,
    'Administer geographic location services', 'ppl', 'description'))
;

COMMIT;
