/*
 * Copyright (C) 2010  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
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

INSERT INTO config.upgrade_log (version) VALUES ('1.6.0.1');

CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DECLARE x RECORD;
    BEGIN
        -- DROP TRIGGER IF EXISTS is only available starting with PostgreSQL 8.2
        FOR x IN SELECT tgname FROM pg_trigger WHERE tgname = 'zzz_update_materialized_simple_record_tgr'
        LOOP
            DROP TRIGGER zzz_update_materialized_simple_record_tgr ON metabib.real_full_rec;
        END LOOP;
    END;
$$ LANGUAGE plpgsql;

ALTER TABLE permission.grp_penalty_threshold DROP CONSTRAINT penalty_grp_once;
ALTER TABLE permission.grp_penalty_threshold ADD CONSTRAINT penalty_grp_once UNIQUE (grp,penalty,org_unit); 

CREATE OR REPLACE FUNCTION vandelay.ingest_bib_items ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr_def    BIGINT;
    item_data   vandelay.import_item%ROWTYPE;
BEGIN

    SELECT item_attr_def INTO attr_def FROM vandelay.bib_queue WHERE id = NEW.queue;

    FOR item_data IN SELECT * FROM vandelay.ingest_items( NEW.id::BIGINT, attr_def ) LOOP
        INSERT INTO vandelay.import_item (
            record,
            definition,
            owning_lib,
            circ_lib,
            call_number,
            copy_number,
            status,
            location,
            circulate,
            deposit,
            deposit_amount,
            ref,
            holdable,
            price,
            barcode,
            circ_modifier,
            circ_as_type,
            alert_message,
            pub_note,
            priv_note,
            opac_visible
        ) VALUES (
            NEW.id,
            item_data.definition,
            item_data.owning_lib,
            item_data.circ_lib,
            item_data.call_number,
            item_data.copy_number,
            item_data.status,
            item_data.location,
            item_data.circulate,
            item_data.deposit,
            item_data.deposit_amount,
            item_data.ref,
            item_data.holdable,
            item_data.price,
            item_data.barcode,
            item_data.circ_modifier,
            item_data.circ_as_type,
            item_data.alert_message,
            item_data.pub_note,
            item_data.priv_note,
            item_data.opac_visible
        );
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

UPDATE config.z3950_attr SET truncation = 1 WHERE source = 'biblios' AND name = 'title';

COMMIT;

INSERT INTO config.i18n_locale (code,marc_code,name,description)
    VALUES ('cs-CZ', 'cze', oils_i18n_gettext('cs-CZ', 'Czech', 'i18n_l', 'name'), oils_i18n_gettext('cs-CZ', 'Czech', 'i18n_l', 'description'));
INSERT INTO config.i18n_locale (code,marc_code,name,description)
    VALUES ('ru-RU', 'rus', oils_i18n_gettext('ru-RU', 'Russian', 'i18n_l', 'name'), oils_i18n_gettext('ru-RU', 'Russian', 'i18n_l', 'description'));

CREATE RULE protect_mfhd_delete AS ON DELETE TO serial.record_entry DO INSTEAD UPDATE serial.record_entry SET deleted = true WHERE old.id = serial.record_entry.id;

INSERT INTO permission.perm_list (code) VALUES ('MERGE_USERS');


