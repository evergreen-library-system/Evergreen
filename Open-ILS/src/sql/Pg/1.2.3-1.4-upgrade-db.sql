/* Enable LIKE to use an index for database clusters with locales other than C or POSIX */
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (value text_pattern_ops);

/* Upgrade to MODS32 for transforms */
ALTER TABLE config.metabib_field
	ALTER COLUMN format SET DEFAULT 'mods32';
UPDATE config.metabib_field
	SET format = 'mods32';

/* Update index definitions to MODS32-compliant XPaths */
UPDATE config.metabib_field
	SET xpath = $$//mods:mods/mods:name[@type='corporate']/mods:namePart[../mods:role/mods:roleTerm[text()='creator']]$$ 
	WHERE field_class = 'author' AND name = 'corporate';
UPDATE config.metabib_field
	SET xpath = $$//mods:mods/mods:name[@type='personal']/mods:namePart[../mods:role/mods:roleTerm[text()='creator']]$$
	WHERE field_class = 'author' AND name = 'personal';
UPDATE config.metabib_field
	SET xpath = $$//mods:mods/mods:name[@type='conference']/mods:namePart[../mods:role/mods:roleTerm[text()='creator']]$$
	WHERE field_class = 'author' AND name = 'conference';
/* And they all want mods32: as their prefix */
UPDATE config.metabib_field
	SET xpath = regexp_replace(xpath, 'mods:', 'mods32:', 'g');
