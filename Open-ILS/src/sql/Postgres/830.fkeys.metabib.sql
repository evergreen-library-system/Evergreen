BEGIN;

ALTER TABLE metabib.metarecord ADD CONSTRAINT metarecord_master_record_fkey FOREIGN KEY ( master_record ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;

ALTER TABLE metabib.title_field_entry ADD CONSTRAINT title_field_entry_field_fkey FOREIGN KEY ( field )
	REFERENCES config.metabib_field (id) ON DELETE RESTRICT;
ALTER TABLE metabib.author_field_entry ADD CONSTRAINT author_field_entry_field_fkey FOREIGN KEY ( field )
	REFERENCES config.metabib_field (id) ON DELETE RESTRICT;
ALTER TABLE metabib.subject_field_entry ADD CONSTRAINT subject_field_entry_field_fkey FOREIGN KEY ( field )
	REFERENCES config.metabib_field (id) ON DELETE RESTRICT;
ALTER TABLE metabib.keyword_field_entry ADD CONSTRAINT keyword_field_entry_field_fkey FOREIGN KEY ( field )
	REFERENCES config.metabib_field (id) ON DELETE RESTRICT;

ALTER TABLE metabib.full_rec ADD CONSTRAINT full_rec_record_fkey FOREIGN KEY ( record ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;

ALTER TABLE metabib.title_field_entry_source_map ADD CONSTRAINT title_field_entry_source_map_metarecord_fkey FOREIGN KEY ( metarecord ) REFERENCES metabib.metarecord (id) ON DELETE RESTRICT;
ALTER TABLE metabib.title_field_entry_source_map ADD CONSTRAINT title_field_entry_source_map_source_record_fkey FOREIGN KEY ( source_record ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;
ALTER TABLE metabib.title_field_entry_source_map ADD CONSTRAINT title_field_entry_source_map_field_entry_fkey FOREIGN KEY ( field_entry ) REFERENCES metabib.title_field_entry (id) ON DELETE RESTRICT;

ALTER TABLE metabib.author_field_entry_source_map ADD CONSTRAINT author_field_entry_source_map_metarecord_fkey FOREIGN KEY ( metarecord ) REFERENCES metabib.metarecord (id) ON DELETE RESTRICT;
ALTER TABLE metabib.author_field_entry_source_map ADD CONSTRAINT author_field_entry_source_map_source_record_fkey FOREIGN KEY ( source_record ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;
ALTER TABLE metabib.author_field_entry_source_map ADD CONSTRAINT author_field_entry_source_map_field_entry_fkey FOREIGN KEY ( field_entry ) REFERENCES metabib.author_field_entry (id) ON DELETE RESTRICT;

ALTER TABLE metabib.subject_field_entry_source_map ADD CONSTRAINT subject_field_entry_source_map_metarecord_fkey FOREIGN KEY ( metarecord ) REFERENCES metabib.metarecord (id) ON DELETE RESTRICT;
ALTER TABLE metabib.subject_field_entry_source_map ADD CONSTRAINT subject_field_entry_source_map_source_record_fkey FOREIGN KEY ( source_record ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;
ALTER TABLE metabib.subject_field_entry_source_map ADD CONSTRAINT subject_field_entry_source_map_field_entry_fkey FOREIGN KEY ( field_entry ) REFERENCES metabib.subject_field_entry (id) ON DELETE RESTRICT;

ALTER TABLE metabib.keyword_field_entry_source_map ADD CONSTRAINT keyword_field_entry_source_map_metarecord_fkey FOREIGN KEY ( metarecord ) REFERENCES metabib.metarecord (id) ON DELETE RESTRICT;
ALTER TABLE metabib.keyword_field_entry_source_map ADD CONSTRAINT keyword_field_entry_source_map_source_record_fkey FOREIGN KEY ( source_record ) REFERENCES biblio.record_entry (id) ON DELETE RESTRICT;
ALTER TABLE metabib.keyword_field_entry_source_map ADD CONSTRAINT keyword_field_entry_source_map_field_entry_fkey FOREIGN KEY ( field_entry ) REFERENCES metabib.keyword_field_entry (id) ON DELETE RESTRICT;

COMMIT;
