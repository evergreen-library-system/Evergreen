
INSERT INTO config.upgrade_log (version) VALUES ('0377'); -- miker .. no xact needed
CREATE INDEX actor_card_barcode_lower_idx ON actor.card (lower(barcode));

