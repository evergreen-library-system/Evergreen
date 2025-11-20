/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Copyright (C) 2008  Laurentian University
 * Mike Rylander <miker@esilibrary.com> 
 * Dan Scott <denials@gmail.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

BEGIN;

SELECT evergreen.setup_delete_protect_rule('biblio','record_entry');
CREATE TRIGGER protect_bre_id_neg1 BEFORE UPDATE ON biblio.record_entry FOR EACH ROW WHEN (OLD.id = -1) EXECUTE PROCEDURE evergreen.raise_protected_row_exception();

-- Kill any transaction that tries to mark a copy location as 
-- deleted if the location contains any non-deleted copies.
CREATE OR REPLACE FUNCTION asset.check_delete_copy_location(acpl_id INTEGER) 
    RETURNS VOID AS $FUNK$
BEGIN
    PERFORM TRUE FROM asset.copy WHERE location = acpl_id AND NOT deleted LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Copy location % contains active copies and cannot be deleted', acpl_id;
    END IF;

    IF acpl_id = 1 THEN
        RAISE EXCEPTION
            'Copy location 1 cannot be deleted';
    END IF;
END;
$FUNK$ LANGUAGE plpgsql;

SELECT evergreen.setup_delete_protect_rule(
    'asset', 'copy_location',
    'SELECT asset.check_delete_copy_location(OLD.id);'
      || ' UPDATE acq.lineitem_detail SET location = NULL WHERE location = OLD.id;'
      || ' DELETE FROM asset.copy_location_order WHERE location = OLD.id;'
      || ' DELETE FROM asset.copy_location_group_map WHERE location = OLD.id;'
      || ' DELETE FROM config.circ_limit_set_copy_loc_map WHERE copy_loc = OLD.id;'
);

CREATE OR REPLACE FUNCTION asset.copy_location_validate_edit()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.id = 1 THEN
        IF OLD.owning_lib != NEW.owning_lib OR NEW.deleted THEN
            RAISE EXCEPTION 'Copy location 1 cannot be moved or deleted';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER acpl_validate_edit BEFORE UPDATE ON asset.copy_location FOR EACH ROW EXECUTE PROCEDURE asset.copy_location_validate_edit();

SELECT evergreen.setup_delete_protect_rule('biblio','monograph_part','DELETE FROM asset.copy_part_map WHERE part = OLD.id');

ALTER TABLE actor.usr ADD CONSTRAINT actor_usr_mailing_address_fkey FOREIGN KEY (mailing_address) REFERENCES actor.usr_address (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.usr ADD CONSTRAINT actor_usr_billing_address_fkey FOREIGN KEY (billing_address) REFERENCES actor.usr_address (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.usr ADD CONSTRAINT actor_usr_home_ou_fkey FOREIGN KEY (home_ou) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.usr ADD CONSTRAINT actor_usr_profile_fkey FOREIGN KEY (profile) REFERENCES permission.grp_tree (id) DEFERRABLE INITIALLY DEFERRED;
        
ALTER TABLE actor.stat_cat ADD CONSTRAINT actor_stat_cat_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE actor.stat_cat_entry ADD CONSTRAINT actor_stat_cat_entry_stat_cat_fkey FOREIGN KEY (stat_cat) REFERENCES actor.stat_cat (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.stat_cat_entry ADD CONSTRAINT actor_stat_cat_entry_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE actor.stat_cat_entry_usr_map ADD CONSTRAINT actor_sceum_tu_fkey FOREIGN KEY (target_usr) REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.stat_cat_entry_usr_map ADD CONSTRAINT actor_sceum_sc_fkey FOREIGN KEY (stat_cat) REFERENCES actor.stat_cat (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE actor.org_unit ADD CONSTRAINT actor_org_unit_mailing_address_fkey FOREIGN KEY (mailing_address) REFERENCES actor.org_address (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.org_unit ADD CONSTRAINT actor_org_unit_billing_address_fkey FOREIGN KEY (billing_address) REFERENCES actor.org_address (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.org_unit ADD CONSTRAINT actor_org_unit_holds_address_fkey FOREIGN KEY (holds_address) REFERENCES actor.org_address (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.org_unit ADD CONSTRAINT actor_org_unit_ill_address_fkey FOREIGN KEY (ill_address) REFERENCES actor.org_address (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE actor.org_unit_proximity_adjustment ADD CONSTRAINT actor_org_unit_proximity_adjustment_circ_mod_fkey FOREIGN KEY (circ_mod) REFERENCES config.circ_modifier (code) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE actor.org_unit_proximity_adjustment ADD CONSTRAINT actor_org_unit_proximity_copy_location_fkey FOREIGN KEY (copy_location) REFERENCES asset.copy_location (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.provider ADD CONSTRAINT acq_provider_edi_default_fkey FOREIGN KEY (edi_default) REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE acq.provider ADD CONSTRAINT acq_provider_primary_contact_fkey FOREIGN KEY (primary_contact) REFERENCES acq.provider_contact (id) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE biblio.record_note ADD CONSTRAINT biblio_record_note_record_fkey FOREIGN KEY (record) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE biblio.record_note ADD CONSTRAINT biblio_record_note_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE biblio.record_note ADD CONSTRAINT biblio_record_note_editor_fkey FOREIGN KEY (editor) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE biblio.record_entry ADD CONSTRAINT biblio_record_entry_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE biblio.record_entry ADD CONSTRAINT biblio_record_entry_editor_fkey FOREIGN KEY (editor) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE biblio.record_entry ADD CONSTRAINT biblio_record_entry_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.metarecord ADD CONSTRAINT metabib_metarecord_master_record_fkey FOREIGN KEY (master_record) REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.title_field_entry ADD CONSTRAINT metabib_title_field_entry_source_pkey FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.title_field_entry ADD CONSTRAINT metabib_title_field_entry_field_pkey FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.identifier_field_entry ADD CONSTRAINT metabib_identifier_field_entry_source_pkey FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.identifier_field_entry ADD CONSTRAINT metabib_identifier_field_entry_field_pkey FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.author_field_entry ADD CONSTRAINT metabib_author_field_entry_source_pkey FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.author_field_entry ADD CONSTRAINT metabib_author_field_entry_field_pkey FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.subject_field_entry ADD CONSTRAINT metabib_subject_field_entry_source_pkey FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.subject_field_entry ADD CONSTRAINT metabib_subject_field_entry_field_pkey FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.keyword_field_entry ADD CONSTRAINT metabib_keyword_field_entry_source_pkey FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.keyword_field_entry ADD CONSTRAINT metabib_keyword_field_entry_field_pkey FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.series_field_entry ADD CONSTRAINT metabib_series_field_entry_source_pkey FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.series_field_entry ADD CONSTRAINT metabib_series_field_entry_field_pkey FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.real_full_rec ADD CONSTRAINT metabib_full_rec_record_fkey FOREIGN KEY (record) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.metarecord_source_map ADD CONSTRAINT metabib_metarecord_source_map_source_fkey FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.metarecord_source_map ADD CONSTRAINT metabib_metarecord_source_map_metarecord_fkey FOREIGN KEY (metarecord) REFERENCES metabib.metarecord (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE asset.copy ADD CONSTRAINT asset_copy_call_number_fkey FOREIGN KEY (call_number) REFERENCES asset.call_number (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.copy ADD CONSTRAINT asset_copy_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.copy ADD CONSTRAINT asset_copy_editor_fkey FOREIGN KEY (editor) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_call_number_fkey FOREIGN KEY (call_number) REFERENCES asset.call_number (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_editor_fkey FOREIGN KEY (editor) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

CREATE OR REPLACE FUNCTION evergreen.vandelay_import_item_imported_as_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        IF NEW.imported_as IS NULL THEN
                RETURN NEW;
        END IF;
        PERFORM 1 FROM asset.copy WHERE id = NEW.imported_as;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, imported_as:%s$$, NEW.imported_as
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER inherit_import_item_imported_as_fkey
        AFTER UPDATE OR INSERT ON vandelay.import_item
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.vandelay_import_item_imported_as_inh_fkey();

ALTER TABLE vandelay.bib_queue ADD CONSTRAINT match_bucket_fkey FOREIGN KEY (match_bucket) REFERENCES container.biblio_record_entry_bucket(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

CREATE OR REPLACE FUNCTION evergreen.asset_copy_note_owning_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.owning_copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, owning_copy:%s$$, NEW.owning_copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER inherit_asset_copy_note_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_note
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_note_owning_copy_inh_fkey();

CREATE OR REPLACE FUNCTION evergreen.asset_copy_tag_copy_map_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, copy:%s$$, NEW.copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE OR REPLACE FUNCTION evergreen.asset_copy_alert_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, copy:%s$$, NEW.copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE OR REPLACE FUNCTION evergreen.asset_copy_inventory_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, copy:%s$$, NEW.copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER inherit_asset_copy_alert_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_alert
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_alert_copy_inh_fkey();

CREATE CONSTRAINT TRIGGER inherit_asset_copy_tag_copy_map_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_tag_copy_map
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_tag_copy_map_copy_inh_fkey();

CREATE CONSTRAINT TRIGGER inherit_asset_copy_inventory_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_inventory_copy_inh_fkey();

ALTER TABLE asset.copy_note ADD CONSTRAINT asset_copy_note_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE asset.call_number ADD CONSTRAINT asset_call_number_owning_lib_fkey FOREIGN KEY (owning_lib) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.call_number ADD CONSTRAINT asset_call_number_record_fkey FOREIGN KEY (record) REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.call_number ADD CONSTRAINT asset_call_number_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.call_number ADD CONSTRAINT asset_call_number_editor_fkey FOREIGN KEY (editor) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE asset.call_number_note ADD CONSTRAINT asset_call_number_note_record_fkey FOREIGN KEY (call_number) REFERENCES asset.call_number (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.call_number_note ADD CONSTRAINT asset_call_number_note_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE asset.stat_cat ADD CONSTRAINT a_sc_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE asset.stat_cat_entry ADD CONSTRAINT a_sce_sc_fkey FOREIGN KEY (stat_cat) REFERENCES asset.stat_cat (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.stat_cat_entry ADD CONSTRAINT a_sce_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- ALTER TABLE asset.stat_cat_entry_copy_map ADD CONSTRAINT a_sc_oc_fkey FOREIGN KEY (owning_copy) REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.stat_cat_entry_copy_map ADD CONSTRAINT a_sc_sce_fkey FOREIGN KEY (stat_cat_entry) REFERENCES asset.stat_cat_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.stat_cat_entry_copy_map ADD CONSTRAINT a_sc_sc_fkey FOREIGN KEY (stat_cat) REFERENCES asset.stat_cat (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE money.billable_xact ADD CONSTRAINT money_billable_xact_usr_fkey FOREIGN KEY (usr) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.circulation ADD CONSTRAINT action_circulation_usr_fkey FOREIGN KEY (usr) REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE action.circulation ADD CONSTRAINT action_circulation_circ_lib_fkey FOREIGN KEY (circ_lib) REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
-- ALTER TABLE action.circulation ADD CONSTRAINT action_circulation_target_copy_fkey FOREIGN KEY (target_copy) REFERENCES asset.copy (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.billing_type ADD CONSTRAINT config_billing_type_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.remote_account ADD CONSTRAINT config_remote_account_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.org_unit_setting_type ADD CONSTRAINT view_perm_fkey FOREIGN KEY (view_perm) REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.org_unit_setting_type ADD CONSTRAINT update_perm_fkey FOREIGN KEY (update_perm) REFERENCES permission.perm_list (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.barcode_completion ADD CONSTRAINT config_barcode_completion_org_unit_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX by_heading_and_thesaurus ON authority.record_entry (heading) WHERE deleted IS FALSE or deleted = FALSE;
CREATE INDEX by_heading ON authority.record_entry (simple_heading) WHERE deleted IS FALSE or deleted = FALSE;

ALTER TABLE config.z3950_source ADD CONSTRAINT use_perm_fkey FOREIGN KEY (use_perm) REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.z3950_source_credentials ADD CONSTRAINT z3950_source_creds_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.org_unit_setting_type_log ADD CONSTRAINT config_org_unit_setting_type_log_fkey FOREIGN KEY (org) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.filter_dialog_filter_set
    ADD CONSTRAINT config_filter_dialog_filter_set_owning_lib_fkey
    FOREIGN KEY (owning_lib) REFERENCES actor.org_unit (id)
    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.filter_dialog_filter_set
    ADD CONSTRAINT config_filter_dialog_filter_set_creator_fkey
    FOREIGN KEY (creator) REFERENCES actor.usr (id)
    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.filter_dialog_filter_set
    ADD CONSTRAINT config_filter_dialog_filter_set_filters_check
    CHECK (evergreen.is_json(filters));

ALTER TABLE asset.copy ADD CONSTRAINT asset_copy_floating_fkey FOREIGN KEY (floating) REFERENCES config.floating_group (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.copy_template ADD CONSTRAINT asset_copy_template_floating_fkey FOREIGN KEY (floating) REFERENCES config.floating_group (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.marc_field ADD CONSTRAINT config_marc_field_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.marc_subfield ADD CONSTRAINT config_marc_subfield_owner_fkey FOREIGN KEY (owner) REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.openathens_identity ADD CONSTRAINT config_openathens_identity_ou_fkey
FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


ALTER TABLE config.copy_tag_type ADD CONSTRAINT copy_tag_type_owner_fkey FOREIGN KEY (owner) REFERENCES  actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.print_template ADD CONSTRAINT cpt_owner_fkey 
    FOREIGN KEY (owner) REFERENCES  actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.geolocation_service ADD CONSTRAINT cgs_owner_fkey
    FOREIGN KEY (owner) REFERENCES  actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.ui_staff_portal_page_entry ADD CONSTRAINT cusppe_entry_type_fkey
    FOREIGN KEY (entry_type) REFERENCES  config.ui_staff_portal_page_entry_type(code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.ui_staff_portal_page_entry ADD CONSTRAINT cusppe_owner_fkey
    FOREIGN KEY (owner) REFERENCES  actor.org_unit(id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;
