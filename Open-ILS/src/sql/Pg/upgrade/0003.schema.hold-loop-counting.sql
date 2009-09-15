BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0003.schema.hold-loop-counting.sql');

CREATE OR REPLACE VIEW action.unfulfilled_hold_loops AS
    SELECT  u.hold,
            c.circ_lib,
            count(*)
      FROM  action.unfulfilled_hold_list u
            JOIN asset.copy c ON (c.id = u.current_copy)
      GROUP BY 1,2;

CREATE OR REPLACE VIEW action.unfulfilled_hold_min_loop AS
    SELECT  hold,
            min(count)
      FROM  action.unfulfilled_hold_loops
      GROUP BY 1;

CREATE OR REPLACE VIEW action.unfulfilled_hold_innermost_loop AS
    SELECT  DISTINCT l.*
      FROM  action.unfulfilled_hold_loops l
            JOIN action.unfulfilled_hold_min_loop m USING (hold)
      WHERE l.count = m.min;


COMMIT;
