-- Evergreen DB patch XXXX.schema.address-alert.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE actor.address_alert (
    id              SERIAL  PRIMARY KEY,
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    active          BOOL    NOT NULL DEFAULT TRUE,
    match_all       BOOL    NOT NULL DEFAULT TRUE,
    alert_message   TEXT    NOT NULL,
    street1         TEXT,
    street2         TEXT,
    city            TEXT,
    county          TEXT,
    state           TEXT,
    country         TEXT,
    post_code       TEXT,
    mailing_address BOOL    NOT NULL DEFAULT FALSE,
    billing_address BOOL    NOT NULL DEFAULT FALSE
);

CREATE OR REPLACE FUNCTION actor.address_alert_matches (
        org_unit INT, 
        street1 TEXT, 
        street2 TEXT, 
        city TEXT, 
        county TEXT, 
        state TEXT, 
        country TEXT, 
        post_code TEXT,
        mailing_address BOOL DEFAULT FALSE,
        billing_address BOOL DEFAULT FALSE
    ) RETURNS SETOF actor.address_alert AS $$

SELECT *
FROM actor.address_alert
WHERE
    active
    AND owner IN (SELECT id FROM actor.org_unit_ancestors($1)) 
    AND (
        (NOT mailing_address AND NOT billing_address)
        OR (mailing_address AND $9)
        OR (billing_address AND $10)
    )
    AND (
            (
                match_all
                AND COALESCE($2, '') ~* COALESCE(street1,   '.*')
                AND COALESCE($3, '') ~* COALESCE(street2,   '.*')
                AND COALESCE($4, '') ~* COALESCE(city,      '.*')
                AND COALESCE($5, '') ~* COALESCE(county,    '.*')
                AND COALESCE($6, '') ~* COALESCE(state,     '.*')
                AND COALESCE($7, '') ~* COALESCE(country,   '.*')
                AND COALESCE($8, '') ~* COALESCE(post_code, '.*')
            ) OR (
                NOT match_all 
                AND (  
                       $2 ~* street1
                    OR $3 ~* street2
                    OR $4 ~* city
                    OR $5 ~* county
                    OR $6 ~* state
                    OR $7 ~* country
                    OR $8 ~* post_code
                )
            )
        )
    ORDER BY actor.org_unit_proximity(owner, $1)
$$ LANGUAGE SQL;

COMMIT;

/* UNDO
DROP FUNCTION actor.address_alert_matches(INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOL, BOOL);
DROP TABLE actor.address_alert;
*/
