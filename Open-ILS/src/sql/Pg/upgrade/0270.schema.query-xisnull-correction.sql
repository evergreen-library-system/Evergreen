BEGIN;

-- Create new expression type for IS [NOT] NULL

INSERT INTO config.upgrade_log (version) VALUES ('0270'); -- Scott McKellar

ALTER TABLE query.expression
	DROP CONSTRAINT expression_type;

ALTER TABLE query.expression
	ADD CONSTRAINT expression_type CHECK
    ( type IN (
		'xbet',    -- between
		'xbind',   -- bind variable
		'xbool',   -- boolean
		'xcase',   -- case
		'xcast',   -- cast
		'xcol',    -- column
		'xex',     -- exists
		'xfld',    -- field
		'xfunc',   -- function
		'xin',     -- in
		'xisnull', -- is null
		'xnull',   -- null
		'xnum',    -- number
		'xop',     -- operator
		'xstr',    -- string
		'xsubq'    -- subquery
	) );

COMMIT;
