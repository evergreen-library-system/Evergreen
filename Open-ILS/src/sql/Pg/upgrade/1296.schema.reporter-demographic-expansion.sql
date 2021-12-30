BEGIN;

SELECT evergreen.upgrade_deps_block_check('1296', :eg_version);

CREATE OR REPLACE VIEW reporter.demographic AS
SELECT  u.id,
    u.dob,
    CASE
        WHEN u.dob IS NULL
            THEN 'Adult'
        WHEN AGE(u.dob) > '18 years'::INTERVAL
            THEN 'Adult'
        ELSE 'Juvenile'
    END AS general_division,
    CASE
        WHEN u.dob IS NULL
            THEN 'No Date of Birth Entered'::text
        WHEN age(u.dob::timestamp with time zone) >= '0 years'::interval and age(u.dob::timestamp with time zone) < '6 years'::interval
            THEN 'Child 0-5 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '6 years'::interval and age(u.dob::timestamp with time zone) < '13 years'::interval
            THEN 'Child 6-12 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '13 years'::interval and age(u.dob::timestamp with time zone) < '18 years'::interval
            THEN 'Teen 13-17 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '18 years'::interval and age(u.dob::timestamp with time zone) < '26 years'::interval
            THEN 'Adult 18-25 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '26 years'::interval and age(u.dob::timestamp with time zone) < '50 years'::interval
            THEN 'Adult 26-49 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '50 years'::interval and age(u.dob::timestamp with time zone) < '60 years'::interval
            THEN 'Adult 50-59 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '60 years'::interval and age(u.dob::timestamp with time zone) < '70  years'::interval
            THEN 'Adult 60-69 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '70 years'::interval
            THEN 'Adult 70+'::text
        ELSE NULL::text
    END AS age_division
    FROM actor.usr u;

COMMIT;
