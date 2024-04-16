BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE actor.org_unit
	ADD COLUMN staff_catalog_visible BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE actor.org_unit
    SET staff_catalog_visible=opac_visible;

CREATE OR REPLACE FUNCTION asset.staff_ou_record_copy_count(org integer, rid bigint)
 RETURNS TABLE(depth integer, org_unit integer, visible bigint, available bigint, unshadow bigint, transcendant integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) WHERE staff_catalog_visible LOOP
        RETURN QUERY
        WITH available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
            cp AS(
                SELECT  cp.id,
                        (cp.status = ANY (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                  FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
            ),
            peer AS (
                select  cp.id,
                        (cp.status = ANY  (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN biblio.peer_bib_copy_map bp ON (bp.peer_record = rid AND bp.target_copy = cp.id)
            )
        select ans.depth, ans.id, count(id), sum(x.available::int), sum(x.opac_visible::int), trans
        from ((select * from cp) union (select * from peer)) x
        group by 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;
    RETURN;
END;
$function$;


INSERT INTO config.global_flag (name, enabled, label)
    VALUES (
        'staff.search.shelving_location_groups_with_orgs', TRUE,
        oils_i18n_gettext(
            'staff.search.shelving_location_groups_with_orgs',
            'Staff Catalog Search: Display shelving location groups inside the Organizational Unit Selector',
            'cgf',
            'label'
        )
);

COMMIT;
