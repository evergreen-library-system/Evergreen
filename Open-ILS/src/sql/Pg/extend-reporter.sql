/*
 * Copyright (C) 2008  Equinox Software, Inc.
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

DROP SCHEMA IF EXISTS extend_reporter CASCADE;

BEGIN;

CREATE SCHEMA extend_reporter;

CREATE TABLE extend_reporter.legacy_circ_count (
    id          BIGINT   PRIMARY KEY, --  REFERENCES asset.copy (id) DEFERRABLE INITIALLY DEFERRED, -- XXX could be an serial.issuance
    circ_count  INT         NOT NULL DEFAULT 0
);

CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
   SELECT cp.id,
   COALESCE((SELECT circ_count FROM extend_reporter.legacy_circ_count WHERE id = cp.id), 0)
   + (SELECT COUNT(*) FROM action.circulation WHERE target_copy = cp.id)
   + (SELECT COUNT(*) FROM action.aged_circulation WHERE target_copy = cp.id) AS circ_count
   FROM asset.copy cp;

CREATE OR REPLACE VIEW extend_reporter.global_bibs_by_holding_update AS
  SELECT DISTINCT ON (id) id, holding_update, update_type
    FROM (SELECT  b.id,
                  LAST(cp.create_date) AS holding_update,
                  'add' AS update_type
            FROM  biblio.record_entry b
                  JOIN asset.call_number cn ON (cn.record = b.id)
                  JOIN asset.copy cp ON (cp.call_number = cn.id)
            WHERE NOT cp.deleted
                  AND b.id > 0
            GROUP BY b.id
              UNION
          SELECT  b.id,
                  LAST(cp.edit_date) AS holding_update,
                  'delete' AS update_type
            FROM  biblio.record_entry b
                  JOIN asset.call_number cn ON (cn.record = b.id)
                  JOIN asset.copy cp ON (cp.call_number = cn.id)
            WHERE cp.deleted
                  AND b.id > 0
            GROUP BY b.id)x
    ORDER BY id, holding_update;

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
