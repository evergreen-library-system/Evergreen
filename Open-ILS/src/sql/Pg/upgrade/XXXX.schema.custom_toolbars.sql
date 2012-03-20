
CREATE TABLE actor.toolbar (
    id          BIGSERIAL   PRIMARY KEY,
    ws          INT         REFERENCES actor.workstation (id) ON DELETE CASCADE,
    org         INT         REFERENCES actor.org_unit (id) ON DELETE CASCADE,
    usr         INT         REFERENCES actor.usr (id) ON DELETE CASCADE,
    label       TEXT        NOT NULL,
    layout      TEXT        NOT NULL,
       CONSTRAINT label_once_per_ws UNIQUE (ws, label) WHERE ws IS NOT NULL,
       CONSTRAINT label_once_per_org UNIQUE (org, label) WHERE org IS NOT NULL,
       CONSTRAINT label_once_per_usr UNIQUE (usr, label) WHERE usr IS NOT NULL,
    CONSTRAINT only_one_type CHECK (
        (ws IS NOT NULL AND COALESCE(org,usr) IS NULL) OR
        (org IS NOT NULL AND COALESCE(ws,usr) IS NULL) OR
        (usr IS NOT NULL AND COALESCE(org,ws) IS NULL)
    ),
    CONSTRAINT layout_must_be_json CHECK ( is_json(layout) )
);

