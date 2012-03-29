ALTER TABLE config.coded_value_map
    ADD COLUMN opac_visible BOOL NOT NULL DEFAULT TRUE,
    ADD COLUMN search_label TEXT;
