BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0255'); -- Scott McKellar

ALTER TABLE query.expression
    ADD CONSTRAINT expression_type CHECK
        ( type IN (
            'xbet',
            'xbind',
            'xbool',
            'xcase',
            'xcast',
            'xcol',
            'xex',
            'xfld',
            'xfunc',
            'xin',
            'xnull',
            'xnum',
            'xop',
            'xstr',
            'xsubq'
));

ALTER TABLE query.expression
	DROP CONSTRAINT predicate_type;

ALTER TABLE query.expression
	ADD COLUMN bind_variable TEXT
		REFERENCES query.bind_variable
		DEFERRABLE INITIALLY DEFERRED;

COMMIT;
