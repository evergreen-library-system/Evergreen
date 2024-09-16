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

DROP SCHEMA IF EXISTS container CASCADE;

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
	description TEXT,
	pub		BOOL				NOT NULL DEFAULT FALSE,
	owning_lib	INT				REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
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
	target_copy	INT	NOT NULL,
    pos         INT,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX copy_bucket_item_bucket_idx ON container.copy_bucket_item (bucket);

CREATE OR REPLACE FUNCTION evergreen.container_copy_bucket_item_target_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.target_copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, target_copy:%s$$, NEW.target_copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER inherit_copy_bucket_item_target_copy_fkey
        AFTER UPDATE OR INSERT ON container.copy_bucket_item
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.container_copy_bucket_item_target_copy_inh_fkey();


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
	description TEXT,
	pub	BOOL	NOT NULL DEFAULT FALSE,
	owning_lib	INT				REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
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
	description TEXT,
	pub	BOOL	NOT NULL DEFAULT FALSE,
	owning_lib	INT				REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT breb_name_once_per_owner UNIQUE (owner,name,btype)
);

CREATE TABLE container.biblio_record_entry_bucket_shares (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    share_org   INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT brebs_org_once_per_bucket UNIQUE (bucket, share_org)
);

CREATE TYPE container.usr_flag_type AS ENUM ('favorite');
CREATE TABLE container.biblio_record_entry_bucket_usr_flags (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    usr         INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    flag        container.usr_flag_type NOT NULL DEFAULT 'favorite',
    CONSTRAINT brebs_flag_once_per_usr_per_bucket UNIQUE (bucket, usr, flag)
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
	target_biblio_record_entry	BIGINT	NOT NULL
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
	description TEXT,
	pub	BOOL	NOT NULL DEFAULT FALSE,
	owning_lib	INT				REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
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

CREATE TABLE container.carousel (
    id                      SERIAL PRIMARY KEY,
    type                    INTEGER NOT NULL REFERENCES config.carousel_type (id),
    owner                   INTEGER NOT NULL REFERENCES actor.org_unit (id),
    name                    TEXT NOT NULL,
    bucket                  INTEGER REFERENCES container.biblio_record_entry_bucket (id),
    creator                 INTEGER NOT NULL REFERENCES actor.usr (id),
    editor                  INTEGER NOT NULL REFERENCES actor.usr (id),
    create_time             TIMESTAMPTZ NOT NULL DEFAULT now(),
    edit_time               TIMESTAMPTZ NOT NULL DEFAULT now(),
    age_filter              INTERVAL,
    owning_lib_filter       INT[],
    copy_location_filter    INT[],
    last_refresh_time       TIMESTAMPTZ,
    active                  BOOLEAN NOT NULL DEFAULT TRUE,
    max_items               INTEGER NOT NULL
);

CREATE TABLE container.carousel_org_unit (
    id              SERIAL PRIMARY KEY,
    carousel        INTEGER NOT NULL REFERENCES container.carousel (id) ON DELETE CASCADE,
    override_name   TEXT,
    org_unit        INTEGER NOT NULL REFERENCES actor.org_unit (id),
    seq             INTEGER NOT NULL
);

COMMIT;
