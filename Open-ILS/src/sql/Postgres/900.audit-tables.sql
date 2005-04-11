DROP SCHEMA auditor CASCADE;

BEGIN;

CREATE SCHEMA auditor;

CREATE FUNCTION auditor.create_auditor ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
	EXECUTE $$
			CREATE TABLE auditor.$$ || sch || $$_$$ || tbl || $$_history (
				audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
				LIKE $$ || sch || $$.$$ || tbl || $$
			);
	$$;

	EXECUTE $$
			CREATE FUNCTION auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ()
			RETURNS TRIGGER AS $func$
			BEGIN
				INSERT INTO auditor.$$ || sch || $$_$$ || tbl || $$_history
					(NOW(),OLD.*);
				RETURN NEW;
			END;
			$func$ LANGUAGE 'plpgsql';
	$$;

	EXECUTE $$
			CREATE TRIGGER audit_$$ || sch || $$_$$ || tbl || $$_update_trigger
				AFTER UPDATE ON $$ || sch || $$.$$ || tbl || $$ FOR EACH ROW
				EXECUTE PROCEDURE auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ();

			CREATE TRIGGER audit_$$ || sch || $$_$$ || tbl || $$_delete_trigger
				BEFORE DELETE ON $$ || sch || $$.$$ || tbl || $$ FOR EACH ROW
				EXECUTE PROCEDURE auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ();
	$$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

SELECT auditor.create_auditor ( 'actor', 'usr' );
SELECT auditor.create_auditor ( 'biblio', 'record_entry' );
SELECT auditor.create_auditor ( 'asset', 'copy' );

COMMIT;

