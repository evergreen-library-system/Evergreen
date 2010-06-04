BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0293'); -- Scott McKellar

CREATE OR REPLACE FUNCTION config.interval_to_seconds( interval_val INTERVAL )
RETURNS INTEGER AS $$
BEGIN
	RETURN EXTRACT( EPOCH FROM interval_val );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION config.interval_to_seconds( interval_string TEXT )
RETURNS INTEGER AS $$
BEGIN
	RETURN config.interval_to_seconds( interval_string::INTERVAL );
END;
$$ LANGUAGE plpgsql;

COMMIT;
