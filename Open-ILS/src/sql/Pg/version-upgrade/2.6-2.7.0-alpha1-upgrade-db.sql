--Upgrade Script for 2.6 to 2.7.0-alpha1
\set eg_version '''2.7.0-alpha1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.7.0-alpha1', :eg_version);
-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0884', :eg_version);

UPDATE container.biblio_record_entry_bucket_type
SET label = oils_i18n_gettext(
	'bookbag',
	'Book List',
	'cbrebt',
	'label'
) WHERE code = 'bookbag';

UPDATE container.user_bucket_type
SET label = oils_i18n_gettext(
	'folks:pub_book_bags.view',
	'List Published Book Lists',
	'cubt',
	'label'
) WHERE code = 'folks:pub_book_bags.view';

UPDATE container.user_bucket_type
SET label = oils_i18n_gettext(
	'folks:pub_book_bags.add',
	'Add to Published Book Lists',
	'cubt',
	'label'
) WHERE code = 'folks:pub_book_bags.add';

UPDATE action_trigger.hook
SET description = oils_i18n_gettext(
	'container.biblio_record_entry_bucket.csv',
	'Produce a CSV file representing a book list',
	'ath',
	'description'
) WHERE key = 'container.biblio_record_entry_bucket.csv';

UPDATE action_trigger.reactor
SET description = oils_i18n_gettext(
	'ContainerCSV',
	'Facilitates producing a CSV file representing a book list by introducing an "items" variable into the TT environment, sorted as dictated according to user params',
	'atr',
	'description'
)
WHERE module = 'ContainerCSV';

UPDATE action_trigger.event_definition
SET template = REPLACE(template, 'bookbag', 'book list'),
name = 'Book List CSV'
WHERE name = 'Bookbag CSV';

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
	'opac.patron.temporary_list_warn',
	'Present a warning dialog to the patron when a patron adds a book to a temporary book list.',
	'coust',
	'description'
) WHERE name = 'opac.patron.temporary_list_warn';

UPDATE config.usr_setting_type
SET label = oils_i18n_gettext(
	'opac.default_list',
	'Default list to use when adding to a list',
	'cust',
	'label'
),
description = oils_i18n_gettext(
	'opac.default_list',
	'Default list to use when adding to a list',
	'cust',
	'description'
) WHERE name = 'opac.default_list';


SELECT evergreen.upgrade_deps_block_check('0885', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT[],
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE(id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    WITH RECURSIVE ou_depth AS (
        SELECT COALESCE(
            $3,
            (
                SELECT depth
                FROM actor.org_unit_type aout
                    INNER JOIN actor.org_unit ou ON ou_type = aout.id
                WHERE ou.id = $2
            )
        ) AS depth
    ), descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id),
                ou_depth
        WHERE ad.depth = ou_depth.depth
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
        WHERE ou.id = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ), descendants as (
        SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id)
    )

    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, aou.name, acn.label_sortkey,
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN descendants AS aou ON (acp.circ_lib = aou.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN
                EXISTS (
                    SELECT 1
                    FROM asset.opac_visible_copies
                    WHERE copy_id = acp.id AND record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, acp.status, aou.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY
                COALESCE(
                    CASE WHEN aou.id = $2 THEN -20000 END,
                    CASE WHEN aou.id = $6 THEN -10000 END,
                    (SELECT distance - 5000
                        FROM actor.org_unit_descendants_distance($6) as x
                        WHERE x.id = aou.id AND $6 IN (
                            SELECT q.id FROM actor.org_unit_descendants($2) as q)),
                    (SELECT e.distance FROM actor.org_unit_descendants_distance($2) as e WHERE e.id = aou.id),
                    1000
                ),
                evergreen.rank_cp_status(acp.status)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$ LANGUAGE SQL STABLE ROWS 10;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes
    ( bibid BIGINT, ouid INT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, pref_lib INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[] )
    RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT)
    AS $$ SELECT * FROM evergreen.ranked_volumes(ARRAY[$1],$2,$3,$4,$5,$6,$7) $$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('0886', :eg_version);

INSERT INTO config.copy_status
(id, name, holdable, opac_visible, copy_active, restrict_copy_delete)
VALUES (17, 'Lost and Paid', FALSE, FALSE, FALSE, TRUE);

INSERT INTO config.org_unit_setting_type
(name, grp, label, description, datatype)
VALUES
('circ.use_lost_paid_copy_status',
 'circ',
 oils_i18n_gettext('circ.use_lost_paid_copy_status',
     'Use Lost and Paid copy status',
     'coust', 'label'),
 oils_i18n_gettext('circ.use_lost_paid_copy_status',
     'Use Lost and Paid copy status when lost or long overdue billing is paid',
     'coust', 'description'),
 'bool');

COMMIT;
