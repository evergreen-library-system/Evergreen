--Upgrade Script for 2.5.3 to 2.5.4
\set eg_version '''2.5.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.5.4', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0869', :eg_version);

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity_update () RETURNS TRIGGER AS $f$
BEGIN
    NEW.proximity := action.hold_copy_calculated_proximity(NEW.hold,NEW.target_copy);
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER hold_copy_proximity_update_tgr BEFORE INSERT OR UPDATE ON action.hold_copy_map FOR EACH ROW EXECUTE PROCEDURE action.hold_copy_calculated_proximity_update ();

-- Now, cause the update we need in a HOT-friendly manner (http://pgsql.tapoueh.org/site/html/misc/hot.html)
UPDATE action.hold_copy_map SET proximity = proximity WHERE proximity IS NULL;



SELECT evergreen.upgrade_deps_block_check('0877', :eg_version);

-- Don't use Series search field as the browse field
UPDATE config.metabib_field SET
	browse_field = FALSE,
	browse_xpath = NULL,
	browse_sort_xpath = NULL,
	xpath = $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo[not(@type="nfi")]$$
WHERE id = 1;

-- Create a new series browse config
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, search_field, authority_xpath, browse_field, browse_sort_xpath ) VALUES
    (32, 'series', 'browse', oils_i18n_gettext(32, 'Series Title (Browse)', 'cmf', 'label'), 'mods32', $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo[@type="nfi"]$$, FALSE, '//@xlink:href', TRUE, $$*[local-name() != "nonSort"]$$ );


\qecho ---------------------------------------------------------------
\qecho We will now do a "quick fix" indexing of series titles for search.
\qecho .
\qecho Ultimately, a full field-entry reingest of your affected series bib
\qecho records should be done.  It might take a while.
\qecho Something like this should suffice:
\qecho ---------------------------------------------------------------
\qecho 'SELECT COUNT(metabib.reingest_metabib_field_entries(id))'
\qecho '    FROM ('
\qecho '        SELECT DISTINCT(bre.id) AS id'
\qecho '        FROM biblio.record_entry bre'
\qecho '        JOIN metabib.full_rec mfr'
\qecho '            ON mfr.record = bre.id'
\qecho '            AND mfr.tag IN (\'490\', \'800\', \'810\', \'811\', \'830\')'
\qecho '        WHERE'
\qecho '            bre.deleted IS FALSE'
\qecho '            AND ('
\qecho '                mfr.tag = \'490\' AND mfr.subfield = \'a\''
\qecho '                OR mfr.tag IN (\'800\',\'810\',\'811\') AND mfr.subfield = \'t\''
\qecho '                OR mfr.tag = \'830\' AND mfr.subfield IN (\'a\',\'t\')'
\qecho '            )'
\qecho '    ) x'
\qecho ';'
\qecho ---------------------------------------------------------------

-- "Quick Fix" indexing of series for search
INSERT INTO metabib.series_field_entry (field,source,value)
    SELECT 1,record,value FROM metabib.full_rec WHERE tag = '490' AND subfield = 'a';

INSERT INTO metabib.series_field_entry (field,source,value)
    SELECT 1,record,value FROM metabib.full_rec WHERE tag IN ('800','810','811') AND subfield = 't';

INSERT INTO metabib.series_field_entry (field,source,value)
    SELECT 1,record,value FROM metabib.full_rec WHERE tag = '830' AND subfield IN ('a','t');

DELETE FROM metabib.combined_series_field_entry;
INSERT INTO metabib.combined_series_field_entry(record, metabib_field, index_vector)
	SELECT source, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
	FROM metabib.series_field_entry GROUP BY source, field;
INSERT INTO metabib.combined_series_field_entry(record, index_vector)
	SELECT source, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
	FROM metabib.series_field_entry GROUP BY source;
COMMIT;
