/*
 * Copyright (C) 2009  Equinox Software, Inc.
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


INSERT INTO config.upgrade_log (version) VALUES ('1.4.0.8');

CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DECLARE x RECORD;
    BEGIN
        -- DROP TRIGGER IF EXISTS is only available starting with PostgreSQL 8.2
        FOR x IN SELECT tgname FROM pg_trigger WHERE tgname = 'zzz_update_materialized_simple_record_tgr'
        LOOP
            DROP TRIGGER zzz_update_materialized_simple_record_tgr ON metabib.real_full_rec;
        END LOOP;
    END;
$$ LANGUAGE plpgsql;

