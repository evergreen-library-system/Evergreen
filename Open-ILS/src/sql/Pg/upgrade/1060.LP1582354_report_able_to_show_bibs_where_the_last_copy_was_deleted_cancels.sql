BEGIN;

SELECT evergreen.upgrade_deps_block_check('1060', :eg_version);

DROP VIEW IF EXISTS extend_reporter.copy_count_per_org;


CREATE OR REPLACE VIEW extend_reporter.copy_count_per_org AS
 SELECT acn.record AS bibid,
    ac.circ_lib,
    acn.owning_lib,
    max(ac.edit_date) AS last_edit_time,
    min(ac.deleted::integer) AS has_only_deleted_copies,
    count(
        CASE
            WHEN ac.deleted THEN ac.id
            ELSE NULL::bigint
        END) AS deleted_count,
    count(
        CASE
            WHEN NOT ac.deleted THEN ac.id
            ELSE NULL::bigint
        END) AS visible_count,
    count(*) AS total_count
   FROM asset.call_number acn,
    asset.copy ac
  WHERE ac.call_number = acn.id
  GROUP BY acn.record, acn.owning_lib, ac.circ_lib;


COMMIT;
