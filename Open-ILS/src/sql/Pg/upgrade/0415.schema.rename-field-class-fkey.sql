-- Dropping and recreating a foreign key constraint for config.metabib_field,
-- in order to change its name.  WHen this foreign key was first introduced,
-- the upgrade script gave it one name and the base install script gave it
-- a different name.  Here we bring the names into sync.

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0415'); -- Scott McKellar

\qecho Dropping and recreating a foreign key in order to change its name.
\qecho If the DROP fails because the constraint doesn't exist under the old
\qecho name, or the ADD fails because it already exists under the new name,
\qecho then ignore the failure.

ALTER TABLE config.metabib_field
	DROP CONSTRAINT field_class_fkey;

ALTER TABLE config.metabib_field
	ADD CONSTRAINT metabib_field_field_class_fkey
	FOREIGN KEY (field_class) REFERENCES config.metabib_class(name);

COMMIT;
