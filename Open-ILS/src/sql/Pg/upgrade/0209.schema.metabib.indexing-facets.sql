BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0209');

CREATE INDEX metabib_title_field_entry_value_idx ON metabib.title_field_entry (SUBSTRING(value,1,1024));
CREATE INDEX metabib_author_field_entry_value_idx ON metabib.author_field_entry (SUBSTRING(value,1,1024));
CREATE INDEX metabib_subject_field_entry_value_idx ON metabib.subject_field_entry (SUBSTRING(value,1,1024));
CREATE INDEX metabib_keyword_field_entry_value_idx ON metabib.keyword_field_entry (SUBSTRING(value,1,1024));
CREATE INDEX metabib_series_field_entry_value_idx ON metabib.series_field_entry (SUBSTRING(value,1,1024));

CREATE INDEX metabib_author_field_entry_source_idx ON metabib.author_field_entry (source);
CREATE INDEX metabib_keyword_field_entry_source_idx ON metabib.keyword_field_entry (source);
CREATE INDEX metabib_title_field_entry_source_idx ON metabib.title_field_entry (source);
CREATE INDEX metabib_series_field_entry_source_idx ON metabib.series_field_entry (source);

COMMIT;

