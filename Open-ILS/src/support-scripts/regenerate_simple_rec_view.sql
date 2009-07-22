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

--
-- This implements a fix, for now, for an ingest issue seemingly
-- caused by atomicity issues in the simple_record_update trigger.
--
-- Set this up to be run by cron on a regular basis -- daily or hourly,
-- depending on your reporting requirements -- in order to refresh the
-- Simple Record Extracts reporting source.
--

BEGIN;

SELECT reporter.enable_materialized_simple_record_trigger();
SELECT reporter.disable_materialized_simple_record_trigger(); 

COMMIT;

