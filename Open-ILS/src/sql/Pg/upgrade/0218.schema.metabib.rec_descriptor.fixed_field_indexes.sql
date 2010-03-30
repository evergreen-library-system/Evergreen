BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0218'); --miker

CREATE INDEX metabib_rec_descriptor_item_type_idx ON metabib.rec_descriptor (item_type);
CREATE INDEX metabib_rec_descriptor_item_form_idx ON metabib.rec_descriptor (item_form);
CREATE INDEX metabib_rec_descriptor_bib_level_idx ON metabib.rec_descriptor (bib_level);
CREATE INDEX metabib_rec_descriptor_control_type_idx ON metabib.rec_descriptor (control_type);
CREATE INDEX metabib_rec_descriptor_char_encoding_idx ON metabib.rec_descriptor (char_encoding);
CREATE INDEX metabib_rec_descriptor_enc_level_idx ON metabib.rec_descriptor (enc_level);
CREATE INDEX metabib_rec_descriptor_audience_idx ON metabib.rec_descriptor (audience);
CREATE INDEX metabib_rec_descriptor_lit_form_idx ON metabib.rec_descriptor (lit_form);
CREATE INDEX metabib_rec_descriptor_cat_form_idx ON metabib.rec_descriptor (cat_form);
CREATE INDEX metabib_rec_descriptor_pub_status_idx ON metabib.rec_descriptor (pub_status);
CREATE INDEX metabib_rec_descriptor_item_lang_idx ON metabib.rec_descriptor (item_lang);
CREATE INDEX metabib_rec_descriptor_vr_format_idx ON metabib.rec_descriptor (vr_format);
CREATE INDEX metabib_rec_descriptor_date1_idx ON metabib.rec_descriptor (date1);
CREATE INDEX metabib_rec_descriptor_dates_idx ON metabib.rec_descriptor (date1,date2);

COMMIT;

