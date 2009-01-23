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



DROP SCHEMA stats CASCADE;
DROP SCHEMA config CASCADE;

BEGIN;
CREATE SCHEMA stats;

CREATE SCHEMA config;
COMMENT ON SCHEMA config IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * The config schema holds static configuration data for the
 * Open-ILS installation.
 *
 * ****
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
 */
$$;

CREATE TABLE config.upgrade_log (
    version         TEXT    PRIMARY KEY,
    install_date    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
INSERT INTO config.upgrade_log (version) VALUES ('1.4.0');

CREATE TABLE config.bib_source (
	id		SERIAL	PRIMARY KEY,
	quality		INT	CHECK ( quality BETWEEN 0 AND 100 ),
	source		TEXT	NOT NULL UNIQUE,
	transcendant	BOOL	NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE config.bib_source IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Valid sources of MARC records
 *
 * This is table is used to set up the relative "quality" of each
 * MARC source, such as OCLC.
 *
 * ****
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
 */
$$;

CREATE TABLE config.standing (
	id		SERIAL	PRIMARY KEY,
	value		TEXT	NOT NULL UNIQUE
);
COMMENT ON TABLE config.standing IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Patron Standings
 *
 * This table contains the values that can be applied to a patron
 * by a staff member.  These values should not be changed, other
 * than for translation, as the ID column is currently a "magic
 * number" in the source. :(
 *
 * ****
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
 */
$$;

CREATE TABLE config.xml_transform (
	name		TEXT	PRIMARY KEY,
	namespace_uri	TEXT	NOT NULL,
	prefix		TEXT	NOT NULL,
	xslt		TEXT	NOT NULL
);

CREATE TABLE config.metabib_field (
	id		SERIAL	PRIMARY KEY,
	field_class	TEXT	NOT NULL CHECK (lower(field_class) IN ('title','author','subject','keyword','series')),
	name		TEXT	NOT NULL,
	xpath		TEXT	NOT NULL,
	weight		INT	NOT NULL DEFAULT 1,
	format		TEXT	NOT NULL DEFAULT 'mods32',
	search_field	BOOL	NOT NULL DEFAULT TRUE,
	facet_field	BOOL	NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE config.metabib_field IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * XPath used for record indexing ingest
 *
 * This table contains the XPath used to chop up MODS into its
 * indexable parts.  Each XPath entry is named and assigned to
 * a "class" of either title, subject, author, keyword or series.
 * 
 *
 * ****
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
 */
$$;

CREATE UNIQUE INDEX config_metabib_field_class_name_idx ON config.metabib_field (field_class, name);

CREATE TABLE config.non_cataloged_type (
	id		SERIAL		PRIMARY KEY,
	owning_lib	INT		NOT NULL, -- REFERENCES actor.org_unit (id),
	name		TEXT		NOT NULL,
	circ_duration	INTERVAL	NOT NULL DEFAULT '14 days'::INTERVAL,
	in_house	BOOL		NOT NULL DEFAULT FALSE,
	CONSTRAINT noncat_once_per_lib UNIQUE (owning_lib,name)
);
COMMENT ON TABLE config.non_cataloged_type IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Types of valid non-cataloged items.
 *
 *
 * ****
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
 */
$$;

CREATE TABLE config.identification_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE
);
COMMENT ON TABLE config.identification_type IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Types of valid patron identification.
 *
 * Each patron must display at least one valid form of identification
 * in order to get a library card.  This table lists those forms.
 * 
 *
 * ****
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
 */
$$;

CREATE TABLE config.rule_circ_duration (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
	extended	INTERVAL	NOT NULL,
	normal		INTERVAL	NOT NULL,
	shrt		INTERVAL	NOT NULL,
	max_renewals	INT		NOT NULL
);
COMMENT ON TABLE config.rule_circ_duration IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Circulation Duration rules
 *
 * Each circulation is given a duration based on one of these rules.
 * 
 *
 * ****
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
 */
$$;

CREATE TABLE config.rule_max_fine (
    id          SERIAL          PRIMARY KEY,
    name        TEXT            NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
    amount      NUMERIC(6,2)    NOT NULL,
    is_percent  BOOL            NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE config.rule_max_fine IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Circulation Max Fine rules
 *
 * Each circulation is given a maximum fine based on one of
 * these rules.
 * 
 *
 * ****
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
 */
$$;

CREATE TABLE config.rule_recuring_fine (
	id			SERIAL		PRIMARY KEY,
	name			TEXT		NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
	high			NUMERIC(6,2)	NOT NULL,
	normal			NUMERIC(6,2)	NOT NULL,
	low			NUMERIC(6,2)	NOT NULL,
	recurance_interval	INTERVAL	NOT NULL DEFAULT '1 day'::INTERVAL
);
COMMENT ON TABLE config.rule_recuring_fine IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Circulation Recurring Fine rules
 *
 * Each circulation is given a recurring fine amount based on one of
 * these rules.  The recurance_interval should not be any shorter
 * than the interval between runs of the fine_processor.pl script
 * (which is run from CRON), or you could miss fines.
 * 
 *
 * ****
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
 */
$$;


CREATE TABLE config.rule_age_hold_protect (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
	age	INTERVAL	NOT NULL,
	prox	INT		NOT NULL
);
COMMENT ON TABLE config.rule_age_hold_protect IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Hold Item Age Protection rules
 *
 * A hold request can only capture new(ish) items when they are
 * within a particular proximity of the home_ou of the requesting
 * user.  The proximity ('prox' column) is calculated by counting
 * the number of tree edges between the user's home_ou and the owning_lib
 * of the copy that could fulfill the hold.
 * 
 *
 * ****
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
 */
$$;

CREATE TABLE config.copy_status (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	holdable	BOOL	NOT NULL DEFAULT FALSE,
	opac_visible	BOOL	NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE config.copy_status IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Copy Statuses
 *
 * The available copy statuses, and whether a copy in that
 * status is available for hold request capture.  0 (zero) is
 * the only special number in this set, meaning that the item
 * is available for immediate checkout, and is counted as available
 * in the OPAC.
 *
 * Statuses with an ID below 100 are not removable, and have special
 * meaning in the code.  Do not change them except to translate the
 * textual name.
 *
 * You may add and remove statuses above 100, and these can be used
 * to remove items from normal circulation without affecting the rest
 * of the copy's values or its location.
 *
 * ****
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
 */
$$;

CREATE TABLE config.net_access_level (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE
);
COMMENT ON TABLE config.net_access_level IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Patron Network Access level
 *
 * This will be used to inform the in-library firewall of how much
 * internet access the using patron should be allowed.
 *
 * ****
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
 */
$$;

CREATE TABLE config.audience_map (
	code		TEXT	PRIMARY KEY,
	value		TEXT	NOT NULL,
	description	TEXT
);

CREATE TABLE config.lit_form_map (
	code		TEXT	PRIMARY KEY,
	value		TEXT	NOT NULL,
	description	TEXT
);

CREATE TABLE config.language_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

CREATE TABLE config.item_form_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

CREATE TABLE config.item_type_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

CREATE TABLE config.bib_level_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

CREATE TABLE config.z3950_source (
    name                TEXT    PRIMARY KEY,
    label               TEXT    NOT NULL UNIQUE,
    host                TEXT    NOT NULL,
    port                INT     NOT NULL,
    db                  TEXT    NOT NULL,
    record_format       TEXT    NOT NULL DEFAULT 'FI',
    transmission_format TEXT    NOT NULL DEFAULT 'usmarc',
    auth                BOOL    NOT NULL DEFAULT TRUE
);

CREATE TABLE config.z3950_attr (
    id          SERIAL  PRIMARY KEY,
    source      TEXT    NOT NULL REFERENCES config.z3950_source (name),
    name        TEXT    NOT NULL,
    label       TEXT    NOT NULL,
    code        INT     NOT NULL,
    format      INT     NOT NULL,
    truncation  INT     NOT NULL DEFAULT 0,
    CONSTRAINT z_code_format_once_per_source UNIQUE (code,format,source)
);

CREATE TABLE config.i18n_locale (
    code        TEXT    PRIMARY KEY,
    marc_code   TEXT    NOT NULL REFERENCES config.language_map (code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE config.i18n_core (
    id              BIGSERIAL   PRIMARY KEY,
    fq_field        TEXT        NOT NULL,
    identity_value  TEXT        NOT NULL,
    translation     TEXT        NOT NULL    REFERENCES config.i18n_locale (code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    string          TEXT        NOT NULL
);

CREATE UNIQUE INDEX i18n_identity ON config.i18n_core (fq_field,identity_value,translation);

COMMIT;

