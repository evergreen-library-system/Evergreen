ALTER TABLE config.bib_source
ADD COLUMN can_have_copies BOOL NOT NULL DEFAULT TRUE;
