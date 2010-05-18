BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0265'); -- miker

ALTER TABLE config.metabib_field DROP CONSTRAINT metabib_field_field_class_check;

INSERT INTO config.metabib_class ( name, label ) VALUES ( 'identifier', oils_i18n_gettext('identifier', 'Identifier', 'cmc', 'name') );

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (17, 'identifier', 'accession', oils_i18n_gettext(17, 'Accession Number', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="001"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (18, 'identifier', 'isbn', oils_i18n_gettext(18, 'ISBN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="020"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (19, 'identifier', 'issn', oils_i18n_gettext(19, 'ISSN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="022"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (20, 'identifier', 'upc', oils_i18n_gettext(20, 'UPC', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="1"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (21, 'identifier', 'ismn', oils_i18n_gettext(21, 'ISMN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="2"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (22, 'identifier', 'ean', oils_i18n_gettext(22, 'EAN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="3"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (23, 'identifier', 'isrc', oils_i18n_gettext(23, 'ISRC', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="0"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (24, 'identifier', 'sici', oils_i18n_gettext(24, 'SICI', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="4"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (25, 'identifier', 'bibcn', oils_i18n_gettext(25, 'Local Free-Text Call Number', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="099"]//text()$$, TRUE );

SELECT SETVAL('config.metabib_field_id_seq'::TEXT, (SELECT MAX(id) FROM config.metabib_field), TRUE);
 

DELETE FROM config.metabib_search_alias WHERE alias = 'dc.identifier';

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('id','identifier');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.identifier','identifier');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.isbn','identifier', 18);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.issn','identifier', 19);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.upc','identifier', 20);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.callnumber','identifier', 25);

CREATE TABLE metabib.identifier_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_identifier_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.identifier_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE INDEX metabib_identifier_field_entry_index_vector_idx ON metabib.identifier_field_entry USING GIST (index_vector);
CREATE INDEX metabib_identifier_field_entry_value_idx ON metabib.identifier_field_entry
    (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_identifier_field_entry_source_idx ON metabib.identifier_field_entry (source);

ALTER TABLE metabib.identifier_field_entry ADD CONSTRAINT metabib_identifier_field_entry_source_pkey
    FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.identifier_field_entry ADD CONSTRAINT metabib_identifier_field_entry_field_pkey
    FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;

