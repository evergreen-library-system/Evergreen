BEGIN;

SELECT evergreen.upgrade_deps_block_check('0yyy', :eg_version);

-- Not everything in 1XX tags should become part of the authorsort field
-- ($0 for example).  The list of subfields chosen here is a superset of all
-- the fields found in the LoC authority mappin definitions for 1XX fields.
-- Anyway, if more fields should be here, add them.

UPDATE config.record_attr_definition
    SET sf_list = 'abcdefgklmnopqrstvxyz'
    WHERE name='authorsort' AND sf_list IS NULL;

COMMIT;
