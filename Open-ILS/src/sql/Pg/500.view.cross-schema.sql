/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

BEGIN;


CREATE OR REPLACE VIEW money.billable_xact_summary_location_view AS
    SELECT  m.*, COALESCE(c.circ_lib, g.billing_location, r.pickup_lib) AS billing_location
      FROM  money.materialized_billable_xact_summary m
            LEFT JOIN action.circulation c ON (c.id = m.id)
            LEFT JOIN money.grocery g ON (g.id = m.id)
            LEFT JOIN booking.reservation r ON (r.id = m.id);

CREATE OR REPLACE VIEW money.open_billable_xact_summary AS 
    SELECT * FROM money.billable_xact_summary_location_view
    WHERE xact_finish IS NULL;

CREATE OR REPLACE VIEW money.open_usr_summary AS
    SELECT 
        usr, 
        sum(total_paid) AS total_paid, 
        sum(total_owed) AS total_owed, 
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    WHERE xact_finish IS NULL
    GROUP BY usr;

CREATE OR REPLACE VIEW money.open_with_balance_usr_summary AS
    SELECT
        usr,
        sum(total_paid) AS total_paid,
        sum(total_owed) AS total_owed,
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    WHERE xact_finish IS NULL AND balance_owed <> 0.0
    GROUP BY usr;

CREATE OR REPLACE VIEW money.open_usr_circulation_summary AS
    SELECT 
        usr,
        SUM(total_paid) AS total_paid,
        SUM(total_owed) AS total_owed,
        SUM(balance_owed) AS balance_owed
    FROM  money.materialized_billable_xact_summary
    WHERE xact_type = 'circulation' AND xact_finish IS NULL
    GROUP BY usr;


-- Not a view, but it's cross-schema..
CREATE TABLE config.idl_field_doc (
    id              BIGSERIAL   PRIMARY KEY,
    fm_class        TEXT        NOT NULL,
    field           TEXT        NOT NULL,
    owner           INT         NOT NULL    REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    string          TEXT        NOT NULL
);
CREATE UNIQUE INDEX idl_field_doc_identity ON config.idl_field_doc (fm_class,field,owner);


CREATE OR REPLACE VIEW config.marc_field_for_ou AS
WITH RECURSIVE ou_marc_fields(id, marc_format, marc_record_type, tag,
                              name, description, fixed_field, repeatable,
                              mandatory, hidden, owner, depth) AS (
    -- start with all MARC fields defined by the controlling national standard
    SELECT id, marc_format, marc_record_type, tag, name, description, fixed_field, repeatable, mandatory, hidden, owner, 0
    FROM config.marc_field
    WHERE owner IS NULL
    UNION
    -- as well as any purely local ones that have been added
    SELECT id, marc_format, marc_record_type, tag, name, description, fixed_field, repeatable, mandatory, hidden, owner, 0
    FROM config.marc_field
    WHERE ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag] NOT IN (
        SELECT ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag]
        FROM config.marc_field
        WHERE owner IS NULL
    )
  UNION
    -- and start walking down the org unit hierarchy,
    -- letting entries for child OUs override field names,
    -- descriptions, repeatability, and the like.  Letting
    -- fixed-fieldness be overridable is something that falls
    -- from the implementation, but is unlikely to be useful
    SELECT c.id, marc_format, marc_record_type, tag,
           COALESCE(c.name, p.name),
           COALESCE(c.description, p.description),
           COALESCE(c.fixed_field, p.fixed_field),
           COALESCE(c.repeatable, p.repeatable),
           COALESCE(c.mandatory, p.mandatory),
           COALESCE(c.hidden, p.hidden),
           c.owner,
           depth + 1
    FROM config.marc_field c
    JOIN ou_marc_fields p USING (marc_format, marc_record_type, tag)
    JOIN actor.org_unit aou ON (c.owner = aou.id)
    WHERE (aou.parent_ou = p.owner OR (aou.parent_ou IS NULL AND p.owner IS NULL))
)
SELECT id, marc_format, marc_record_type, tag,
       name, description, fixed_field, repeatable,
       mandatory, hidden, owner, depth
FROM ou_marc_fields;

CREATE OR REPLACE VIEW config.marc_subfield_for_ou AS
WITH RECURSIVE ou_marc_subfields(id, marc_format, marc_record_type, tag, code,
                              description, repeatable,
                              mandatory, hidden, value_ctype, owner, depth) AS (
    -- start with all MARC subfields defined by the controlling national standard
    SELECT id, marc_format, marc_record_type, tag, code, description, repeatable, mandatory,
           hidden, value_ctype, owner, 0
    FROM config.marc_subfield
    WHERE owner IS NULL
    UNION
    -- as well as any purely local ones that have been added
    SELECT id, marc_format, marc_record_type, tag, code, description, repeatable, mandatory,
           hidden, value_ctype, owner, 0
    FROM config.marc_subfield
    WHERE ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag, code] NOT IN (
        SELECT ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag, code]
        FROM config.marc_subfield
        WHERE owner IS NULL
    )
  UNION
    -- and start walking down the org unit hierarchy,
    -- letting entries for child OUs override subfield
    -- descriptions, repeatability, and the like.
    SELECT c.id, marc_format, marc_record_type, tag, code,
           COALESCE(c.description, p.description),
           COALESCE(c.repeatable, p.repeatable),
           COALESCE(c.mandatory, p.mandatory),
           COALESCE(c.hidden, p.hidden),
           COALESCE(c.value_ctype, p.value_ctype),
           c.owner,
           depth + 1
    FROM config.marc_subfield c
    JOIN ou_marc_subfields p USING (marc_format, marc_record_type, tag, code)
    JOIN actor.org_unit aou ON (c.owner = aou.id)
    WHERE (aou.parent_ou = p.owner OR (aou.parent_ou IS NULL AND p.owner IS NULL))
)
SELECT id, marc_format, marc_record_type, tag, code,
       description, repeatable,
       mandatory, hidden, value_ctype, owner, depth
FROM ou_marc_subfields;

CREATE OR REPLACE FUNCTION config.ou_marc_fields(marc_format INTEGER, marc_record_type config.marc_record_type, ou INTEGER) RETURNS SETOF config.marc_field AS $func$
    SELECT id, marc_format, marc_record_type, tag, name, description, fixed_field, repeatable, mandatory, hidden, owner
    FROM (
        SELECT id, marc_format, marc_record_type, tag, name, description,
              fixed_field, repeatable, mandatory, hidden, owner, depth,
              MAX(depth) OVER (PARTITION BY marc_format, marc_record_type, tag) AS winner
        FROM config.marc_field_for_ou
        WHERE (owner IS NULL
               OR owner IN (SELECT id FROM actor.org_unit_ancestors($3)))
        AND   marc_format = $1
        AND   marc_record_type = $2
    ) AS s
    WHERE depth = winner
    AND not hidden;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION config.ou_marc_subfields(marc_format INTEGER, marc_record_type config.marc_record_type, ou INTEGER) RETURNS SETOF config.marc_subfield AS $func$
    SELECT id, marc_format, marc_record_type, tag, code, description, repeatable, mandatory,
           hidden, value_ctype, owner
    FROM (
        SELECT id, marc_format, marc_record_type, tag, code, description,
              repeatable, mandatory, hidden, value_ctype, owner, depth,
              MAX(depth) OVER (PARTITION BY marc_format, marc_record_type, tag, code) AS winner
        FROM config.marc_subfield_for_ou
        WHERE (owner IS NULL
               OR owner IN (SELECT id FROM actor.org_unit_ancestors($3)))
        AND   marc_format = $1
        AND   marc_record_type = $2
    ) AS s
    WHERE depth = winner
    AND not hidden;
$func$ LANGUAGE SQL;

COMMIT;
