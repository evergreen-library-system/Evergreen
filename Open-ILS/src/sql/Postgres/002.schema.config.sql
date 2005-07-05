
DROP SCHEMA config CASCADE;

BEGIN;
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


CREATE TABLE config.bib_source (
	id	SERIAL	PRIMARY KEY,
	quality	INT	CHECK ( quality BETWEEN 0 AND 100 ),
	source	TEXT	NOT NULL UNIQUE
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


INSERT INTO config.bib_source (quality, source) VALUES (90, 'OcLC');
INSERT INTO config.bib_source (quality, source) VALUES (10, 'System Local');

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
 * that for translation, as the ID column is currently a "magic
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


INSERT INTO config.standing (value) VALUES ('Good');
INSERT INTO config.standing (value) VALUES ('Barred');

CREATE TABLE config.metabib_field (
	id		SERIAL	PRIMARY KEY,
	field_class	TEXT	NOT NULL CHECK (lower(field_class) IN ('title','author','subject','keyword','series')),
	name		TEXT	NOT NULL UNIQUE,
	xpath		TEXT	NOT NULL
);
COMMENT ON TABLE config.metabib_field IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * XPath used for WoRMing
 *
 * This table contains the XPath used to chop up MODS into it's
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


INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'series', 'seriestitle', $$//mods:mods/mods:relatedItem[@type="series"]/mods:titleInfo$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'abbreviated', $$//mods:mods/mods:titleInfo[mods:title and (@type='abreviated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'translated', $$//mods:mods/mods:titleInfo[mods:title and (@type='translated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'uniform', $$//mods:mods/mods:titleInfo[mods:title and (@type='uniform')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'proper', $$//mods:mods/mods:titleInfo[mods:title and not (@type)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'corporate', $$//mods:mods/mods:name[@type='corporate']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'personal', $$//mods:mods/mods:name[@type='personal']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'conference', $$//mods:mods/mods:name[@type='conference']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'other', $$//mods:mods/mods:name[@type='personal']/mods:namePart[not(../mods:role)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'geographic', $$//mods:mods/mods:subject/mods:geographic$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'name', $$//mods:mods/mods:subject/mods:name$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'temporal', $$//mods:mods/mods:subject/mods:temporal$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'topic', $$//mods:mods/mods:subject/mods:topic$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'genre', $$//mods:mods/mods:genre$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'keyword', 'keyword', $$//mods:mods/*[not(local-name()='originInfo')]$$ ); -- /* to fool vim */

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


INSERT INTO config.identification_type ( name ) VALUES ( 'Drivers Licence' );
INSERT INTO config.identification_type ( name ) VALUES ( 'Voter Card' );
INSERT INTO config.identification_type ( name ) VALUES ( 'Two Utility Bills' );
INSERT INTO config.identification_type ( name ) VALUES ( 'State ID' );
INSERT INTO config.identification_type ( name ) VALUES ( 'SSN' );

CREATE TABLE config.rule_circ_duration (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
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
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	amount	NUMERIC(6,2)	NOT NULL
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
	name			TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
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
 * Circulation Recuring Fine rules
 *
 * Each circulation is given a recuring fine amount based on one of
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
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
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
 * the number of tree edges beween the user's home_ou and the owning_lib
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
	holdable	BOOL	NOT NULL DEFAULT 'F'
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
 * is available for imediate checkout, and is counted as available
 * in the OPAC.
 *
 * Statuses with an ID below 100 are not removable, and have special
 * meaning in the code.  Do not change them except to translate the
 * textual name.
 *
 * You may add and remove statuses above 100, and these can be used
 * to remove items from normal circulation without affecting the rest
 * of the copies values or it's location.
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

INSERT INTO config.copy_status (id,name,holdable) VALUES (0,'Available','t');
INSERT INTO config.copy_status (name,holdable) VALUES ('Checked out','t');
INSERT INTO config.copy_status (name) VALUES ('Bindery');
INSERT INTO config.copy_status (name) VALUES ('Lost');
INSERT INTO config.copy_status (name) VALUES ('Missing');
INSERT INTO config.copy_status (name,holdable) VALUES ('In process','t');
INSERT INTO config.copy_status (name) VALUES ('In transit');
INSERT INTO config.copy_status (name,holdable) VALUES ('Reshelving','t');
INSERT INTO config.copy_status (name) VALUES ('On holds shelf');
INSERT INTO config.copy_status (name,holdable) VALUES ('On order','t');
INSERT INTO config.copy_status (name) VALUES ('ILL');
INSERT INTO config.copy_status (name) VALUES ('Cataloging');
INSERT INTO config.copy_status (name) VALUES ('Reserves');
INSERT INTO config.copy_status (name) VALUES ('Discard/Weed');

SELECT SETVAL('config.copy_status_id_seq'::TEXT, 100);


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

INSERT INTO config.net_access_level (name) VALUES ('Restricted');
INSERT INTO config.net_access_level (name) VALUES ('Full');
INSERT INTO config.net_access_level (name) VALUES ('None');



/*

CREATE TABLE config.new_metabib_field (
	id		SERIAL	PRIMARY KEY,
	field_class	TEXT	NOT NULL CHECK (lower(field_class) IN ('title','author','subject','keyword','series')),
	name		TEXT	NOT NULL UNIQUE,
	search_xpath	TEXT	NOT NULL,
	browse_xpath	TEXT
);

INSERT INTO config.new_metabib_field ( field_class, name, search_xpath, browse_xpath )
	VALUES ( 'series', 'seriestitle', $$//mods/relatedItem[@type="series"]/titleInfo$$, $$//mods/relatedItem[@type="series"]/titleInfo/title$$ );

INSERT INTO config.new_metabib_field ( field_class, name, search_xpath, browse_xpath )
	VALUES ( 'title', 'abbreviated', $$//mods/titleInfo[title and (@type='abreviated')]$$, $$//mods/titleInfo[title and (@type='abreviated')]/title$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath, browse_xpath )
	VALUES ( 'title', 'translated', $$//mods/titleInfo[title and (@type='translated')]$$, $$//mods/titleInfo[title and (@type='translated')]/title$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath, browse_xpath )
	VALUES ( 'title', 'uniform', $$//mods/titleInfo[title and (@type='uniform')]$$, $$//mods/titleInfo[title and (@type='uniform')]/title$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath, browse_xpath )
	VALUES ( 'title', 'proper', $$//mods/titleInfo[title and not (@type)]$$, $$//mods/titleInfo[title and not (@type)]/title$$ );

INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'author', 'corporate', $$//mods/name[@type='corporate']/namePart[../role/text[text()='creator']]$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'author', 'personal', $$//mods/name[@type='personal']/namePart[../role/text[text()='creator']]$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'author', 'conference', $$//mods/name[@type='conference']/namePart[../role/text[text()='creator']]$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'author', 'other', $$//mods/name[@type='personal']/namePart[not(../role)]$$ );

INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'subject', 'geographic', $$//mods/subject/geographic$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'subject', 'name', $$//mods/subject/name$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'subject', 'temporal', $$//mods/subject/temporal$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'subject', 'topic', $$//mods/subject/topic$$ );
INSERT INTO config.new_metabib_field ( field_class, name, search_xpath )
	VALUES ( 'keyword', 'keyword', $$//mods/*[not(local-name()='originInfo')]$$ ); 

*/

COMMIT;
