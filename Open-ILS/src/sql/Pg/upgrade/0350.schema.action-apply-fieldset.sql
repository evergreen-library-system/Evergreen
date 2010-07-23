BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0350'); -- Scott McKellar

CREATE OR REPLACE FUNCTION action.apply_fieldset(
	fieldset_id IN INT,        -- id from action.fieldset
	table_name  IN TEXT,       -- table to be updated
	pkey_name   IN TEXT,       -- name of primary key column in that table
	query       IN TEXT        -- query constructed by qstore (for query-based
	                           --    fieldsets only; otherwise null
)
RETURNS TEXT AS $$
DECLARE
	statement TEXT;
	fs_status TEXT;
	fs_pkey_value TEXT;
	fs_query TEXT;
	sep CHAR;
	status_code TEXT;
	msg TEXT;
	update_count INT;
	cv RECORD;
BEGIN
	-- Sanity checks
	IF fieldset_id IS NULL THEN
		RETURN 'Fieldset ID parameter is NULL';
	END IF;
	IF table_name IS NULL THEN
		RETURN 'Table name parameter is NULL';
	END IF;
	IF pkey_name IS NULL THEN
		RETURN 'Primary key name parameter is NULL';
	END IF;
	--
	statement := 'UPDATE ' || table_name || ' SET';
	--
	SELECT
		status,
		quote_literal( pkey_value )
	INTO
		fs_status,
		fs_pkey_value
	FROM
		action.fieldset
	WHERE
		id = fieldset_id;
	--
	IF fs_status IS NULL THEN
		RETURN 'No fieldset found for id = ' || fieldset_id;
	ELSIF fs_status = 'APPLIED' THEN
		RETURN 'Fieldset ' || fieldset_id || ' has already been applied';
	END IF;
	--
	sep := '';
	FOR cv IN
		SELECT  col,
				val
		FROM    action.fieldset_col_val
		WHERE   fieldset = fieldset_id
	LOOP
		statement := statement || sep || ' ' || cv.col
					 || ' = ' || coalesce( quote_literal( cv.val ), 'NULL' );
		sep := ',';
	END LOOP;
	--
	IF sep = '' THEN
		RETURN 'Fieldset ' || fieldset_id || ' has no column values defined';
	END IF;
	--
	-- Add the WHERE clause.  This differs according to whether it's a
	-- single-row fieldset or a query-based fieldset.
	--
	IF query IS NULL        AND fs_pkey_value IS NULL THEN
		RETURN 'Incomplete fieldset: neither a primary key nor a query available';
	ELSIF query IS NOT NULL AND fs_pkey_value IS NULL THEN
	    fs_query := rtrim( query, ';' );
	    statement := statement || ' WHERE ' || pkey_name || ' IN ( '
	                 || fs_query || ' );';
	ELSIF query IS NULL     AND fs_pkey_value IS NOT NULL THEN
		statement := statement || ' WHERE ' || pkey_name || ' = '
				     || fs_pkey_value || ';';
	ELSE  -- both are not null
		RETURN 'Ambiguous fieldset: both a primary key and a query provided';
	END IF;
	--
	-- Execute the update
	--
	BEGIN
		EXECUTE statement;
		GET DIAGNOSTICS update_count = ROW_COUNT;
		--
		IF UPDATE_COUNT > 0 THEN
			status_code := 'APPLIED';
			msg := NULL;
		ELSE
			status_code := 'ERROR';
			msg := 'No eligible rows found for fieldset ' || fieldset_id;
    	END IF;
	EXCEPTION WHEN OTHERS THEN
		status_code := 'ERROR';
		msg := 'Unable to apply fieldset ' || fieldset_id
			   || ': ' || sqlerrm;
	END;
	--
	-- Update fieldset status
	--
	UPDATE action.fieldset
	SET status       = status_code,
	    applied_time = now()
	WHERE id = fieldset_id;
	--
	RETURN msg;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION action.apply_fieldset( INT, TEXT, TEXT, TEXT ) IS $$
/**
 * Applies a specified fieldset, using a supplied table name and primary
 * key name.  The query parameter should be non-null only for
 * query-based fieldsets.
 *
 * Returns NULL if successful, or an error message if not.
 */
$$;

COMMIT;
