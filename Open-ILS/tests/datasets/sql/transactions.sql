
/**
 * For the first (by ID) 20 users in each Patron group and the first 3 in 
 * each Staff group:
 *
 * 1. create 3 regular circs w/ varying (stock) rules and 3 overdue
 * circs. 
 *
 * 2. create 2 regular title holds and one frozen title hold.  If the user
 * is in a Staff group, also create one copy-level hold.
 *
 */

/**
 * NOTE: The fine generator and hold targeter should be run after this is
 * loaded to creating overdue billings and target copies for holds.
 */

DO $$                                                                           
    DECLARE grp INTEGER;                                                      
    DECLARE recipient actor.usr%ROWTYPE;
    DECLARE copy asset.copy%ROWTYPE;
    DECLARE bre biblio.record_entry%ROWTYPE;
    DECLARE user_count INTEGER;
    DECLARE requestor INTEGER;
BEGIN                                                                           

    copy := evergreen.next_copy(0);
    bre := evergreen.next_bib(0);

    FOR grp IN SELECT id FROM permission.grp_tree WHERE id > 1 ORDER BY id LOOP

        IF 2 IN (SELECT id FROM permission.grp_ancestors(grp)) THEN
            -- patron group
            user_count := 50;
        ELSE
            user_count := 3;
        END IF;

        FOR recipient IN SELECT * FROM actor.usr 
            WHERE NOT deleted AND profile = grp 
                AND expire_date > NOW() - '1 month'::interval
                ORDER BY id LIMIT user_count LOOP

            -- find a suitable circulator/requestor for these transactions
            SELECT INTO requestor id 
                FROM actor.usr 
                WHERE home_ou = recipient.home_ou AND
                      profile = 5 AND -- Circulators
                      NOT deleted
                      AND expire_date > NOW()
                ORDER BY id LIMIT 1;

            -- regular circs --------------------------------

            copy := evergreen.next_copy(copy.id);
            EXIT WHEN copy IS NULL;
            PERFORM evergreen.populate_circ(
                recipient.id, requestor, copy.id, copy.circ_lib,
                'default', 'default', 'default', FALSE
            );

            copy := evergreen.next_copy(copy.id);
            EXIT WHEN copy IS NULL;
            PERFORM evergreen.populate_circ(
                recipient.id, requestor, copy.id, copy.circ_lib,
                '1_hour_2_renew', 'default', 'overdue_min', FALSE
            );

            copy := evergreen.next_copy(copy.id);
            EXIT WHEN copy IS NULL;
            PERFORM evergreen.populate_circ(
                recipient.id, requestor, copy.id, copy.circ_lib,
                '7_days_0_renew', 'default', 'overdue_max', FALSE
            );

            -- overdue circs ----------------------------------

            copy := evergreen.next_copy(copy.id);
            EXIT WHEN copy IS NULL;
            PERFORM evergreen.populate_circ(
                recipient.id, requestor, copy.id, copy.circ_lib,
                'default', 'default', 'default', TRUE
            );

            copy := evergreen.next_copy(copy.id);
            EXIT WHEN copy IS NULL;
            PERFORM evergreen.populate_circ(
                recipient.id, requestor, copy.id, copy.circ_lib,
                '1_hour_2_renew', 'default', 'overdue_min', TRUE
            );

            copy := evergreen.next_copy(copy.id);
            EXIT WHEN copy IS NULL;
            PERFORM evergreen.populate_circ(
                recipient.id, requestor, copy.id, copy.circ_lib,
                '7_days_0_renew', 'default', 'overdue_max', TRUE
            );

            -- holds ------------------------------------------

            -- title hold
            bre := evergreen.next_bib(bre.id);
            EXIT WHEN bre IS NULL;
            PERFORM evergreen.populate_hold(
                'T', bre.id, recipient.id, recipient.id,
                recipient.home_ou, FALSE, NULL
            );

            -- title hold, circulator-placed 
            bre := evergreen.next_bib(bre.id);
            EXIT WHEN bre IS NULL;
            PERFORM evergreen.populate_hold(
                'T', bre.id, recipient.id, requestor,
                recipient.home_ou, FALSE, NULL
            );

            -- frozen title hold
            bre := evergreen.next_bib(bre.id);
            EXIT WHEN bre IS NULL;
            PERFORM evergreen.populate_hold(
                'T', bre.id, recipient.id, recipient.id,
                recipient.home_ou,
                TRUE, NOW() + '3 months'::INTERVAL
            );

            -- Staff accounts get a copy-level hold
            IF 3 IN (SELECT id FROM permission.grp_ancestors(grp)) THEN
                copy := evergreen.next_copy(copy.id);
                EXIT WHEN copy IS NULL;
                PERFORM evergreen.populate_hold(
                    'C', copy.id, recipient.id, recipient.id,
                    recipient.home_ou, FALSE, NULL
                );
            END IF;

        END LOOP;                                                                   
    END LOOP;                                                                   
END $$;


