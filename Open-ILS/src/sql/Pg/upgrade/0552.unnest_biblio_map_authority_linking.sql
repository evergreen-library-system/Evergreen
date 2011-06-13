-- Evergreen DB patch 0552.unnest_biblio_map_authority_linking.sql
--
-- Replace usage of custom explode_array() function with native unnest()
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0552', :eg_version);

CREATE OR REPLACE FUNCTION biblio.map_authority_linking (bibid BIGINT, marc TEXT) RETURNS BIGINT AS $func$
    DELETE FROM authority.bib_linking WHERE bib = $1;
    INSERT INTO authority.bib_linking (bib, authority)
        SELECT  y.bib,
                y.authority
          FROM (    SELECT  DISTINCT $1 AS bib,
                            BTRIM(remove_paren_substring(txt))::BIGINT AS authority
                      FROM  unnest(oils_xpath('//*[@code="0"]/text()',$2)) x(txt)
                      WHERE BTRIM(remove_paren_substring(txt)) ~ $re$^\d+$$re$
                ) y JOIN authority.record_entry r ON r.id = y.authority;
    SELECT $1;
$func$ LANGUAGE SQL;

COMMIT;
