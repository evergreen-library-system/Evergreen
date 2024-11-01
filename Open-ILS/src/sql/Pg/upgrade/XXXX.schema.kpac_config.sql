BEGIN;

-- Bootstrap KPAC Configuration Interface

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE config.kpac_content_types (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL
);

INSERT INTO config.kpac_content_types
    (id, name)
VALUES
    (1, 'Category'),
    (2, 'Book List'),
    (3, 'URL'),
    (4, 'Search String')
; 

CREATE TABLE config.kpac_topics (
    id              SERIAL PRIMARY KEY,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    parent          INTEGER, -- empty is home / top level entry
    img             TEXT, -- image file name
    name            TEXT NOT NULL,
    description     TEXT,
    content_type    INTEGER NOT NULL REFERENCES config.kpac_content_types (id),
    content_list    INTEGER, -- bookbag id
    content_link    TEXT, -- url
    content_search  TEXT, -- preset search string
    topic_order     INTEGER
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
   'eg.grid.admin.server.config.kpac_topics', 'gui', 'object',
   oils_i18n_gettext(
       'eg.grid.admin.server.config.kpac_topics',
       'Grid Config: KPAC topics',
       'cwst', 'label')
);

INSERT into config.org_unit_setting_type
	(name, grp, label, description, datatype)
VALUES (
	'opac.show_kpac_link',
	'opac',
	oils_i18n_gettext('opac.show_kpac_link',
    	'Show KPAC Link',
    	'coust', 'label'),
	oils_i18n_gettext('opac.show_kpac_link',
    	'Show the KPAC link in the OPAC. Default is false.',
    	'coust', 'description'),
	'bool'
);

INSERT into permission.perm_list
    (code, description)
VALUES (
    'KPAC_ADMIN',
    'Allow user to configure KPAC category and topic entries'
);

INSERT into config.org_unit_setting_type
	(name, grp, label, description, datatype)
VALUES (
	'opac.kpac_audn_filter',
	'opac',
    oils_i18n_gettext('opac.kpac_audn_filter',
        'KPAC Audience Filter',
        'coust', 'label'),
	oils_i18n_gettext('opac.kpac_audn_filter',
        'Controls which items to display based on MARC Target Audience (Audn) field. Options are: a,b,c,d,j. Default is: a,b,c,j',
        'coust', 'description'),
	'string'
);


COMMIT;


