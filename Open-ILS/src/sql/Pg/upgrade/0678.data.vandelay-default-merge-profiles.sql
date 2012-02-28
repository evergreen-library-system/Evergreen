-- Evergreen DB patch 0678.data.vandelay-default-merge-profiles.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0678', :eg_version);

INSERT INTO vandelay.merge_profile (owner, name, replace_spec) 
    VALUES (1, 'Match-Only Merge', '901c');

INSERT INTO vandelay.merge_profile (owner, name, preserve_spec) 
    VALUES (1, 'Full Overlay', '901c');


COMMIT;
