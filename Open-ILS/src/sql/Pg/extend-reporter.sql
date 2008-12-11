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

DROP SCHEMA extend_reporter CASCADE;

BEGIN;

CREATE SCHEMA extend_reporter;

CREATE TABLE extend_reporter.legacy_circ_count (
    id          BIGINT   PRIMARY KEY REFERENCES asset.copy (id),
    circ_count  INT         NOT NULL DEFAULT 0
);

CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
 SELECT cp.id, COALESCE(sum(c.circ_count), 0::bigint) + COALESCE(count(circ.id), 0::bigint) AS circ_count
   FROM asset."copy" cp
   LEFT JOIN extend_reporter.legacy_circ_count c USING (id)
   LEFT JOIN "action".all_circulation circ ON circ.target_copy = cp.id
  GROUP BY cp.id;

CREATE OR REPLACE VIEW extend_reporter.global_bibs_by_holding_update AS
  SELECT id, LAST(holding_update) AS holding_update, update_type
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
    GROUP BY id, update_type;
        
COMMIT;

