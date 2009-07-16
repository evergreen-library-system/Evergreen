/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
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

DROP SCHEMA container CASCADE;

BEGIN;
CREATE SCHEMA container;

CREATE TABLE container.copy_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);

CREATE TABLE container.copy_bucket (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL
							REFERENCES actor.usr (id)
								ON DELETE CASCADE
								ON UPDATE CASCADE
								DEFERRABLE
								INITIALLY DEFERRED,
	name		TEXT				NOT NULL,
	btype		TEXT				NOT NULL DEFAULT 'misc' REFERENCES container.copy_bucket_type (code) DEFERRABLE INITIALLY DEFERRED,
	pub		BOOL				NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT cb_name_once_per_owner UNIQUE (owner,name,btype)
);

CREATE TABLE container.copy_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.copy_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

CREATE TABLE container.copy_bucket_item (
	id		SERIAL	PRIMARY KEY,
	bucket		INT	NOT NULL
				REFERENCES container.copy_bucket (id)
					ON DELETE CASCADE
					ON UPDATE CASCADE
					DEFERRABLE
					INITIALLY DEFERRED,
	target_copy	INT	NOT NULL
				REFERENCES asset."copy" (id)
					ON DELETE CASCADE
					ON UPDATE CASCADE
					DEFERRABLE
					INITIALLY DEFERRED,
    pos         INT,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX copy_bucket_item_bucket_idx ON container.copy_bucket_item (bucket);

CREATE TABLE container.copy_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.copy_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);



CREATE TABLE container.call_number_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);

CREATE TABLE container.call_number_bucket (
	id	SERIAL	PRIMARY KEY,
	owner	INT	NOT NULL
			REFERENCES actor.usr (id)
				ON DELETE CASCADE
				ON UPDATE CASCADE
				DEFERRABLE
				INITIALLY DEFERRED,
	name	TEXT	NOT NULL,
	btype	TEXT	NOT NULL DEFAULT 'misc' REFERENCES container.call_number_bucket_type (code) DEFERRABLE INITIALLY DEFERRED,
	pub	BOOL	NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT cnb_name_once_per_owner UNIQUE (owner,name,btype)
);

CREATE TABLE container.call_number_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.call_number_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

CREATE TABLE container.call_number_bucket_item (
	id		SERIAL	PRIMARY KEY,
	bucket		INT	NOT NULL
				REFERENCES container.call_number_bucket (id)
					ON DELETE CASCADE
					ON UPDATE CASCADE
					DEFERRABLE
					INITIALLY DEFERRED,
	target_call_number	INT	NOT NULL
				REFERENCES asset.call_number (id)
					ON DELETE CASCADE
					ON UPDATE CASCADE
					DEFERRABLE
					INITIALLY DEFERRED,
    pos         INT,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);

CREATE TABLE container.call_number_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.call_number_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);




CREATE TABLE container.biblio_record_entry_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);


CREATE TABLE container.biblio_record_entry_bucket (
	id	SERIAL	PRIMARY KEY,
	owner	INT	NOT NULL
			REFERENCES actor.usr (id)
				ON DELETE CASCADE
				ON UPDATE CASCADE
				DEFERRABLE
				INITIALLY DEFERRED,
	name	TEXT	NOT NULL,
	btype	TEXT	NOT NULL DEFAULT 'misc' REFERENCES container.biblio_record_entry_bucket_type (code) DEFERRABLE INITIALLY DEFERRED,
	pub	BOOL	NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT breb_name_once_per_owner UNIQUE (owner,name,btype)
);

CREATE TABLE container.biblio_record_entry_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

CREATE TABLE container.biblio_record_entry_bucket_item (
	id				SERIAL	PRIMARY KEY,
	bucket				INT	NOT NULL
						REFERENCES container.biblio_record_entry_bucket (id)
							ON DELETE CASCADE
							ON UPDATE CASCADE
							DEFERRABLE
							INITIALLY DEFERRED,
	target_biblio_record_entry	INT	NOT NULL
						REFERENCES biblio.record_entry (id)
							ON DELETE CASCADE
							ON UPDATE CASCADE
							DEFERRABLE
							INITIALLY DEFERRED,
    pos         INT,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);

CREATE TABLE container.biblio_record_entry_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.biblio_record_entry_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);



CREATE TABLE container.user_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);

CREATE TABLE container.user_bucket (
	id	SERIAL	PRIMARY KEY,
	owner	INT	NOT NULL
			REFERENCES actor.usr (id)
				ON DELETE CASCADE
				ON UPDATE CASCADE
				DEFERRABLE
				INITIALLY DEFERRED,
	name	TEXT	NOT NULL,
	btype	TEXT	NOT NULL DEFAULT 'misc' REFERENCES container.user_bucket_type (code) DEFERRABLE INITIALLY DEFERRED,
	pub	BOOL	NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT ub_name_once_per_owner UNIQUE (owner,name,btype)
);

CREATE TABLE container.user_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.user_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

CREATE TABLE container.user_bucket_item (
	id		SERIAL	PRIMARY KEY,
	bucket		INT	NOT NULL
				REFERENCES container.user_bucket (id)
					ON DELETE CASCADE
					ON UPDATE CASCADE
					DEFERRABLE
					INITIALLY DEFERRED,
	target_user	INT	NOT NULL
				REFERENCES actor.usr (id)
					ON DELETE CASCADE
					ON UPDATE CASCADE
					DEFERRABLE
					INITIALLY DEFERRED,
    pos         INT,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX user_bucket_item_target_user_idx ON container.user_bucket_item ( target_user );

CREATE TABLE container.user_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.user_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);


COMMIT;
