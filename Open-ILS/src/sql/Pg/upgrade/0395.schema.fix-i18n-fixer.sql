BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0395'); -- Scott McKellar

CREATE OR REPLACE FUNCTION oils_i18n_update_apply(old_ident TEXT, new_ident TEXT, hint TEXT) RETURNS VOID AS $_$
BEGIN

    EXECUTE $$
        UPDATE  config.i18n_core
          SET   identity_value = $$ || quote_literal( new_ident ) || $$ 
          WHERE fq_field LIKE '$$ || hint || $$.%' 
                AND identity_value = $$ || quote_literal( old_ident ) || $$;$$;

    RETURN;

END;
$_$ LANGUAGE PLPGSQL;

COMMIT;
