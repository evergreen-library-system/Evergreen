-- The following DROP statements are outside of the transaction.
-- That way if one of the tables doesn't exist, the DROP will
-- fail but the rest of the script can still run.

DROP TABLE serial.bib_summary CASCADE;

DROP TABLE serial.index_summary CASCADE;

DROP TABLE serial.sup_summary CASCADE;

DROP TABLE serial.issuance CASCADE;

DROP TABLE serial.binding_unit CASCADE;

DROP TABLE serial.subscription CASCADE;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0288'); -- Scott McKellar

CREATE TABLE asset.copy_template (
	id             SERIAL   PRIMARY KEY,
	owning_lib     INT      NOT NULL
	                        REFERENCES actor.org_unit (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	creator        BIGINT   NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	editor         BIGINT   NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	create_date    TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	edit_date      TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	name           TEXT     NOT NULL,
	-- columns above this point are attributes of the template itself
	-- columns after this point are attributes of the copy this template modifies/creates
	circ_lib       INT      REFERENCES actor.org_unit (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	status         INT      REFERENCES config.copy_status (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	location       INT      REFERENCES asset.copy_location (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	loan_duration  INT      CONSTRAINT valid_loan_duration CHECK (
	                            loan_duration IS NULL OR loan_duration IN (1,2,3)),
	fine_level     INT      CONSTRAINT valid_fine_level CHECK (
	                            fine_level IS NULL OR loan_duration IN (1,2,3)),
	age_protect    INT,
	circulate      BOOL,
	deposit        BOOL,
	ref            BOOL,
	holdable       BOOL,
	deposit_amount NUMERIC(6,2),
	price          NUMERIC(8,2),
	circ_modifier  TEXT,
	circ_as_type   TEXT,
	alert_message  TEXT,
	opac_visible   BOOL,
	floating       BOOL,
	mint_condition BOOL
);

CREATE TABLE serial.subscription (
	id                     SERIAL       PRIMARY KEY,
	start_date             TIMESTAMP WITH TIME ZONE     NOT NULL,
	end_date               TIMESTAMP WITH TIME ZONE,    -- interpret NULL as current subscription
	record_entry           BIGINT       REFERENCES serial.record_entry (id)
	                                    ON DELETE SET NULL
	                                    DEFERRABLE INITIALLY DEFERRED,
	expected_date_offset   INTERVAL
	-- acquisitions/business-side tables link to here
);

--at least one distribution per org_unit holding issues
CREATE TABLE serial.distribution (
	id                    SERIAL  PRIMARY KEY,
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
