-- Evergreen DB patch 0655.config.bib_source.can_have_copies.sql
--
-- This column introduces the ability to prevent bib records associated
-- with specific bib sources from being able to have volumes or MFHD
-- records attached to them.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0655', :eg_version);

ALTER TABLE config.bib_source
ADD COLUMN can_have_copies BOOL NOT NULL DEFAULT TRUE;

COMMIT;
