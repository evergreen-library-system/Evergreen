BEGIN;

ALTER TABLE biblio.record_entry ADD CONSTRAINT record_entry_creator_fkey FOREIGN KEY ( creator ) REFERENCES actor.usr (id) ON DELETE RESTRICT;
ALTER TABLE biblio.record_entry ADD CONSTRAINT record_entry_editor_fkey FOREIGN KEY ( editor ) REFERENCES actor.usr (id) ON DELETE RESTRICT;
ALTER TABLE biblio.record_entry ADD CONSTRAINT record_entry_source_fkey FOREIGN KEY ( source ) REFERENCES config.bib_source (id) ON DELETE RESTRICT;

ALTER TABLE biblio.record_data ADD CONSTRAINT record_data_owner_doc_fkey FOREIGN KEY ( owner_doc ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;
--ALTER TABLE biblio.record_data ADD CONSTRAINT record_data_parent_node_fkey FOREIGN KEY ( owner_doc,parent_node )
--	REFERENCES biblio.record_data (owner_doc, intra_doc_id) ON DELETE CASCADE;

ALTER TABLE biblio.record_note ADD CONSTRAINT record_note_record_fkey FOREIGN KEY ( record ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;

COMMIT;
