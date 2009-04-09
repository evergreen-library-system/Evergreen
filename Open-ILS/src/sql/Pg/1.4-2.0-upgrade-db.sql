/*
 * Copyright (C) 2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com.com>
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

------------------
/* Typos begone */
------------------

DROP INDEX asset.cp_tr_cp_idx;
ALTER TABLE asset.copy_tranparency_map RENAME COLUMN tansparency TO transparency;
ALTER TABLE asset.copy_tranparency_map RENAME TO copy_transparency_map;
CREATE INDEX cp_tr_cp_idx ON asset.copy_transparency_map (transparency);

COMMIT;
