/*
 * Copyright (C) 2014  Equinox Software, Inc.
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

SELECT evergreen.upgrade_deps_block_check('0870', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.located_uris (
    bibid BIGINT[],
    ouid INT,
    pref_lib INT DEFAULT NULL
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank INT) AS $$
    WITH all_orgs AS (SELECT COALESCE( enabled, FALSE ) AS flag FROM config.global_flag WHERE name = 'opac.located_uri.act_as_copy')
    SELECT DISTINCT ON (id) * FROM (
    SELECT acn.id, COALESCE(aou.name,aoud.name), acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( COALESCE($3, $2) ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( COALESCE($3, $2) ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR (all_orgs.flag AND COALESCE(aou.id,aoud.id) IS NOT NULL))
    UNION
    SELECT acn.id, COALESCE(aou.name,aoud.name) AS name, acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( $2 ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( $2 ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR (all_orgs.flag AND COALESCE(aou.id,aoud.id) IS NOT NULL)))x
    ORDER BY id, pref_ou DESC;
$$
LANGUAGE SQL STABLE;

COMMIT;

