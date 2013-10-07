BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0838', :eg_version);

DELETE FROM config.metabib_field_index_norm_map
    WHERE field = 25 AND norm IN (
        SELECT id
        FROM config.index_normalizer
        WHERE func IN ('search_normalize','split_date_range')
    );

\qecho If your site's bibcn searches are affected by this issue, you may wish
\qecho to reingest your bib records now.  It's probably not worth it for many
\qecho sites.

COMMIT;
