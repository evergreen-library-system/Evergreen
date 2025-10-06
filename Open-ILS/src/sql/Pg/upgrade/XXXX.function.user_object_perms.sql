BEGIN;

ALTER FUNCTION permission.usr_has_home_perm STABLE;
ALTER FUNCTION permission.usr_has_work_perm STABLE;
ALTER FUNCTION permission.usr_has_object_perm ( INT, TEXT, TEXT, TEXT ) STABLE;
ALTER FUNCTION permission.usr_has_perm STABLE;
ALTER FUNCTION permission.usr_has_perm_at_nd STABLE;
ALTER FUNCTION permission.usr_has_perm_at_all_nd STABLE;
ALTER FUNCTION permission.usr_has_perm_at STABLE;
ALTER FUNCTION permission.usr_has_perm_at_all STABLE;

CREATE OR REPLACE FUNCTION permission.usr_has_object_perm ( iuser INT, tperm TEXT, obj_type TEXT, obj_id TEXT, target_ou INT ) RETURNS BOOL AS $$
DECLARE
    r_usr   actor.usr%ROWTYPE;
    r_perm  permission.perm_list%ROWTYPE;
    res     BOOL;
BEGIN

    SELECT * INTO r_usr FROM actor.usr WHERE id = iuser;
    SELECT * INTO r_perm FROM permission.perm_list WHERE code = tperm;

    IF r_usr.active = FALSE THEN
        RETURN FALSE;
    END IF;

    IF r_usr.super_user = TRUE THEN
        RETURN TRUE;
    END IF;

    SELECT TRUE INTO res FROM permission.usr_object_perm_map WHERE perm = r_perm.id AND usr = r_usr.id AND object_type = obj_type AND object_id = obj_id;

    IF FOUND THEN
        RETURN TRUE;
    END IF;

    IF target_ou > -1 THEN
        RETURN permission.usr_has_perm( iuser, tperm, target_ou);
    END IF;

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL STABLE;

-- Start trimming back RULEs, they're starting to make things too hard.  Trigger time!
CREATE OR REPLACE FUNCTION evergreen.raise_protected_row_exception() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Cannot % %.% with % of %', TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME, COALESCE(TG_ARGV[0]::TEXT,'id'), COALESCE(TG_ARGV[1]::TEXT,'-1');
END;
$$ LANGUAGE plpgsql;

DROP RULE IF EXISTS protect_bre_id_neg1 ON biblio.record_entry;
CREATE TRIGGER protect_bre_id_neg1
  BEFORE UPDATE ON biblio.record_entry
  FOR EACH ROW WHEN (NEW.deleted = TRUE AND OLD.deleted = FALSE AND OLD.id = -1)
  EXECUTE PROCEDURE evergreen.raise_protected_row_exception();

DROP RULE IF EXISTS protect_acn_id_neg1 ON asset.call_number;
CREATE TRIGGER protect_acn_id_neg1
  BEFORE UPDATE ON asset.call_number
  FOR EACH ROW WHEN (OLD.id = -1)
  EXECUTE PROCEDURE evergreen.raise_protected_row_exception();

-- Open-ILS/src/sql/Pg/005.schema.actors.sql
CREATE OR REPLACE RULE protect_user_delete AS ON DELETE TO actor.usr DO INSTEAD UPDATE actor.usr SET deleted = TRUE WHERE OLD.id = actor.usr.id RETURNING *;
CREATE OR REPLACE RULE protect_usr_message_delete AS ON DELETE TO actor.usr_message DO INSTEAD UPDATE actor.usr_message SET deleted = TRUE WHERE OLD.id = actor.usr_message.id RETURNING *;

-- Open-ILS/src/sql/Pg/011.schema.authority.sql
CREATE OR REPLACE RULE protect_authority_rec_delete AS ON DELETE TO authority.record_entry DO INSTEAD (UPDATE authority.record_entry SET deleted = TRUE WHERE OLD.id = authority.record_entry.id RETURNING *; DELETE FROM authority.full_rec WHERE record = OLD.id);

-- Open-ILS/src/sql/Pg/040.schema.asset.sql
CREATE OR REPLACE RULE protect_copy_delete AS ON DELETE TO asset.copy DO INSTEAD UPDATE asset.copy SET deleted = TRUE WHERE OLD.id = asset.copy.id RETURNING *;
CREATE OR REPLACE RULE protect_cn_delete AS ON DELETE TO asset.call_number DO INSTEAD UPDATE asset.call_number SET deleted = TRUE WHERE OLD.id = asset.call_number.id RETURNING *;

-- Open-ILS/src/sql/Pg/210.schema.serials.sql
CREATE OR REPLACE RULE protect_mfhd_delete AS ON DELETE TO serial.record_entry DO INSTEAD UPDATE serial.record_entry SET deleted = true WHERE old.id = serial.record_entry.id RETURNING *;
CREATE OR REPLACE RULE protect_serial_unit_delete AS ON DELETE TO serial.unit DO INSTEAD UPDATE serial.unit SET deleted = TRUE WHERE OLD.id = serial.unit.id RETURNING *;

-- Open-ILS/src/sql/Pg/800.fkeys.sql
CREATE OR REPLACE RULE protect_bib_rec_delete AS ON DELETE TO biblio.record_entry DO INSTEAD UPDATE biblio.record_entry SET deleted = TRUE WHERE OLD.id = biblio.record_entry.id RETURNING *;
CREATE OR REPLACE RULE protect_mono_part_delete AS ON DELETE TO biblio.monograph_part DO INSTEAD (UPDATE biblio.monograph_part SET deleted = TRUE WHERE OLD.id = biblio.monograph_part.id RETURNING *; DELETE FROM asset.copy_part_map WHERE part = OLD.id);
CREATE OR REPLACE RULE protect_cn_delete AS ON DELETE TO asset.call_number DO INSTEAD UPDATE asset.call_number SET deleted = TRUE WHERE OLD.id = asset.call_number.id RETURNING *;
CREATE OR REPLACE RULE protect_copy_location_delete AS
    ON DELETE TO asset.copy_location DO INSTEAD (
        SELECT asset.check_delete_copy_location(OLD.id); -- exception on error
        UPDATE asset.copy_location SET deleted = TRUE WHERE OLD.id = asset.copy_location.id RETURNING *;
        UPDATE acq.lineitem_detail SET location = NULL WHERE location = OLD.id;
        DELETE FROM asset.copy_location_order WHERE location = OLD.id;
        DELETE FROM asset.copy_location_group_map WHERE location = OLD.id;
        DELETE FROM config.circ_limit_set_copy_loc_map WHERE copy_loc = OLD.id;
    );

COMMIT;
