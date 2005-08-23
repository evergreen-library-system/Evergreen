DROP SCHEMA circ_stats CASCADE;

BEGIN;

CREATE SCHEMA circ_stats;

CREATE TABLE circ_stats.checkout (
	-- circulation info
	circ_id			BIGINT				PRIMARY KEY,
	circ_checkout_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
	circ_lib		INT				NOT NULL,
	circ_self		BOOL				NOT NULL,
	circ_staff		INT				NOT NULL,
	circ_duration		INTERVAL			NOT NULL,
	circ_duration_rule	TEXT				NOT NULL,
	circ_recuring_fine	INTERVAL			NOT NULL,
	circ_recuring_fine_rule	TEXT				NOT NULL,
	circ_max_fine		INTERVAL			NOT NULL,
	circ_max_fine_rule	TEXT				NOT NULL,
	circ_fine_interval	INTERVAL			NOT NULL,

	-- patron info
	-- usr_id		INT				NOT NULL,
	usr_grp			INT				NOT NULL, -- aka profile
	usr_county		TEXT				NOT NULL,
	usr_city		TEXT				NOT NULL,
	usr_post_code		TEXT				NOT NULL,
	usr_standing		INT				NOT NULL,
	usr_home_ou		INT				NOT NULL,

	-- copy info
	cp_circ_lib		INT				NOT NULL,
	cp_barcode		TEXT				NOT NULL,
	cp_holdable		BOOL				NOT NULL,
	cp_ref			BOOL				NOT NULL,
	cp_circulate		BOOL				NOT NULL,
	cp_opac_visible		BOOL				NOT NULL,
	cp_circ_modifer		TEXT				NOT NULL,
	cp_circ_as_type		TEXT				NOT NULL,
	cp_location		INT				NOT NULL,
	cp_fine_level		INT				NOT NULL,
	cp_load_duration	INT				NOT NULL,
	cp_location		INT				NOT NULL,

	-- call number info
	cn_owning_lib		INT				NOT NULL,
	cn_label		TEXT				NOT NULL,

	-- bib record info
	bib_id			BIGINT				NOT NULL,
	bib_item_type		"char"				NOT NULL,
	bib_item_form		"char"				NOT NULL,
	bib_level		"char"				NOT NULL,
	bib_control_type	"char"				NOT NULL,
	bib_char_encoding	"char"				NOT NULL,
	bib_enc_level		"char"				NOT NULL,
	bib_audience		"char"				NOT NULL,
	bib_cat_form		TEXT				NOT NULL,
	bib_pub_status		TEXT				NOT NULL,
	bib_item_lang		TEXT				NOT NULL
) WITHOUT OIDS;

CREATE TABLE circ_stats.renewal (
	-- circulation info
	circ_id			BIGINT				PRIMARY KEY,
	circ_renewal_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
	circ_lib		INT				NOT NULL,
	circ_opac		BOOL				NOT NULL,
	circ_staff		INT				NOT NULL,
	circ_duration		INTERVAL			NOT NULL,
	circ_duration_rule	TEXT				NOT NULL,
	circ_recuring_fine	INTERVAL			NOT NULL,
	circ_recuring_fine_rule	TEXT				NOT NULL,
	circ_max_fine		INTERVAL			NOT NULL,
	circ_max_fine_rule	TEXT				NOT NULL,
	circ_fine_interval	INTERVAL			NOT NULL,

	-- patron info
	-- usr_id		INT				NOT NULL,
	usr_grp			INT				NOT NULL, -- aka profile
	usr_county		TEXT				NOT NULL,
	usr_city		TEXT				NOT NULL,
	usr_post_code		TEXT				NOT NULL,
	usr_standing		INT				NOT NULL,
	usr_home_ou		INT				NOT NULL,

	-- copy info
	cp_circ_lib		INT				NOT NULL,
	cp_barcode		TEXT				NOT NULL,
	cp_holdable		BOOL				NOT NULL,
	cp_ref			BOOL				NOT NULL,
	cp_circulate		BOOL				NOT NULL,
	cp_opac_visible		BOOL				NOT NULL,
	cp_circ_modifer		TEXT				NOT NULL,
	cp_circ_as_type		TEXT				NOT NULL,
	cp_location		INT				NOT NULL,
	cp_fine_level		INT				NOT NULL,
	cp_load_duration	INT				NOT NULL,
	cp_location		INT				NOT NULL,

	-- call number info
	cn_owning_lib		INT				NOT NULL,
	cn_label		TEXT				NOT NULL,

	-- bib record info
	bib_id			BIGINT				NOT NULL,
	bib_item_type		"char"				NOT NULL,
	bib_item_form		"char"				NOT NULL,
	bib_level		"char"				NOT NULL,
	bib_control_type	"char"				NOT NULL,
	bib_char_encoding	"char"				NOT NULL,
	bib_enc_level		"char"				NOT NULL,
	bib_audience		"char"				NOT NULL,
	bib_cat_form		TEXT				NOT NULL,
	bib_pub_status		TEXT				NOT NULL,
	bib_item_lang		TEXT				NOT NULL
) WITHOUT OIDS;

CREATE TABLE circ_stats.checkin (
	-- circulation info
	circ_id			BIGINT				PRIMARY KEY,
	circ_checkin_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
	circ_checkout_lib	INT				NOT NULL,
	circ_checkin_lib	INT				NOT NULL,
	circ_staff		INT				NOT NULL,
	circ_duration		INTERVAL			NOT NULL,
	circ_duration_rule	TEXT				NOT NULL,
	circ_recuring_fine	INTERVAL			NOT NULL,
	circ_recuring_fine_rule	TEXT				NOT NULL,
	circ_max_fine		INTERVAL			NOT NULL,
	circ_max_fine_rule	TEXT				NOT NULL,
	circ_fine_interval	INTERVAL			NOT NULL,

	-- patron info
	-- usr_id		INT				NOT NULL,
	usr_grp			INT				NOT NULL, -- aka profile
	usr_county		TEXT				NOT NULL,
	usr_city		TEXT				NOT NULL,
	usr_post_code		TEXT				NOT NULL,
	usr_standing		INT				NOT NULL,
	usr_home_ou		INT				NOT NULL,

	-- copy info
	cp_circ_lib		INT				NOT NULL,
	cp_barcode		TEXT				NOT NULL,
	cp_holdable		BOOL				NOT NULL,
	cp_ref			BOOL				NOT NULL,
	cp_circulate		BOOL				NOT NULL,
	cp_opac_visible		BOOL				NOT NULL,
	cp_circ_modifer		TEXT				NOT NULL,
	cp_circ_as_type		TEXT				NOT NULL,
	cp_location		INT				NOT NULL,
	cp_fine_level		INT				NOT NULL,
	cp_load_duration	INT				NOT NULL,
	cp_location		INT				NOT NULL,

	-- call number info
	cn_owning_lib		INT				NOT NULL,
	cn_label		TEXT				NOT NULL,

	-- bib record info
	bib_id			BIGINT				NOT NULL,
	bib_item_type		"char"				NOT NULL,
	bib_item_form		"char"				NOT NULL,
	bib_level		"char"				NOT NULL,
	bib_control_type	"char"				NOT NULL,
	bib_char_encoding	"char"				NOT NULL,
	bib_enc_level		"char"				NOT NULL,
	bib_audience		"char"				NOT NULL,
	bib_cat_form		TEXT				NOT NULL,
	bib_pub_status		TEXT				NOT NULL,
	bib_item_lang		TEXT				NOT NULL
) WITHOUT OIDS;

