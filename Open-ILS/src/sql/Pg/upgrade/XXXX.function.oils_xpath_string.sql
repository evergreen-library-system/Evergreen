BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.oils_xpath_string(text, text, text, anyarray) RETURNS text
AS $F$
    SELECT  ARRAY_TO_STRING(
                oils_xpath(
                    $1 ||
                        CASE WHEN $1 ~ $re$/[^/[]*@[^]]+$$re$ OR $1 ~ $re$\)$$re$ THEN '' ELSE '//text()' END,
                    $2,
                    $4
                ),
                $3
            );
$F$ LANGUAGE SQL IMMUTABLE;

COMMIT;

