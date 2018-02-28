BEGIN;

SELECT evergreen.upgrade_deps_block_check('1100', :eg_version);

-- NEW config.metabib_field entries

UPDATE config.metabib_field SET display_xpath = facet_xpath, display_field = TRUE WHERE id = 33;

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    38, 'identifier', 'edition', 
    oils_i18n_gettext(38, 'Edition', 'cmf', 'label'),
    $$//mods33:mods/mods33:originInfo//mods33:edition[1]$$,
    TRUE, TRUE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    39, 'keyword', 'physical_description', 
    oils_i18n_gettext(39, 'Physical Descrption', 'cmf', 'label'),
    $$(//mods33:mods/mods33:physicalDescription/mods33:form|//mods33:mods/mods33:physicalDescription/mods33:extent|//mods33:mods/mods33:physicalDescription/mods33:reformattingQuality|//mods33:mods/mods33:physicalDescription/mods33:internetMediaType|//mods33:mods/mods33:physicalDescription/mods33:digitalOrigin)$$,
    TRUE, TRUE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    40, 'identifier', 'publisher', 
    oils_i18n_gettext(40, 'Publisher', 'cmf', 'label'),
    $$//mods33:mods/mods33:originInfo//mods33:publisher[1]$$,
    TRUE, TRUE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    41, 'keyword', 'abstract', 
    oils_i18n_gettext(41, 'Abstract', 'cmf', 'label'),
    $$//mods33:mods/mods33:abstract$$,
    TRUE, TRUE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    42, 'keyword', 'toc', 
    oils_i18n_gettext(42, 'Table of Contents', 'cmf', 'label'),
    $$//mods33:tableOfContents$$,
    TRUE, TRUE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    43, 'identifier', 'type_of_resource', 
    oils_i18n_gettext(43, 'Type of Resource', 'cmf', 'label'),
    $$//mods33:mods/mods33:typeOfResource$$,
    TRUE, FALSE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    44, 'identifier', 'pubdate', 
    oils_i18n_gettext(44, 'Publication Date', 'cmf', 'label'),
    $$//mods33:mods/mods33:originInfo//mods33:dateIssued[@encoding="marc"]|//mods33:mods/mods33:originInfo//mods33:dateIssued[1]$$,
    TRUE, FALSE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, 
    label, xpath, display_field, search_field, browse_field)
VALUES (
    46, 'keyword', 'bibliography', 
    oils_i18n_gettext(46, 'Bibliography', 'cmf', 'label'),
    $$//mods33:note[@type='bibliography']$$,
    TRUE, TRUE, FALSE
),(
    47, 'keyword', 'thesis', 
    oils_i18n_gettext(47, 'Thesis', 'cmf', 'label'),
    $$//mods33:note[@type='thesis']$$,
    TRUE, TRUE, FALSE
),(
    48, 'keyword', 'production_credits', 
    oils_i18n_gettext(48, 'Creation/Production Credits', 'cmf', 'label'),
    $$//mods33:note[@type='creation/production credits']$$,
    TRUE, TRUE, FALSE
),(
    49, 'keyword', 'performers', 
    oils_i18n_gettext(49, 'Performers', 'cmf', 'label'),
    $$//mods33:note[@type='performers']$$,
    TRUE, TRUE, FALSE
),(
    50, 'keyword', 'general_note', 
    oils_i18n_gettext(50, 'General Note', 'cmf', 'label'),
    $$//mods33:note[not(@type)]$$,
    TRUE, TRUE, FALSE
)
;

INSERT INTO config.metabib_field (id, field_class, name, format,
    label, xpath, display_xpath, display_field, search_field, browse_field)
VALUES (
    51, 'author', 'first_author', 'mods32',
    oils_i18n_gettext(51, 'Author', 'cmf', 'label'),
    $$//mods32:mods/mods32:name[mods32:role/mods32:roleTerm[text()='creator']][1]$$,
    $$//*[local-name()='namePart']$$,
    TRUE, TRUE, FALSE
);

INSERT INTO config.metabib_field (id, field_class, name, format,
    label, xpath, display_xpath, display_field, search_field, browse_field)
VALUES (
    52, 'identifier', 'origin_info', 'marcxml',
    oils_i18n_gettext(52, 'Origin Info', 'cmf', 'label'),
    $$//*[@tag='260']$$,
    $$//*[local-name()='subfield' and contains('abc',@code)]$$,
    TRUE, FALSE, FALSE
);


-- Modify existing config.metabib_field entries

UPDATE config.metabib_field SET display_field = TRUE WHERE id IN (
    1,  -- seriestitle
    11, -- subject_geographic 
    12, -- subject_name
    13, -- subject_temporal
    14, -- subject_topic
    19, -- ISSN
    20, -- UPC
    26  -- TCN
);

-- Map display field names to config.metabib_field entries

INSERT INTO config.display_field_map (name, field, multi) VALUES 
    ('series_title',         1, TRUE),
    ('subject_geographic',  11, TRUE),
    ('subject_name',        12, TRUE),
    ('subject_temporal',    13, TRUE),
    ('subject_topic',       14, TRUE),
    ('issn',                19, TRUE),
    ('upc',                 20, TRUE),
    ('tcn',                 26, FALSE),
    ('edition',             38, FALSE),
    ('physical_description',39, TRUE),
    ('genre',               33, TRUE),
    ('bibliography',        46, TRUE),
    ('thesis',              47, TRUE),
    ('performers',          49, TRUE),
    ('production_credits',  48, TRUE),
    ('general_note',        50, TRUE),
    ('publisher',           52, FALSE),
    ('abstract',            41, FALSE),
    ('toc',                 42, FALSE),
    ('type_of_resource',    43, FALSE),
    ('pubdate',             44, FALSE)
;

UPDATE config.display_field_map SET field = 51 WHERE name = 'author';

-- Add a column to wide-display-entry per well-known field

DROP VIEW IF EXISTS metabib.wide_display_entry;
CREATE VIEW metabib.wide_display_entry AS
    SELECT 
        bre.id AS source,
        COALESCE(mcde_title.value, 'null')::TEXT AS title,
        COALESCE(mcde_author.value, 'null')::TEXT AS author,
        COALESCE(mcde_subject_geographic.value, 'null')::TEXT AS subject_geographic,
        COALESCE(mcde_subject_name.value, 'null')::TEXT AS subject_name,
        COALESCE(mcde_subject_temporal.value, 'null')::TEXT AS subject_temporal,
        COALESCE(mcde_subject_topic.value, 'null')::TEXT AS subject_topic,
        COALESCE(mcde_creators.value, 'null')::TEXT AS creators,
        COALESCE(mcde_isbn.value, 'null')::TEXT AS isbn,
        COALESCE(mcde_issn.value, 'null')::TEXT AS issn,
        COALESCE(mcde_upc.value, 'null')::TEXT AS upc,
        COALESCE(mcde_tcn.value, 'null')::TEXT AS tcn,
        COALESCE(mcde_edition.value, 'null')::TEXT AS edition,
        COALESCE(mcde_physical_description.value, 'null')::TEXT AS physical_description,
        COALESCE(mcde_publisher.value, 'null')::TEXT AS publisher,
        COALESCE(mcde_series_title.value, 'null')::TEXT AS series_title,
        COALESCE(mcde_abstract.value, 'null')::TEXT AS abstract,
        COALESCE(mcde_toc.value, 'null')::TEXT AS toc,
        COALESCE(mcde_pubdate.value, 'null')::TEXT AS pubdate,
        COALESCE(mcde_type_of_resource.value, 'null')::TEXT AS type_of_resource
    FROM biblio.record_entry bre 
    LEFT JOIN metabib.compressed_display_entry mcde_title 
        ON (bre.id = mcde_title.source AND mcde_title.name = 'title')
    LEFT JOIN metabib.compressed_display_entry mcde_author 
        ON (bre.id = mcde_author.source AND mcde_author.name = 'author')
    LEFT JOIN metabib.compressed_display_entry mcde_subject 
        ON (bre.id = mcde_subject.source AND mcde_subject.name = 'subject')
    LEFT JOIN metabib.compressed_display_entry mcde_subject_geographic 
        ON (bre.id = mcde_subject_geographic.source 
            AND mcde_subject_geographic.name = 'subject_geographic')
    LEFT JOIN metabib.compressed_display_entry mcde_subject_name 
        ON (bre.id = mcde_subject_name.source 
            AND mcde_subject_name.name = 'subject_name')
    LEFT JOIN metabib.compressed_display_entry mcde_subject_temporal 
        ON (bre.id = mcde_subject_temporal.source 
            AND mcde_subject_temporal.name = 'subject_temporal')
    LEFT JOIN metabib.compressed_display_entry mcde_subject_topic 
        ON (bre.id = mcde_subject_topic.source 
            AND mcde_subject_topic.name = 'subject_topic')
    LEFT JOIN metabib.compressed_display_entry mcde_creators 
        ON (bre.id = mcde_creators.source AND mcde_creators.name = 'creators')
    LEFT JOIN metabib.compressed_display_entry mcde_isbn 
        ON (bre.id = mcde_isbn.source AND mcde_isbn.name = 'isbn')
    LEFT JOIN metabib.compressed_display_entry mcde_issn 
        ON (bre.id = mcde_issn.source AND mcde_issn.name = 'issn')
    LEFT JOIN metabib.compressed_display_entry mcde_upc 
        ON (bre.id = mcde_upc.source AND mcde_upc.name = 'upc')
    LEFT JOIN metabib.compressed_display_entry mcde_tcn 
        ON (bre.id = mcde_tcn.source AND mcde_tcn.name = 'tcn')
    LEFT JOIN metabib.compressed_display_entry mcde_edition 
        ON (bre.id = mcde_edition.source AND mcde_edition.name = 'edition')
    LEFT JOIN metabib.compressed_display_entry mcde_physical_description 
        ON (bre.id = mcde_physical_description.source 
            AND mcde_physical_description.name = 'physical_description')
    LEFT JOIN metabib.compressed_display_entry mcde_publisher 
        ON (bre.id = mcde_publisher.source AND mcde_publisher.name = 'publisher')
    LEFT JOIN metabib.compressed_display_entry mcde_series_title 
        ON (bre.id = mcde_series_title.source AND mcde_series_title.name = 'series_title')
    LEFT JOIN metabib.compressed_display_entry mcde_abstract 
        ON (bre.id = mcde_abstract.source AND mcde_abstract.name = 'abstract')
    LEFT JOIN metabib.compressed_display_entry mcde_toc 
        ON (bre.id = mcde_toc.source AND mcde_toc.name = 'toc')
    LEFT JOIN metabib.compressed_display_entry mcde_pubdate 
        ON (bre.id = mcde_pubdate.source AND mcde_pubdate.name = 'pubdate')
    LEFT JOIN metabib.compressed_display_entry mcde_type_of_resource 
        ON (bre.id = mcde_type_of_resource.source 
            AND mcde_type_of_resource.name = 'type_of_resource')
;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    evergreen.oils_json_to_text(d.title) AS title,
    evergreen.oils_json_to_text(d.author) AS author,
    evergreen.oils_json_to_text(d.publisher) AS publisher,
    evergreen.oils_json_to_text(d.pubdate) AS pubdate,
    CASE WHEN d.isbn = 'null'
        THEN NULL
        ELSE (SELECT ARRAY(SELECT json_array_elements_text(d.isbn::JSON)))
    END AS isbn,
    CASE WHEN d.issn = 'null'
        THEN NULL
        ELSE (SELECT ARRAY(SELECT json_array_elements_text(d.issn::JSON)))
    END AS issn
  FROM  biblio.record_entry r
        JOIN metabib.wide_display_entry d ON (r.id = d.source);

COMMIT;

