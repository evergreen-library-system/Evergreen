BEGIN;

SELECT evergreen.upgrade_deps_block_check('1063', :eg_version);

DO $temp$
DECLARE
	r RECORD;
BEGIN

	FOR r IN SELECT	t.table_schema AS sname,
			t.table_name AS tname,
			t.column_name AS colname,
			t.constraint_name
		  FROM	information_schema.referential_constraints ref
			JOIN information_schema.key_column_usage t USING (constraint_schema,constraint_name)
		  WHERE	ref.unique_constraint_schema = 'asset'
			AND ref.unique_constraint_name = 'copy_pkey'
	LOOP

		EXECUTE 'ALTER TABLE '||r.sname||'.'||r.tname||' DROP CONSTRAINT '||r.constraint_name||';';

		EXECUTE '
			CREATE OR REPLACE FUNCTION evergreen.'||r.sname||'_'||r.tname||'_'||r.colname||'_inh_fkey() RETURNS TRIGGER AS $f$
			BEGIN
				PERFORM 1 FROM asset.copy WHERE id = NEW.'||r.colname||';
				IF NOT FOUND THEN
					RAISE foreign_key_violation USING MESSAGE = FORMAT(
						$$Referenced asset.copy id not found, '||r.colname||':%s$$, NEW.'||r.colname||'
					);
				END IF;
				RETURN NEW;
			END;
			$f$ LANGUAGE PLPGSQL VOLATILE COST 50;
		';

		EXECUTE '
			CREATE CONSTRAINT TRIGGER inherit_'||r.constraint_name||'
				AFTER UPDATE OR INSERT OR DELETE ON '||r.sname||'.'||r.tname||'
				DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.'||r.sname||'_'||r.tname||'_'||r.colname||'_inh_fkey();
		';
	END LOOP;
END
$temp$;

COMMIT;

