

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
	last_xact_id	TEXT		NOT NULL
);
CREATE INDEX serial_record_entry_record_idx ON serial.record_entry ( record );
CREATE INDEX serial_record_entry_creator_idx ON serial.record_entry ( creator );
CREATE INDEX serial_record_entry_editor_idx ON serial.record_entry ( editor );
CREATE INDEX serial_record_entry_owning_lib_idx ON serial.record_entry ( owning_lib, deleted );
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_control_numbers();

CREATE RULE protect_mfhd_delete AS ON DELETE TO serial.record_entry DO INSTEAD UPDATE serial.record_entry SET deleted = true WHERE old.id = serial.record_entry.id RETURNING *;

CREATE TABLE serial.subscription (
	id                     SERIAL       PRIMARY KEY,
	owning_lib             INT          NOT NULL DEFAULT 1 REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	start_date             TIMESTAMP WITH TIME ZONE     NOT NULL,
	end_date               TIMESTAMP WITH TIME ZONE,    -- interpret NULL as current subscription
	record_entry           BIGINT       REFERENCES biblio.record_entry (id)
	                                    ON DELETE SET NULL
	                                    DEFERRABLE INITIALLY DEFERRED,
	expected_date_offset   INTERVAL
	-- acquisitions/business-side tables link to here
);
CREATE INDEX serial_subscription_record_idx ON serial.subscription (record_entry);
CREATE INDEX serial_subscription_owner_idx ON serial.subscription (owning_lib);

CREATE TABLE serial.subscription_note (
	id           SERIAL PRIMARY KEY,
	subscription INT    NOT NULL
	                    REFERENCES serial.subscription (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator      INT    NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
	pub          BOOL   NOT NULL DEFAULT FALSE,
	alert        BOOL   NOT NULL DEFAULT FALSE,
	title        TEXT   NOT NULL,
	value        TEXT   NOT NULL
);
CREATE INDEX serial_subscription_note_sub_idx ON serial.subscription_note (subscription);

CREATE TABLE serial.caption_and_pattern (
	id           SERIAL       PRIMARY KEY,
	subscription INT          NOT NULL
	                          REFERENCES serial.subscription (id)
	                          ON DELETE CASCADE
	                          DEFERRABLE INITIALLY DEFERRED,
	type         TEXT         NOT NULL
	                          CONSTRAINT cap_type CHECK ( type in
	                          ( 'basic', 'supplement', 'index' )),
	create_date  TIMESTAMPTZ  NOT NULL DEFAULT now(),
	start_date   TIMESTAMPTZ  NOT NULL DEFAULT now(),
	end_date     TIMESTAMPTZ,
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
CREATE INDEX serial_caption_and_pattern_sub_idx ON serial.caption_and_pattern (subscription);

--at least one distribution per org_unit holding issues
CREATE TABLE serial.distribution (
	id                    SERIAL  PRIMARY KEY,
	record_entry          BIGINT  REFERENCES serial.record_entry (id)
								  ON DELETE SET NULL
								  DEFERRABLE INITIALLY DEFERRED,
	summary_method        TEXT    CONSTRAINT sdist_summary_method_check
	                              CHECK (summary_method IS NULL
	                              OR summary_method IN ( 'add_to_sre',
	                              'merge_with_sre', 'use_sre_only',
	                              'use_sdist_only')),
	subscription          INT     NOT NULL
	                              REFERENCES serial.subscription (id)
								  ON DELETE CASCADE
								  DEFERRABLE INITIALLY DEFERRED,
	holding_lib           INT     NOT NULL
	                              REFERENCES actor.org_unit (id)
								  DEFERRABLE INITIALLY DEFERRED,
	label                 TEXT    NOT NULL,
	display_grouping      TEXT    NOT NULL DEFAULT 'chron'
	                              CHECK (display_grouping IN ('enum', 'chron')),
	receive_call_number   BIGINT  REFERENCES asset.call_number (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	receive_unit_template INT     REFERENCES asset.copy_template (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	bind_call_number      BIGINT  REFERENCES asset.call_number (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	bind_unit_template    INT     REFERENCES asset.copy_template (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	unit_label_prefix     TEXT,
	unit_label_suffix     TEXT
);
CREATE UNIQUE INDEX one_dist_per_sre_idx ON serial.distribution (record_entry);
CREATE INDEX serial_distribution_sub_idx ON serial.distribution (subscription);
CREATE INDEX serial_distribution_holding_lib_idx ON serial.distribution (holding_lib);

CREATE TABLE serial.distribution_note (
	id           SERIAL PRIMARY KEY,
	distribution INT    NOT NULL
	                    REFERENCES serial.distribution (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator      INT    NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
	pub          BOOL   NOT NULL DEFAULT FALSE,
	alert        BOOL   NOT NULL DEFAULT FALSE,
	title        TEXT   NOT NULL,
	value        TEXT   NOT NULL
);
CREATE INDEX serial_distribution_note_dist_idx ON serial.distribution_note (distribution);

CREATE TABLE serial.stream (
	id              SERIAL  PRIMARY KEY,
	distribution    INT     NOT NULL
	                        REFERENCES serial.distribution (id)
	                        ON DELETE CASCADE
	                        DEFERRABLE INITIALLY DEFERRED,
	routing_label   TEXT
);
CREATE INDEX serial_stream_dist_idx ON serial.stream (distribution);

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
CREATE INDEX serial_routing_list_user_stream_idx ON serial.routing_list_user (stream);
CREATE INDEX serial_routing_list_user_reader_idx ON serial.routing_list_user (reader);

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
	caption_and_pattern INT   REFERENCES serial.caption_and_pattern (id)
                              ON DELETE CASCADE
	                          DEFERRABLE INITIALLY DEFERRED,
	holding_code    TEXT      CONSTRAINT issuance_holding_code_check CHECK (
	                            holding_code IS NULL OR could_be_serial_holding_code(holding_code)
	                          ),
	holding_type    TEXT      CONSTRAINT valid_holding_type CHECK
	                          (
	                              holding_type IS NULL
	                              OR holding_type IN ('basic','supplement','index')
	                          ),
	holding_link_id INT -- probably defunct
	-- TODO: add columns for separate enumeration/chronology values
);
ALTER TABLE serial.issuance ADD CHECK (holding_code IS NULL OR evergreen.is_json(holding_code));
CREATE INDEX serial_issuance_sub_idx ON serial.issuance (subscription);
CREATE INDEX serial_issuance_caption_and_pattern_idx ON serial.issuance (caption_and_pattern);
CREATE INDEX serial_issuance_date_published_idx ON serial.issuance (date_published);

CREATE TABLE serial.unit (
	sort_key          TEXT,
	detailed_contents TEXT    NOT NULL,
	summary_contents  TEXT    NOT NULL
) INHERITS (asset.copy);
ALTER TABLE serial.unit ADD PRIMARY KEY (id);
CREATE UNIQUE INDEX unit_barcode_key ON serial.unit (barcode) WHERE deleted = FALSE OR deleted IS FALSE;
CREATE INDEX unit_cn_idx ON serial.unit (call_number);
CREATE INDEX unit_avail_cn_idx ON serial.unit (call_number);
CREATE INDEX unit_creator_idx  ON serial.unit ( creator );
CREATE INDEX unit_editor_idx   ON serial.unit ( editor );
CREATE INDEX unit_extant_by_circ_lib_idx ON serial.unit(circ_lib) WHERE deleted = FALSE OR deleted IS FALSE;

-- must create this rule explicitly; it is not inherited from asset.copy
CREATE RULE protect_serial_unit_delete AS ON DELETE TO serial.unit DO INSTEAD UPDATE serial.unit SET deleted = TRUE WHERE OLD.id = serial.unit.id RETURNING *;

-- must create this trigger explicitly; it is not inherited from asset.copy
CREATE TRIGGER autogenerate_placeholder_barcode
   BEFORE INSERT OR UPDATE ON serial.unit 
   FOR EACH ROW EXECUTE PROCEDURE asset.autogenerate_placeholder_barcode()
;

-- must create this trigger explicitly; it is not inherited from asset.copy
CREATE TRIGGER sunit_status_changed_trig
    BEFORE UPDATE ON serial.unit
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_status_changed();

-- ditto
CREATE TRIGGER sunit_created_trig
    BEFORE INSERT ON serial.unit
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_created();

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
	date_received   TIMESTAMP WITH TIME ZONE,
	status          TEXT    CONSTRAINT valid_status CHECK
	                        (
	                            status IN ('Bindery', 'Bound', 'Claimed', 'Discarded', 'Expected', 'Not Held', 'Not Published', 'Received')
	                        ) DEFAULT 'Expected',
	shadowed        BOOL    NOT NULL DEFAULT FALSE -- ignore when generating summaries/labels
);
CREATE INDEX serial_item_stream_idx ON serial.item (stream);
CREATE INDEX serial_item_issuance_idx ON serial.item (issuance);
CREATE INDEX serial_item_unit_idx ON serial.item (unit);
CREATE INDEX serial_item_uri_idx ON serial.item (uri);
CREATE INDEX serial_item_date_received_idx ON serial.item (date_received);
CREATE INDEX serial_item_status_idx ON serial.item (status);

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
	alert       BOOL    NOT NULL    DEFAULT FALSE,
	title       TEXT    NOT NULL,
	value       TEXT    NOT NULL
);
CREATE INDEX serial_item_note_item_idx ON serial.item_note (item);

CREATE TABLE serial.basic_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT,
	show_generated      BOOL    NOT NULL DEFAULT TRUE
);
CREATE INDEX serial_basic_summary_dist_idx ON serial.basic_summary (distribution);

CREATE TABLE serial.supplement_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT,
	show_generated      BOOL    NOT NULL DEFAULT TRUE
);
CREATE INDEX serial_supplement_summary_dist_idx ON serial.supplement_summary (distribution);

CREATE TABLE serial.index_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT,
	show_generated      BOOL    NOT NULL DEFAULT TRUE
);
CREATE INDEX serial_index_summary_dist_idx ON serial.index_summary (distribution);

CREATE VIEW serial.any_summary AS
    SELECT
        'basic' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.basic_summary
    UNION
    SELECT
        'index' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.index_summary
    UNION
    SELECT
        'supplement' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.supplement_summary ;


CREATE TABLE serial.materialized_holding_code (
    id BIGSERIAL PRIMARY KEY,
    issuance INTEGER NOT NULL REFERENCES serial.issuance (id) ON DELETE CASCADE,
    subfield CHAR,
    value TEXT
);

CREATE OR REPLACE FUNCTION serial.materialize_holding_code() RETURNS TRIGGER
AS $func$ 
use strict;

use MARC::Field;
use JSON::XS;

if (not defined $_TD->{new}{holding_code}) {
    elog(WARNING, 'NULL in "holding_code" column of serial.issuance allowed for now, but may not be useful');
    return;
}

# Do nothing if holding_code has not changed...

if ($_TD->{new}{holding_code} eq $_TD->{old}{holding_code}) {
    # ... unless the following internal flag is set.

    my $flag_rv = spi_exec_query(q{
        SELECT * FROM config.internal_flag
        WHERE name = 'serial.rematerialize_on_same_holding_code' AND enabled
    }, 1);
    return unless $flag_rv->{processed};
}


my $holding_code = (new JSON::XS)->decode($_TD->{new}{holding_code});

my $field = new MARC::Field('999', @$holding_code); # tag doesnt matter

my $dstmt = spi_prepare(
    'DELETE FROM serial.materialized_holding_code WHERE issuance = $1',
    'INT'
);
spi_exec_prepared($dstmt, $_TD->{new}{id});

my $istmt = spi_prepare(
    q{
        INSERT INTO serial.materialized_holding_code (
            issuance, subfield, value
        ) VALUES ($1, $2, $3)
    }, qw{INT CHAR TEXT}
);

foreach ($field->subfields) {
    spi_exec_prepared(
        $istmt,
        $_TD->{new}{id},
        $_->[0],
        $_->[1]
    );
}

return;

$func$ LANGUAGE 'plperlu';

CREATE INDEX assist_holdings_display
    ON serial.materialized_holding_code (issuance, subfield);

CREATE TRIGGER materialize_holding_code
    AFTER INSERT OR UPDATE ON serial.issuance
    FOR EACH ROW EXECUTE PROCEDURE serial.materialize_holding_code() ;

CREATE TABLE serial.pattern_template (
    id            SERIAL PRIMARY KEY,
    name          TEXT NOT NULL,
    pattern_code  TEXT NOT NULL,
    owning_lib    INTEGER REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
    share_depth   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX serial_pattern_template_name_idx ON serial.pattern_template (evergreen.lowercase(name));

CREATE OR REPLACE FUNCTION serial.pattern_templates_visible_to(org_unit INT) RETURNS SETOF serial.pattern_template AS $func$
BEGIN
    RETURN QUERY SELECT *
           FROM serial.pattern_template spt
           WHERE (
             SELECT ARRAY_AGG(id)
             FROM actor.org_unit_descendants(spt.owning_lib, spt.share_depth)
           ) @@ org_unit::TEXT::QUERY_INT;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

