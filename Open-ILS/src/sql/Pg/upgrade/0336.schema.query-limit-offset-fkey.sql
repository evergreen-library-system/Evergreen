BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0336'); -- Scott McKellar

ALTER TABLE query.stored_query
    ADD FOREIGN KEY ( limit_count )
    REFERENCES query.expression( id )
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE query.stored_query
    ADD FOREIGN KEY ( offset_count )
    REFERENCES query.expression( id )
    DEFERRABLE INITIALLY DEFERRED;

COMMIT;
