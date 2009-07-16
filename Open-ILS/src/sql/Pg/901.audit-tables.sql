/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
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

SELECT auditor.create_auditor ( 'actor', 'usr' );
CREATE INDEX aud_actor_usr_hist_id_idx            ON auditor.actor_usr_history ( id );

SELECT auditor.create_auditor ( 'actor', 'usr_address' );
CREATE INDEX aud_actor_usr_address_hist_id_idx    ON auditor.actor_usr_address_history ( id );

SELECT auditor.create_auditor ( 'actor', 'org_unit' );

SELECT auditor.create_auditor ( 'biblio', 'record_entry' );
CREATE INDEX aud_bib_rec_entry_hist_creator_idx   ON auditor.biblio_record_entry_history ( creator );
CREATE INDEX aud_bib_rec_entry_hist_editor_idx    ON auditor.biblio_record_entry_history ( editor );

SELECT auditor.create_auditor ( 'asset', 'call_number' );
CREATE INDEX aud_asset_cn_hist_creator_idx        ON auditor.asset_call_number_history ( creator );
CREATE INDEX aud_asset_cn_hist_editor_idx         ON auditor.asset_call_number_history ( editor );

SELECT auditor.create_auditor ( 'asset', 'copy' );
CREATE INDEX aud_asset_cp_hist_creator_idx        ON auditor.asset_copy_history ( creator );
CREATE INDEX aud_asset_cp_hist_editor_idx         ON auditor.asset_copy_history ( editor );

COMMIT;

