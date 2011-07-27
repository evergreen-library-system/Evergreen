BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXY', :eg_version);

INSERT INTO config.metabib_field (
    id, field_class, name, label, xpath, weight, format,
    search_field, facet_field
) VALUES (
    29, 'identifier', 'lccn', oils_i18n_gettext(29, 'LCCN', 'cmf', 'label'),
    '//marc:datafield[@tag="010"]/marc:subfield[@code="a"]', 1,
    'marcxml', TRUE, FALSE
);

COMMIT;
