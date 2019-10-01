BEGIN;

SELECT evergreen.upgrade_deps_block_check('1189', :eg_version);

CREATE OR REPLACE VIEW action.open_circulation AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	checkin_time IS NULL
	  ORDER BY due_date;

CREATE OR REPLACE VIEW action.billable_circulations AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	xact_finish IS NULL;

CREATE OR REPLACE VIEW reporter.overdue_circs AS
SELECT  *
  FROM  "action".circulation
  WHERE checkin_time is null
        AND (stop_fines NOT IN ('LOST','CLAIMSRETURNED') OR stop_fines IS NULL)
        AND due_date < now();

CREATE OR REPLACE VIEW reporter.circ_type AS
SELECT	id,
	CASE WHEN opac_renewal OR phone_renewal OR desk_renewal OR auto_renewal
		THEN 'RENEWAL'
		ELSE 'CHECKOUT'
	END AS "type"
  FROM	action.circulation;

COMMIT;
