BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('0952', :eg_version); --miker/kmlussier/gmcharlt

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, browse_field, facet_field, facet_xpath, joiner ) VALUES
    (33, 'identifier', 'genre', oils_i18n_gettext(33, 'Genre', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='655']$$, FALSE, TRUE, $$//*[local-name()='subfield' and contains('abvxyz',@code)]$$, ' -- ' ); -- /* to fool vim */;

INSERT INTO config.metabib_field_index_norm_map (field,norm)
    SELECT  m.id,
            i.id
      FROM  config.metabib_field m,
        config.index_normalizer i
      WHERE i.func IN ('search_normalize','split_date_range')
            AND m.id IN (33);

COMMIT;

\qecho
\qecho To use the new identifier|genre index, it is necessary to do
\qecho a partial reingest.  For example,
\qecho
\qecho SELECT metabib.reingest_metabib_field_entries(record, FALSE, TRUE, FALSE)
\qecho FROM metabib.real_full_rec
\qecho WHERE tag IN (''''655'''')
\qecho GROUP BY record; 
\qecho
