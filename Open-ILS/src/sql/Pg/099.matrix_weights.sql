
BEGIN;

-- Circ Matrix Weights
CREATE TABLE config.circ_matrix_weights (
    id                      SERIAL  PRIMARY KEY,
    name                    TEXT    NOT NULL UNIQUE,
    org_unit                NUMERIC(6,2)   NOT NULL,
    grp                     NUMERIC(6,2)   NOT NULL,
    circ_modifier           NUMERIC(6,2)   NOT NULL,
    copy_location           NUMERIC(6,2)   NOT NULL,
    marc_type               NUMERIC(6,2)   NOT NULL,
    marc_form               NUMERIC(6,2)   NOT NULL,
    marc_bib_level          NUMERIC(6,2)   NOT NULL,
    marc_vr_format          NUMERIC(6,2)   NOT NULL,
    copy_circ_lib           NUMERIC(6,2)   NOT NULL,
    copy_owning_lib         NUMERIC(6,2)   NOT NULL,
    user_home_ou            NUMERIC(6,2)   NOT NULL,
    ref_flag                NUMERIC(6,2)   NOT NULL,
    juvenile_flag           NUMERIC(6,2)   NOT NULL,
    is_renewal              NUMERIC(6,2)   NOT NULL,
    usr_age_lower_bound     NUMERIC(6,2)   NOT NULL,
    usr_age_upper_bound     NUMERIC(6,2)   NOT NULL,
    item_age                NUMERIC(6,2)   NOT NULL
);

-- Hold Matrix Weights
CREATE TABLE config.hold_matrix_weights (
    id                      SERIAL  PRIMARY KEY,
    name                    TEXT    NOT NULL UNIQUE,
    user_home_ou            NUMERIC(6,2)   NOT NULL,
    request_ou              NUMERIC(6,2)   NOT NULL,
    pickup_ou               NUMERIC(6,2)   NOT NULL,
    item_owning_ou          NUMERIC(6,2)   NOT NULL,
    item_circ_ou            NUMERIC(6,2)   NOT NULL,
    usr_grp                 NUMERIC(6,2)   NOT NULL,
    requestor_grp           NUMERIC(6,2)   NOT NULL,
    circ_modifier           NUMERIC(6,2)   NOT NULL,
    marc_type               NUMERIC(6,2)   NOT NULL,
    marc_form               NUMERIC(6,2)   NOT NULL,
    marc_bib_level          NUMERIC(6,2)   NOT NULL,
    marc_vr_format          NUMERIC(6,2)   NOT NULL,
    juvenile_flag           NUMERIC(6,2)   NOT NULL,
    ref_flag                NUMERIC(6,2)   NOT NULL,
    item_age                NUMERIC(6,2)   NOT NULL
);

-- Linking between weights and org units
CREATE TABLE config.weight_assoc (
    id                      SERIAL  PRIMARY KEY,
    active                  BOOL    NOT NULL,
    org_unit                INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    circ_weights            INT     REFERENCES config.circ_matrix_weights (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    hold_weights            INT     REFERENCES config.hold_matrix_weights (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
);
CREATE UNIQUE INDEX cwa_one_active_per_ou ON config.weight_assoc (org_unit) WHERE active;

COMMIT;
