DROP SCHEMA circ_stats CASCADE;

BEGIN;

CREATE SCHEMA circ_stats;

CREATE TABLE circ_stats.circulation (
    id			BIGSERIAL			PRIMARY KEY,
    target_copy		BIGINT				NOT NULL,
    usr			INT				NOT NULL,
    circ_lib		INT				NOT NULL,
    renewal_remaining	INT				NOT NULL,
    circ_staff		INT,
    checkin_staff	INT,
    checkin_lib		INT,
    xact_start		TIMESTAMP WITH TIME ZONE	NOT NULL,
    xact_finish		TIMESTAMP WITH TIME ZONE,
    due_date		TIMESTAMP WITH TIME ZONE	NOT NULL,
    stop_fines_time	TIMESTAMP WITH TIME ZONE,
    checkin_time	TIMESTAMP WITH TIME ZONE,
    duration		INTERVAL			NOT NULL,
    fine_interval	INTERVAL			NOT NULL,
    recuring_fine	NUMERIC(6,2)			NOT NULL,
    max_fine		NUMERIC(6,2)			NOT NULL,
    opac_renewal	BOOL				NOT NULL,
    phone_renewal	BOOL				NOT NULL,
    desk_renewal	BOOL				NOT NULL,
    duration_rule	TEXT				NOT NULL,
    recuring_fine_rule	TEXT				NOT NULL,
    max_fine_rule	TEXT				NOT NULL,
    stop_fines		TEXT
) WITHOUT OIDS;

CREATE TABLE circ_stats.circulation_checkin () INHERITS (circ_stats.circulation);
CREATE TABLE circ_stats.circulation_claimsreturned () INHERITS (circ_stats.circulation);
CREATE TABLE circ_stats.circulation_lost () INHERITS (circ_stats.circulation);
CREATE TABLE circ_stats.circulation_maxfines () INHERITS (circ_stats.circulation);
CREATE TABLE circ_stats.circulation_renew () INHERITS (circ_stats.circulation);


CREATE TABLE circ_stats.record_dim (
	id			BIGSERIAL	PRIMARY KEY,
	bib_item_type		TEXT	NOT NULL DEFAULT '?',
	bib_item_form		TEXT	NOT NULL DEFAULT '?',
	bib_level		TEXT	NOT NULL DEFAULT '?',
	bib_control_type	TEXT	NOT NULL DEFAULT '?',
	bib_char_encoding	TEXT	NOT NULL DEFAULT '?',
	bib_enc_level		TEXT	NOT NULL DEFAULT '?',
	bib_audience		TEXT	NOT NULL DEFAULT '?',
	bib_cat_form		TEXT	NOT NULL DEFAULT '?',
	bib_pub_status		TEXT	NOT NULL DEFAULT '?',
	bib_pub_date		TEXT	NOT NULL DEFAULT '?',
	bib_item_lang		TEXT	NOT NULL DEFAULT '?',
	bib_title		TEXT	NOT NULL DEFAULT '?',
	bib_author		TEXT	NOT NULL DEFAULT '?'
) WITHOUT OIDS;
CREATE TRIGGER circ_stats_record_dim_id_trigger
	BEFORE INSERT ON circ_stats.record_dim
	FOR EACH ROW
	EXECUTE PROCEDURE dim_row_hash ();

CREATE TABLE circ_stats.usr_dim (
	id			BIGSERIAL	PRIMARY KEY,
	usr_id			INT	NOT NULL DEFAULT 0,
	usr_grp			INT	NOT NULL, -- aka profile
	usr_standing		INT	NOT NULL,
	usr_home_ou		INT	NOT NULL,
	usr_county		TEXT,
	usr_city		TEXT,
	usr_post_code		TEXT	NOT NULL
) WITHOUT OIDS;
CREATE TRIGGER circ_stats_usr_dim_id_trigger
	BEFORE INSERT ON circ_stats.usr_dim
	FOR EACH ROW
	EXECUTE PROCEDURE dim_row_hash ();


CREATE TABLE circ_stats.copy_dim (
	id			BIGSERIAL	PRIMARY KEY,
	copy_holdable		BOOL	NOT NULL,
	copy_ref		BOOL	NOT NULL,
	copy_circulate		BOOL	NOT NULL,
	copy_opac_visible	BOOL	NOT NULL,
	copy_circ_lib		INT	NOT NULL,
	copy_location		INT	NOT NULL,
	copy_fine_level		INT	NOT NULL,
	copy_loan_duration	INT	NOT NULL,
	copy_circ_modifer	TEXT,
	copy_circ_as_type	TEXT,
	copy_call_number_label	TEXT	NOT NULL
) WITHOUT OIDS;
CREATE TRIGGER circ_stats_copy_dim_id_trigger
	BEFORE INSERT ON circ_stats.copy_dim
	FOR EACH ROW
	EXECUTE PROCEDURE dim_row_hash ();


CREATE TABLE circ_stats.circ_dim (
	id			BIGSERIAL				PRIMARY KEY,
	circ_opac_renewal	BOOL,
	circ_desk_renewal	BOOL,
	circ_phone_renewal	BOOL,
	circ_self_checkout	BOOL,
	circ_recuring_fine	NUMERIC(6,2)			NOT NULL,
	circ_max_fine		NUMERIC(6,2)			NOT NULL,
	circ_fine_interval	INTERVAL			NOT NULL,
	circ_duration		INTERVAL			NOT NULL,
	circ_due_date		TIMESTAMP WITH TIME ZONE	NOT NULL,
	circ_duration_rule	TEXT				NOT NULL,
	circ_recuring_fine_rule	TEXT				NOT NULL,
	circ_max_fine_rule	TEXT				NOT NULL,
	circ_stop_fines		TEXT
) WITHOUT OIDS;
CREATE TRIGGER circ_stats_circ_dim_id_trigger
	BEFORE INSERT ON circ_stats.circ_dim
	FOR EACH ROW
	EXECUTE PROCEDURE dim_row_hash ();


CREATE TABLE circ_stats.checkout_fact (
	-- circulation info
	circ_id			BIGINT				PRIMARY KEY,
	circ_lib		INT				NOT NULL,
	circ_staff		INT,
	circ_timestamp		TIMESTAMP WITH TIME ZONE	NOT NULL,
	circ_dim		INT				NOT NULL REFERENCES circ_stats.circ_dim (id),

	-- patron info
	usr_dim			INT				NOT NULL REFERENCES circ_stats.usr_dim (id),

	-- copy info
	copy_dim		INT				NOT NULL REFERENCES circ_stats.copy_dim (id),

	-- bib record info
	bib_dim			INT				NOT NULL REFERENCES circ_stats.record_dim (id)
) WITHOUT OIDS;
CREATE INDEX circ_stats_checkout_fact_time_idx		ON circ_stats.checkout_fact (circ_timestamp);
CREATE INDEX circ_stats_checkout_fact_circ_dim_idx	ON circ_stats.checkout_fact (circ_dim);
CREATE INDEX circ_stats_checkout_fact_usr_dim_idx	ON circ_stats.checkout_fact (usr_dim);
CREATE INDEX circ_stats_checkout_fact_copy_dim_idx	ON circ_stats.checkout_fact (copy_dim);
CREATE INDEX circ_stats_checkout_fact_bib_dim_idx	ON circ_stats.checkout_fact (bib_dim);

CREATE TABLE circ_stats.renewal_fact (
	-- circulation info
	circ_id			BIGINT				PRIMARY KEY,
	circ_lib		INT				NOT NULL,
	circ_staff		INT,
	circ_timestamp		TIMESTAMP WITH TIME ZONE	NOT NULL,
	circ_dim		INT				NOT NULL REFERENCES circ_stats.circ_dim (id),

	-- patron info
	usr_dim			INT				NOT NULL REFERENCES circ_stats.usr_dim (id),

	-- copy info
	copy_dim		INT				NOT NULL REFERENCES circ_stats.copy_dim (id),

	-- bib record info
	bib_dim			INT				NOT NULL REFERENCES circ_stats.record_dim (id)
) WITHOUT OIDS;
CREATE INDEX circ_stats_renewal_fact_time_idx		ON circ_stats.renewal_fact (circ_timestamp);
CREATE INDEX circ_stats_renewal_fact_circ_dim_idx	ON circ_stats.renewal_fact (circ_dim);
CREATE INDEX circ_stats_renewal_fact_usr_dim_idx	ON circ_stats.renewal_fact (usr_dim);
CREATE INDEX circ_stats_renewal_fact_copy_dim_idx	ON circ_stats.renewal_fact (copy_dim);
CREATE INDEX circ_stats_renewal_fact_bib_dim_idx	ON circ_stats.renewal_fact (bib_dim);

CREATE TABLE circ_stats.checkin_fact (
	-- circulation info
	circ_id			BIGINT				PRIMARY KEY,
	circ_lib		INT				NOT NULL,
	circ_staff		INT,
	circ_timestamp		TIMESTAMP WITH TIME ZONE	NOT NULL,
	circ_dim		INT				NOT NULL REFERENCES circ_stats.circ_dim (id),

	-- patron info
	usr_dim			INT				NOT NULL REFERENCES circ_stats.usr_dim (id),

	-- copy info
	copy_dim		INT				NOT NULL REFERENCES circ_stats.copy_dim (id),

	-- bib record info
	bib_dim			INT				NOT NULL REFERENCES circ_stats.record_dim (id)
) WITHOUT OIDS;
CREATE INDEX circ_stats_checkin_fact_time_idx		ON circ_stats.checkin_fact (circ_timestamp);
CREATE INDEX circ_stats_checkin_fact_circ_dim_idx	ON circ_stats.checkin_fact (circ_dim);
CREATE INDEX circ_stats_checkin_fact_usr_dim_idx	ON circ_stats.checkin_fact (usr_dim);
CREATE INDEX circ_stats_checkin_fact_copy_dim_idx	ON circ_stats.checkin_fact (copy_dim);
CREATE INDEX circ_stats_checkin_fact_bib_dim_idx	ON circ_stats.checkin_fact (bib_dim);

CREATE OR REPLACE VIEW circ_stats.checkout_full_view AS
	SELECT	circ_id,
		circ_timestamp,

		circ_lib,
		circ_staff,
		circ_opac_renewal,
		circ_self_checkout,
		circ_recuring_fine,
		circ_max_fine,
		circ_fine_interval,
		circ_duration,
		circ_due_date,
		circ_duration_rule,
		circ_recuring_fine_rule,
		circ_max_fine_rule,
		circ_stop_fines,

		usr_id,
		usr_grp,
		usr_standing,
		usr_home_ou,
		usr_county,
		usr_city,
		usr_post_code,

		copy_holdable,
		copy_ref,
		copy_circulate,
		copy_opac_visible,
		copy_circ_lib,
		copy_fine_level,
		copy_loan_duration,
		copy_location,
		copy_circ_modifer,
		copy_circ_as_type,
		copy_call_number_label,

		bib_item_type,
		bib_item_form,
		bib_level,
		bib_control_type,
		bib_char_encoding,
		bib_enc_level,
		bib_audience,
		bib_cat_form,
		bib_pub_status,
		bib_pub_date,
		bib_item_lang

	  FROM	circ_stats.checkout_fact f
		JOIN circ_stats.circ_dim cd ON (f.circ_dim = cd.id)
		JOIN circ_stats.usr_dim ud ON (f.usr_dim = ud.id)
		JOIN circ_stats.copy_dim cpd ON (f.copy_dim = cpd.id)
		JOIN circ_stats.record_dim bd ON (f.bib_dim = bd.id);

CREATE OR REPLACE VIEW circ_stats.checkin_full_view AS
	SELECT	circ_id,
		circ_timestamp,

		circ_lib,
		circ_staff,
		circ_opac_renewal,
		circ_self_checkout,
		circ_recuring_fine,
		circ_max_fine,
		circ_fine_interval,
		circ_duration,
		circ_due_date,
		circ_duration_rule,
		circ_recuring_fine_rule,
		circ_max_fine_rule,
		circ_stop_fines,

		usr_id,
		usr_grp,
		usr_standing,
		usr_home_ou,
		usr_county,
		usr_city,
		usr_post_code,

		copy_holdable,
		copy_ref,
		copy_circulate,
		copy_opac_visible,
		copy_circ_lib,
		copy_fine_level,
		copy_loan_duration,
		copy_location,
		copy_circ_modifer,
		copy_circ_as_type,
		copy_call_number_label,

		bib_item_type,
		bib_item_form,
		bib_level,
		bib_control_type,
		bib_char_encoding,
		bib_enc_level,
		bib_audience,
		bib_cat_form,
		bib_pub_status,
		bib_pub_date,
		bib_item_lang

	  FROM	circ_stats.checkin_fact f
		JOIN circ_stats.circ_dim cd ON (f.circ_dim = cd.id)
		JOIN circ_stats.usr_dim ud ON (f.usr_dim = ud.id)
		JOIN circ_stats.copy_dim cpd ON (f.copy_dim = cpd.id)
		JOIN circ_stats.record_dim bd ON (f.bib_dim = bd.id);

CREATE OR REPLACE VIEW circ_stats.renewal_full_view AS
	SELECT	circ_id,
		circ_timestamp,

		circ_lib,
		circ_staff,
		circ_opac_renewal,
		circ_self_checkout,
		circ_recuring_fine,
		circ_max_fine,
		circ_fine_interval,
		circ_duration,
		circ_due_date,
		circ_duration_rule,
		circ_recuring_fine_rule,
		circ_max_fine_rule,
		circ_stop_fines,

		usr_id,
		usr_grp,
		usr_standing,
		usr_home_ou,
		usr_county,
		usr_city,
		usr_post_code,

		copy_holdable,
		copy_ref,
		copy_circulate,
		copy_opac_visible,
		copy_circ_lib,
		copy_fine_level,
		copy_loan_duration,
		copy_location,
		copy_circ_modifer,
		copy_circ_as_type,
		copy_call_number_label,

		bib_item_type,
		bib_item_form,
		bib_level,
		bib_control_type,
		bib_char_encoding,
		bib_enc_level,
		bib_audience,
		bib_cat_form,
		bib_pub_status,
		bib_pub_date,
		bib_item_lang

	  FROM	circ_stats.renewal_fact f
		JOIN circ_stats.circ_dim cd ON (f.circ_dim = cd.id)
		JOIN circ_stats.usr_dim ud ON (f.usr_dim = ud.id)
		JOIN circ_stats.copy_dim cpd ON (f.copy_dim = cpd.id)
		JOIN circ_stats.record_dim bd ON (f.bib_dim = bd.id);


COMMIT;


