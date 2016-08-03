BEGIN;

CREATE TABLE staging.setting_stage (
        row_id          BIGSERIAL PRIMARY KEY,
        row_date        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,
        setting         TEXT NOT NULL,
        value           TEXT NOT NULL,
        complete        BOOL DEFAULT FALSE
);

COMMIT;
