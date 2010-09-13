BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0393'); -- miker

CREATE OR REPLACE FUNCTION oils_i18n_update_apply(old_ident TEXT, new_ident TEXT, hint TEXT) RETURNS VOID AS $_$
BEGIN

    EXECUTE $$
        UPDATE  config.i18n_core
          SET   identity_value = $$ || new_ident || $$ 
          WHERE fq_field LIKE '$$ || hint || $$.%' 
                AND identity_value = $$ || old_ident || $$;$$;

    RETURN;

END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_i18n_id_tracking(/* hint */) RETURNS TRIGGER AS $_$
BEGIN
    PERFORM oils_i18n_update_apply( OLD.id::TEXT, NEW.id::TEXT, TG_ARGV[0]::TEXT );
    RETURN NEW;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_i18n_code_tracking(/* hint */) RETURNS TRIGGER AS $_$
BEGIN
    PERFORM oils_i18n_update_apply( OLD.code::TEXT, NEW.code::TEXT, TG_ARGV[0]::TEXT );
    RETURN NEW;
END;
$_$ LANGUAGE PLPGSQL;


CREATE TRIGGER maintain_perm_i18n_tgr
    AFTER UPDATE ON permission.perm_list
    FOR EACH ROW EXECUTE PROCEDURE oils_i18n_id_tracking('ppl');

COMMIT;
