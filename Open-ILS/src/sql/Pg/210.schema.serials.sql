

DROP SCHEMA IF EXISTS serial CASCADE;

BEGIN;

CREATE SCHEMA serial;

CREATE TABLE serial.record_entry (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		REFERENCES biblio.record_entry (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	owning_lib	INT		NOT NULL DEFAULT 1 REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	creator		INT		NOT NULL DEFAULT 1,
	editor		INT		NOT NULL DEFAULT 1,
	source		INT,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	active		BOOL		NOT NULL DEFAULT TRUE,
	deleted		BOOL		NOT NULL DEFAULT FALSE,
	marc		TEXT,
	last_xact_id	TEXT		NOT NULL,
	owner		INT
);
CREATE INDEX serial_record_entry_creator_idx ON serial.record_entry ( creator );
CREATE INDEX serial_record_entry_editor_idx ON serial.record_entry ( editor );
CREATE INDEX serial_record_entry_owning_lib_idx ON serial.record_entry ( owning_lib, deleted );
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_901();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_control_numbers();

CREATE RULE protect_mfhd_delete AS ON DELETE TO serial.record_entry DO INSTEAD UPDATE serial.record_entry SET deleted = true WHERE old.id = serial.record_entry.id;

CREATE TABLE serial.subscription (
	id                     SERIAL       PRIMARY KEY,
	owning_lib             INT     NOT NULL DEFAULT 1 REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	start_date             TIMESTAMP WITH TIME ZONE     NOT NULL,
	end_date               TIMESTAMP WITH TIME ZONE,    -- interpret NULL as current subscription
	record_entry           BIGINT       REFERENCES biblio.record_entry (id)
	                                    ON DELETE SET NULL
	                                    DEFERRABLE INITIALLY DEFERRED,
	expected_date_offset   INTERVAL
	-- acquisitions/business-side tables link to here
);


CREATE TABLE serial.caption_and_pattern (
	id           SERIAL       PRIMARY KEY,
	subscription INT          NOT NULL
	                          REFERENCES serial.subscription (id)
	                          ON DELETE CASCADE
	                          DEFERRABLE INITIALLY DEFERRED,
	type         TEXT         NOT NULL
	                          CONSTRAINT cap_type CHECK ( type in
	                          ( 'basic', 'supplement', 'index' )),
	create_time  TIMESTAMPTZ  NOT NULL DEFAULT now(),
	active       BOOL         NOT NULL DEFAULT FALSE,
	pattern_code TEXT         NOT NULL,       -- must contain JSON
	enum_1       TEXT,
	enum_2       TEXT,
	enum_3       TEXT,
	enum_4       TEXT,
	enum_5       TEXT,
	enum_6       TEXT,
	chron_1      TEXT,
	chron_2      TEXT,
	chron_3      TEXT,
	chron_4      TEXT,
	chron_5      TEXT
);

--at least one distribution per org_unit holding issues
CREATE TABLE serial.distribution (
	id                    SERIAL  PRIMARY KEY,
	record_entry          BIGINT  REFERENCES serial.record_entry (id)
								  ON DELETE SET NULL
								  DEFERRABLE INITIALLY DEFERRED,
	subscription          INT     NOT NULL
	                              REFERENCES serial.subscription (id)
								  ON DELETE CASCADE
								  DEFERRABLE INITIALLY DEFERRED,
	holding_lib           INT     NOT NULL
	                              REFERENCES actor.org_unit (id)
								  DEFERRABLE INITIALLY DEFERRED,
	label                 TEXT    NOT NULL,
	receive_call_number   BIGINT  REFERENCES asset.call_number (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	receive_unit_template INT     REFERENCES asset.copy_template (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	bind_call_number      BIGINT  REFERENCES asset.call_number (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	bind_unit_template    INT     REFERENCES asset.copy_template (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	unit_label_base       TEXT,
	unit_label_suffix     TEXT
);
CREATE UNIQUE INDEX one_dist_per_sre_idx ON serial.distribution (record_entry);

CREATE TABLE serial.stream (
	id              SERIAL  PRIMARY KEY,
	distribution    INT     NOT NULL
	                        REFERENCES serial.distribution (id)
	                        ON DELETE CASCADE
	                        DEFERRABLE INITIALLY DEFERRED,
	routing_label   TEXT
);

CREATE UNIQUE INDEX label_once_per_dist
	ON serial.stream (distribution, routing_label)
	WHERE routing_label IS NOT NULL;

CREATE TABLE serial.routing_list_user (
	id             SERIAL       PRIMARY KEY,
	stream         INT          NOT NULL
	                            REFERENCES serial.stream
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	pos            INT          NOT NULL DEFAULT 1,
	reader         INT          REFERENCES actor.usr
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	department     TEXT,
	note           TEXT,
	CONSTRAINT one_pos_per_routing_list UNIQUE ( stream, pos ),
	CONSTRAINT reader_or_dept CHECK
	(
	    -- Recipient is a person or a department, but not both
		(reader IS NOT NULL AND department IS NULL) OR
		(reader IS NULL AND department IS NOT NULL)
	)
);

CREATE TABLE serial.issuance (
	id              SERIAL    PRIMARY KEY,
	creator         INT       NOT NULL
	                          REFERENCES actor.usr (id)
							  DEFERRABLE INITIALLY DEFERRED,
	editor          INT       NOT NULL
	                          REFERENCES actor.usr (id)
	                          DEFERRABLE INITIALLY DEFERRED,
	create_date     TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	edit_date       TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	subscription    INT       NOT NULL
	                          REFERENCES serial.subscription (id)
	                          ON DELETE CASCADE
	                          DEFERRABLE INITIALLY DEFERRED,
	label           TEXT,
	date_published  TIMESTAMP WITH TIME ZONE,
	holding_code    TEXT,
	holding_type    TEXT      CONSTRAINT valid_holding_type CHECK
	                          (
	                              holding_type IS NULL
	                              OR holding_type IN ('basic','supplement','index')
	                          ),
	holding_link_id INT
	-- TODO: add columns for separate enumeration/chronology values
);

CREATE TABLE serial.unit (
	label           TEXT,
	label_sort_key  TEXT,
	contents        TEXT    NOT NULL
) INHERITS (asset.copy);

ALTER TABLE serial.unit ADD PRIMARY KEY (id);

-- must create this rule explicitly; it is not inherited from asset.copy
CREATE RULE protect_serial_unit_delete AS ON DELETE TO serial.unit DO INSTEAD UPDATE serial.unit SET deleted = TRUE WHERE OLD.id = serial.unit.id;

CREATE TABLE serial.item (
	id              SERIAL  PRIMARY KEY,
	creator         INT     NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	editor          INT     NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	create_date     TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	edit_date       TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	issuance        INT     NOT NULL
	                        REFERENCES serial.issuance (id)
	                        ON DELETE CASCADE
	                        DEFERRABLE INITIALLY DEFERRED,
	stream          INT     NOT NULL
	                        REFERENCES serial.stream (id)
	                        ON DELETE CASCADE
	                        DEFERRABLE INITIALLY DEFERRED,
	unit            INT     REFERENCES serial.unit (id)
	                        ON DELETE SET NULL
	                        DEFERRABLE INITIALLY DEFERRED,
	uri             INT     REFERENCES asset.uri (id)
	                        ON DELETE SET NULL
	                        DEFERRABLE INITIALLY DEFERRED,
	date_expected   TIMESTAMP WITH TIME ZONE,
	date_received   TIMESTAMP WITH TIME ZONE
);

CREATE TABLE serial.item_note (
	id          SERIAL  PRIMARY KEY,
	item        INT     NOT NULL
	                    REFERENCES serial.item (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator     INT     NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	pub         BOOL    NOT NULL    DEFAULT FALSE,
	title       TEXT    NOT NULL,
	value       TEXT    NOT NULL
);

CREATE TABLE serial.bib_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT
);

CREATE TABLE serial.sup_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT
);

CREATE TABLE serial.index_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT
);

COMMIT;
