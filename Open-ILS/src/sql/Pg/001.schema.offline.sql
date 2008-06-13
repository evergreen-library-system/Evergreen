/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
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


DROP SCHEMA offline CASCADE;

BEGIN;

CREATE SCHEMA offline;

CREATE TABLE offline.script (
	id		SERIAL PRIMARY KEY,
	session		TEXT    NOT NULL,
	requestor	INTEGER NOT NULL,
	create_time	INTEGER NOT NULL,
	workstation	TEXT    NOT NULL,
	logfile		TEXT    NOT NULL,
	time_delta	INTEGER NOT NULL DEFAULT 0,
	count		INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX offline_script_pkey ON offline.script (id);
CREATE INDEX offline_script_ws ON offline.script (workstation);
CREATE INDEX offline_script_session ON offline.script (session);


CREATE TABLE offline.session (
	key		TEXT    PRIMARY KEY,
	org		INTEGER NOT NULL,
	description	TEXT,
	creator		INTEGER NOT NULL,
	create_time	INTEGER NOT NULL,
	in_process	INTEGER NOT NULL DEFAULT 0,
	start_time	INTEGER,
	end_time	INTEGER,
	num_complete	INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX offline_session_pkey ON offline.session (key);
CREATE INDEX offline_session_org ON offline.session (org);
CREATE INDEX offline_session_creation ON offline.session (create_time);

COMMIT;

