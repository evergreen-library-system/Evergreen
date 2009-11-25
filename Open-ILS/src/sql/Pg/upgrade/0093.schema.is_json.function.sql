BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0093'); -- miker

CREATE OR REPLACE FUNCTION is_json (TEXT) RETURNS BOOL AS $func$
    use JSON::XS;
    my $json = shift();
    eval { decode_json( $json ) };
    return $@ ? 0 : 1;
$func$ LANGUAGE PLPERLU;

COMMIT;

