BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0505'); --miker

CREATE OR REPLACE FUNCTION force_unicode_normal_form(string TEXT, form TEXT) RETURNS TEXT AS $func$
use Unicode::Normalize 'normalize';
return normalize($_[1],$_[0]); # reverse the params
$func$ LANGUAGE PLPERLU;

UPDATE metabib.facet_entry SET value = force_unicode_normal_form(value,'NFC');

CREATE OR REPLACE FUNCTION facet_force_nfc() RETURNS TRIGGER AS $$
BEGIN
    NEW.value := force_unicode_normal_form(NEW.value,'NFC');
    RETURN NEW;
END;
$$ LANUAGE PLPGSQL;

CREATE TRIGGER facet_force_nfc_tgr
	BEFORE UPDATE OR INSERT ON metabib.facet_entry
	FOR EACH ROW EXECUTE PROCEDURE facet_force_nfc();

COMMIT;

