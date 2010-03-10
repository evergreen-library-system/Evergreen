BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0185'); -- Scott McKellar

CREATE VIEW action.unfulfilled_hold_max_loop AS
	SELECT  hold,
	        max(count) AS max
	FROM    action.unfulfilled_hold_loops
	GROUP BY 1;

COMMIT;
