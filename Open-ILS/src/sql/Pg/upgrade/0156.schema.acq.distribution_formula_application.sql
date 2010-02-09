BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0156'); -- senator

CREATE TABLE acq.distribution_formula_application (
    id BIGSERIAL PRIMARY KEY,
    creator INT NOT NULL REFERENCES actor.usr(id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    formula INT NOT NULL
        REFERENCES acq.distribution_formula(id) DEFERRABLE INITIALLY DEFERRED,
    lineitem INT NOT NULL
        REFERENCES acq.lineitem(id) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX acqdfa_df_idx
    ON acq.distribution_formula_application(formula);
CREATE INDEX acqdfa_li_idx
    ON acq.distribution_formula_application(lineitem);
CREATE INDEX acqdfa_creator_idx
    ON acq.distribution_formula_application(creator);

COMMIT;
