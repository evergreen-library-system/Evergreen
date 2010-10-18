
-- No transaction, just creating indexes if they don't exist

INSERT INTO config.upgrade_log (version) VALUES ('0398'); -- miker

CREATE INDEX serial_subscription_record_idx ON serial.subscription (record_entry);
CREATE INDEX serial_subscription_owner_idx ON serial.subscription (owning_lib);
CREATE INDEX serial_caption_and_pattern_sub_idx ON serial.caption_and_pattern (subscription);
CREATE INDEX serial_distribution_sub_idx ON serial.distribution (subscription);
CREATE INDEX serial_distribution_holding_lib_idx ON serial.distribution (holding_lib);
CREATE INDEX serial_distribution_note_dist_idx ON serial.distribution_note (distribution);
CREATE INDEX serial_stream_dist_idx ON serial.stream (distribution);
CREATE INDEX serial_routing_list_user_stream_idx ON serial.routing_list_user (stream);
CREATE INDEX serial_routing_list_user_reader_idx ON serial.routing_list_user (reader);
CREATE INDEX serial_issuance_sub_idx ON serial.issuance (subscription);
CREATE INDEX serial_issuance_caption_and_pattern_idx ON serial.issuance (caption_and_pattern);
CREATE INDEX serial_issuance_date_published_idx ON serial.issuance (date_published);
CREATE UNIQUE INDEX unit_barcode_key ON serial.unit (barcode) WHERE deleted = FALSE OR deleted IS FALSE;
CREATE INDEX unit_cn_idx ON serial.unit (call_number);
CREATE INDEX unit_avail_cn_idx ON serial.unit (call_number);
CREATE INDEX unit_creator_idx  ON serial.unit ( creator );
CREATE INDEX unit_editor_idx   ON serial.unit ( editor );
CREATE INDEX serial_item_stream_idx ON serial.item (stream);
CREATE INDEX serial_item_issuance_idx ON serial.item (issuance);
CREATE INDEX serial_item_unit_idx ON serial.item (unit);
CREATE INDEX serial_item_uri_idx ON serial.item (uri);
CREATE INDEX serial_item_date_received_idx ON serial.item (date_received);
CREATE INDEX serial_item_status_idx ON serial.item (status);
CREATE INDEX serial_item_note_item_idx ON serial.item_note (item);
CREATE INDEX serial_basic_summary_dist_idx ON serial.basic_summary (distribution);
CREATE INDEX serial_supplement_summary_dist_idx ON serial.supplement_summary (distribution);
CREATE INDEX serial_index_summary_dist_idx ON serial.index_summary (distribution);
 
