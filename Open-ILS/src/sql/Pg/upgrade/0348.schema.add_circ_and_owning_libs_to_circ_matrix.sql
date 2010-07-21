
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0348'); --miker

ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT ep_once_per_grp_loc_mod_marc;

ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN copy_circ_lib   INT REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN copy_owning_lib INT REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.circ_matrix_matchpoint ADD CONSTRAINT ep_once_per_grp_loc_mod_marc UNIQUE (
    grp, org_unit, circ_modifier, marc_type, marc_form, marc_vr_format, ref_flag,
    juvenile_flag, usr_age_lower_bound, usr_age_upper_bound, is_renewal, copy_circ_lib,
    copy_owning_lib
);


CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS config.circ_matrix_matchpoint AS $func$
DECLARE
    current_group    permission.grp_tree%ROWTYPE;
    user_object    actor.usr%ROWTYPE;
    item_object    asset.copy%ROWTYPE;
    cn_object    asset.call_number%ROWTYPE;
    rec_descriptor    metabib.rec_descriptor%ROWTYPE;
    current_mp    config.circ_matrix_matchpoint%ROWTYPE;
    matchpoint    config.circ_matrix_matchpoint%ROWTYPE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
    SELECT INTO cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r JOIN asset.call_number c USING (record) WHERE c.id = item_object.call_number;
    SELECT INTO current_group * FROM permission.grp_tree WHERE id = user_object.profile;

    LOOP
        -- for each potential matchpoint for this ou and group ...
        FOR current_mp IN
            SELECT  m.*
              FROM  config.circ_matrix_matchpoint m
                    JOIN actor.org_unit_ancestors( context_ou ) d ON (m.org_unit = d.id)
                    LEFT JOIN actor.org_unit_proximity p ON (p.from_org = context_ou AND p.to_org = d.id)
              WHERE m.grp = current_group.id
                    AND m.active
                    AND (m.copy_owning_lib IS NULL OR cn_object.owning_lib IN ( SELECT id FROM actor.org_unit_descendants(m.copy_owning_lib) ))
                    AND (m.copy_circ_lib   IS NULL OR item_object.circ_lib IN ( SELECT id FROM actor.org_unit_descendants(m.copy_circ_lib)   ))
              ORDER BY    CASE WHEN p.prox        IS NULL THEN 999 ELSE p.prox END,
                    CASE WHEN m.copy_owning_lib IS NOT NULL
                        THEN 256 / ( SELECT COALESCE(prox, 255) + 1 FROM actor.org_unit_proximity WHERE to_org = cn_object.owning_lib AND from_org = m.copy_owning_lib LIMIT 1 )
                        ELSE 0
                    END +
                    CASE WHEN m.copy_circ_lib IS NOT NULL
                        THEN 256 / ( SELECT COALESCE(prox, 255) + 1 FROM actor.org_unit_proximity WHERE to_org = item_object.circ_lib AND from_org = m.copy_circ_lib LIMIT 1 )
                        ELSE 0
                    END +
                    CASE WHEN m.is_renewal = renewal        THEN 128 ELSE 0 END +
                    CASE WHEN m.juvenile_flag    IS NOT NULL THEN 64 ELSE 0 END +
                    CASE WHEN m.circ_modifier    IS NOT NULL THEN 32 ELSE 0 END +
                    CASE WHEN m.marc_type        IS NOT NULL THEN 16 ELSE 0 END +
                    CASE WHEN m.marc_form        IS NOT NULL THEN 8 ELSE 0 END +
                    CASE WHEN m.marc_vr_format    IS NOT NULL THEN 4 ELSE 0 END +
                    CASE WHEN m.ref_flag        IS NOT NULL THEN 2 ELSE 0 END +
                    CASE WHEN m.usr_age_lower_bound    IS NOT NULL THEN 0.5 ELSE 0 END +
                    CASE WHEN m.usr_age_upper_bound    IS NOT NULL THEN 0.5 ELSE 0 END DESC LOOP

            IF current_mp.circ_modifier IS NOT NULL THEN
                CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier OR item_object.circ_modifier IS NULL;
            END IF;

            IF current_mp.marc_type IS NOT NULL THEN
                IF item_object.circ_as_type IS NOT NULL THEN
                    CONTINUE WHEN current_mp.marc_type <> item_object.circ_as_type;
                ELSE
                    CONTINUE WHEN current_mp.marc_type <> rec_descriptor.item_type;
                END IF;
            END IF;

            IF current_mp.marc_form IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_form <> rec_descriptor.item_form;
            END IF;

            IF current_mp.marc_vr_format IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_vr_format <> rec_descriptor.vr_format;
            END IF;

            IF current_mp.ref_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.ref_flag <> item_object.ref;
            END IF;

            IF current_mp.juvenile_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.juvenile_flag <> user_object.juvenile;
            END IF;

            IF current_mp.usr_age_lower_bound IS NOT NULL THEN
                CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_lower_bound < age(user_object.dob);
            END IF;

            IF current_mp.usr_age_upper_bound IS NOT NULL THEN
                CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_upper_bound > age(user_object.dob);
            END IF;


            -- everything was undefined or matched
            matchpoint = current_mp;

            EXIT WHEN matchpoint.id IS NOT NULL;
        END LOOP;

        EXIT WHEN current_group.parent IS NULL OR matchpoint.id IS NOT NULL;

        SELECT INTO current_group * FROM permission.grp_tree WHERE id = current_group.parent;
    END LOOP;

    RETURN matchpoint;
END;
$func$ LANGUAGE plpgsql;

COMMIT;

