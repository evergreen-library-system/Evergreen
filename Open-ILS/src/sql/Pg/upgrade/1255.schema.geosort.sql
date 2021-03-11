BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1255', :eg_version);

CREATE EXTENSION earthdistance CASCADE;

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

-- geolocation-aware variant
CREATE OR REPLACE FUNCTION evergreen.rank_ou(lib INT, search_lib INT, pref_lib INT, plat FLOAT, plon FLOAT)
RETURNS INTEGER AS $$
    SELECT COALESCE(

        -- lib matches search_lib
        (SELECT CASE WHEN $1 = $2 THEN -20000 END),

        -- lib matches pref_lib
        (SELECT CASE WHEN $1 = $3 THEN -10000 END),


        -- pref_lib is a child of search_lib and lib is a child of pref lib.
        -- For example, searching CONS, pref lib is SYS1,
        -- copies at BR1 and BR2 sort to the front.
        (SELECT distance - 5000
            FROM actor.org_unit_descendants_distance($3)
            WHERE id = $1 AND $3 IN (
                SELECT id FROM actor.org_unit_descendants($2))),

        -- lib is a child of search_lib
        (SELECT distance FROM actor.org_unit_descendants_distance($2) WHERE id = $1),

        -- all others pay cash
        1000
    ) + ((SELECT CASE WHEN addr.latitude IS NULL THEN 0 ELSE -20038 END) + (earth_distance( -- shortest GC distance is returned, only half the circumfrence is needed
            ll_to_earth(
                COALESCE(addr.latitude,plat), -- if the org has no coords, we just
                COALESCE(addr.longitude,plon) -- force 0 distance and let the above tie-break
            ),ll_to_earth(plat,plon)
        ) / 1000)::INT ) -- earth_distance is in meters, convert to kilometers and subtract from largest distance
    FROM actor.org_unit org
         LEFT JOIN actor.org_address addr ON (org.billing_address = addr.id)
    WHERE org.id = $1;
$$ LANGUAGE SQL STABLE;

COMMIT;
