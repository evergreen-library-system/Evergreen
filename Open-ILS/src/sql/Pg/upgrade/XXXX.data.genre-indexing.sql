BEGIN;

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, browse_field, facet_field, facet_xpath, joiner ) VALUES
    (33, 'identifier', 'genre', oils_i18n_gettext(33, 'Genre', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='655' or @tag='659']$$, FALSE, TRUE, $$//*[contains('abvxyz',@code)]$$, ' -- ' ); -- /* to fool vim */;

COMMIT;
 
