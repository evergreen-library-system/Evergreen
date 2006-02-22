DROP SCHEMA container CASCADE;

BEGIN;
CREATE SCHEMA container;

CREATE TABLE container.copy_bucket (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL
							REFERENCES actor.usr (id)
								ON DELETE CASCADE
								ON UPDATE CASCADE
								DEFERRABLE
								INITIALLY DEFERRED,
	name		TEXT				NOT NULL,
	btype		TEXT				NOT NULL DEFAULT 'misc',
	pub		BOOL				NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT cb_name_once_per_owner UNIQUE (owner,name,btype)
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
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
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
	btype	TEXT	NOT NULL DEFAULT 'misc',
	pub	BOOL	NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT cnb_name_once_per_owner UNIQUE (owner,name,btype)
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
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
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
	btype	TEXT	NOT NULL DEFAULT 'misc',
	pub	BOOL	NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT breb_name_once_per_owner UNIQUE (owner,name,btype)
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
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
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
	btype	TEXT	NOT NULL DEFAULT 'misc',
	pub	BOOL	NOT NULL DEFAULT FALSE,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT ub_name_once_per_owner UNIQUE (owner,name,btype)
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
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);

COMMIT;
