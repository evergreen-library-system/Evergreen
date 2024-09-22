-- Invalid address
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (13, 3, 'sforbes', 6, 'Forbes', 'demo123',
        'Samuel', 'Eugene', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '40065', '8751 Gentleman Burgs', 'f',
        'KY', 'Shelbyville', '', 'Shelby', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999336514', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (13, 1, 'vcampbell', 4, 'Campbell', 'demo123',
        'Vincent', 'Lawrence', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '45633', '5489 Suitable Way Knoll', 't',
        'OH', 'Hallsville', '', 'Ross', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999338171', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'afrey', 9, 'Frey', 'demo123',
        'Annie', 'Jessica', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '54409', '7918 Subjective Volume Trail', 't',
        'WI', 'Antigo', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999364116', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'msalinas', 9, 'Salinas', 'demo123',
        'Mark', 'Christopher', NOW() + '3 years'::INTERVAL, '1999-06-13', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '25529', '1790 Lively Attitude Falls', 't', 
        'WV', 'Julian', '', 'Boone', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999313813', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 1, 'klindsey', 8, 'Lindsey', 'demo123',
        'Kenneth', 'Jesse', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '89077', '1552 Okay Communication Motorway', 't',
        'NV', 'Henderson', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999334832', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'mdavis', 8, 'Davis', 'demo123',
        'Martha', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '13156', '8717 Cabinet Fords', 't',
        'NY', 'Sterling', '', 'Cayuga', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999315736', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'vfreeman', 7, 'Freeman', 'demo123',
        'Virginia', 'Johanna', NOW() + '3 years'::INTERVAL, '1967-07-23', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '33122', '4033 Instant Matter Cape', 't',
        'FL', 'Miami', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999301938', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'lmartinez', 7, 'Martinez', 'demo123',
        'Leroy', 'Brian', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '55046', '2511 Other Stream', 't',
        'MN', 'Lonsdale', '', 'Rice', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999385425', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 1, 'warmstrong', 6, 'Armstrong', 'demo123',
        'William', 'William', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '55959', '1671 Cabinet Orchard', 't',
        'MN', 'Minnesota city', '', 'Winona', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999378711', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'acotton', 6, 'Cotton', 'demo123',
        'Amy', 'Ada', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '34202', '1488 Glamorous Alternative Forks', 't',
        'FL', 'Bradenton', '', 'Manatee', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999323866', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 1, 'sbarton', 5, 'Barton', 'demo123',
        'Sarah', 'Valerie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '54655', '6986 Delighted Design Trail', 't', 
        'WI', 'Soldiers grove', '', 'Crawford', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999327258', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 1, 'jhammond', 5, 'Hammond', 'demo123',
        'James', 'Michael', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '88211', '9144 White Support Squares', 't',
        'NM', 'Artesia', '', 'Eddy', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999385896', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'ajoseph', 4, 'Joseph', 'demo123',
        'Alex', 'Edward', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '56308', '9081 Awake Minute Spring', 't', 
        'MN', 'Alexandria', '', 'Douglas', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999378073', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (15, 3, 'imccoy', 4, 'Mccoy', 'demo123',
        'Ida', 'Gloria', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '40046', '9875 Support Row', 't',
        'KY', 'Mount eden', '', 'Spencer', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999321047', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 3, 'dwright', 9, 'Wright', 'demo123',
        'Dennis', 'Ernest', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '03457', '2063 Sophisticated Status Plaza', 't',
        'NH', 'Nelson', '', 'Cheshire', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999348121', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 1, 'alynch', 9, 'Lynch', 'demo123',
        'Armando', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '31126', '7394 Show Valley', 't',
        'GA', 'Atlanta', '', 'Fulton', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999384116', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 3, 'rgraham', 8, 'Graham', 'demo123',
        'Robert', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '98807', '2577 Stuck Benefit Tunnel', 't',
        'WA', 'Wenatchee', '', 'Chelan', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999311950', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 1, 'sthompson', 8, 'Thompson', 'demo123',
        'Sherri', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '31758', '3587 Name Neck', 't',
        'GA', 'Thomasville', '', 'Thomas', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999384066', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 1, 'ngarcia', 7, 'Garcia', 'demo123',
        'Nanette', 'Helen', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '11733', '6990 Icy Scene Street', 't',
        'NY', 'East setauket', '', 'Suffolk', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999332719', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 3, 'rcook', 7, 'Cook', 'demo123',
        'Raymond', 'Boyd', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '94533', '2004 Harsh Gold Tunnel', 't',
        'CA', 'Fairfield', '', 'Solano', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999392343', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 3, 'kbrewer', 6, 'Brewer', 'demo123',
        'Katherine', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '59053', '6732 Recognition Street', 't', 
        'MT', 'Martinsdale', '', 'Meagher', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999383479', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 1, 'cwashington', 6, 'Washington', 'demo123',
        'Christopher', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '47360', '9934 Coloured Bar Grove', 't',
        'IN', 'Mooreland', '', 'Henry', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999380284', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 3, 'dmurray', 5, 'Murray', 'demo123',
        'Dawn', 'Katherine', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '59868', '4426 Temporary Demand River', 't',
        'MT', 'Seeley lake', '', 'Missoula', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999347656', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 1, 'bwatts', 5, 'Watts', 'demo123',
        'Barbara', 'Gloria', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '51036', '4020 Marked Chemical Bayoo', 't',
        'IA', 'Maurice', '', 'Sioux', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999384489', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 3, 'mmartin', 4, 'Martin', 'demo123',
        'Mary', 'Shannon', NOW() + '3 years'::INTERVAL, NULL, 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '16657', '7511 Fortunate Length Parkway', 't', 
        'PA', 'James creek', '', 'Huntingdon', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999336634', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (14, 3, 'vford', 4, 'Ford', 'demo123',
        'Vivian', 'Darlene', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '23023', '3414 Energetic Weekend Circles', 't',
        'VA', 'Bruington', '', 'King and queen', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999361251', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'gsuarez', 9, 'Suarez', 'demo123',
        'Gary', 'Joel', NOW() + '3 years'::INTERVAL, NULL, 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '19244', '1613 Legislation River', 't', 
        'PA', 'Philadelphia', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999372079', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'eellis', 9, 'Ellis', 'demo123',
        'Edward', 'David', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '17349', '1977 Profound Conference Path', 't',
        'PA', 'New freedom', '', 'York', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999354444', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'nward', 8, 'Ward', 'demo123',
        'Naomi', 'Angela', NOW() + '3 years'::INTERVAL, NULL, 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '20109', '2689 Standard Interview Vista', 't', 
        'VA', 'Manassas', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999326817', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'jrichards', 8, 'Richards', 'demo123',
        'Joseph', 'Thomas', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '78658', '3275 Error Freeway', 't',
        'TX', 'Ottine', '', 'Gonzales', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999318881', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 3, 'rsanders', 7, 'Sanders', 'demo123',
        'Roslyn', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '19975', '6946 Constitutional Word Freeway', 't',
        'DE', 'Selbyville', '', 'Sussex', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999356038', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'nrivera', 7, 'Rivera', 'demo123',
        'Nancy', 'Anita', NOW() + '3 years'::INTERVAL, NULL, 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '27373', '263 Catholic End Field', 't',
        'NC', 'Wallburg', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999302274', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'cmartin', 6, 'Martin', 'demo123',
        'Carl', 'Charles', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '61452', '6985 Welcome Statement Fort', 't',
        'IL', 'Littleton', '', 'Schuyler', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999339237', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'telliott', 6, 'Elliott', 'demo123',
        'Thomas', 'Marcus', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '97624', '1283 Splendid West Manor', 't',
        'OR', 'Chiloquin', '', 'Klamath', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999340230', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 3, 'ocherry', 5, 'Cherry', 'demo123',
        'Olga', 'Marie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '17081', '9657 Scared Kind Street', 't',
        'PA', 'Plainfield', '', 'Cumberland', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999384061', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 1, 'gdavenport', 5, 'Davenport', 'demo123',
        'Gwendolyn', '', NOW() + '3 years'::INTERVAL, NULL, 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '85014', '110 Logical Tone Drive', 't',
        'AZ', 'Phoenix', '', 'Maricopa', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999372586', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 3, 'sbrock', 4, 'Brock', 'demo123',
        'Scott', 'George', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '60132', '1760 Channel Bottom', 't',
        'IL', 'Carol stream', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999336715', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (12, 3, 'rjackson', 4, 'Jackson', 'demo123',
        'Ronald', 'Robert', NOW() + '3 years'::INTERVAL, NULL, 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '04985', '5561 Native Reduction Crossing', 't', 
        'ME', 'West forks', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999335465', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 1, 'wjames', 9, 'James', 'demo123',
        'Wayne', 'George', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '27014', '5542 Politics Hollow', 't',
        'NC', 'Cooleemee', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999379835', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 1, 'shernandez', 9, 'Hernandez', 'demo123',
        'Sarah', 'Elaine', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '89151', '4939 Family Divide', 't', 
        'NV', 'Las vegas', '', 'Clark', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999346587', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'latkins', 8, 'Atkins', 'demo123',
        'Louis', 'Edward', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '44705', '2794 Uniform Value Square', 't',
        'OH', 'Canton', '', 'Stark', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999377256', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'wneal', 8, 'Neal', 'demo123',
        'Wayne', '', NOW() + '3 years'::INTERVAL, '1977-06-05', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '35501', '6178 Relieved Rain Wells', 't',
        'AL', 'Jasper', '', 'Walker', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999377249', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'mharrison', 7, 'Harrison', 'demo123',
        'Michelle', 'Patricia', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '05345', '1766 Victorious Estate Avenue', 't', 
        'VT', 'Newfane', '', 'Windham', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999376642', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'hwomack', 7, 'Womack', 'demo123',
        'Howard', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '06262', '5472 Exhibition Trace', 't', 
        'CT', 'Quinebaug', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999342319', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'vbacon', 6, 'Bacon', 'demo123',
        'Virginia', 'Celia', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '61638', '4639 Family Tunnel', 't', 
        'IL', 'Peoria', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999362019', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 1, 'lbrooks', 6, 'Brooks', 'demo123',
        'Lonnie', 'William', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '83836', '8823 Side Fall', 't',
        'ID', 'Hope', '', 'Bonner', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999326493', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'mgonzales', 5, 'Gonzales', 'demo123',
        'Mary', 'Jessica', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '16213', '6608 Weary Drawing Lakes', 't',
        'PA', 'Callensburg', '', 'Clarion', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999337760', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 1, 'mterry', 5, 'Terry', 'demo123',
        'Michelle', 'Kristy', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '30817', '1658 Organisational Bedroom Square', 't',
        'GA', 'Lincolnton', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999390692', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'mmeeks', 4, 'Meeks', 'demo123',
        'Michelle', 'Myra', NOW() + '3 years'::INTERVAL, '1966-01-23', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '88240', '7269 Sister Gardens', 't',
        'NM', 'Hobbs', '', 'Lea', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999396672', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (11, 3, 'epalmer', 4, 'Palmer', 'demo123',
        'Elva', 'Tiffany', NOW() + '3 years'::INTERVAL, '1987-08-21', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '50595', '7864 Remarkable Status River', 't',
        'IA', 'Webster city', '', 'Hamilton', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999335171', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 3, 'mwilliams', 9, 'Williams', 'demo123',
        'Matthew', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '60064', '7230 Trend Mount', 't',
        'IL', 'North chicago', '', 'Lake', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999365046', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 1, 'nperez', 9, 'Perez', 'demo123',
        'Nicholas', 'Joseph', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '55076', '9299 Democratic Hill Cliffs', 't',
        'MN', 'Inver grove heights', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999391887', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 3, 'bfisher', 8, 'Fisher', 'demo123',
        'Barbara', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '61756', '9822 Excess Start Lock', 't',
        'IL', 'Maroa', '', 'Macon', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999325028', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 3, 'mmendoza', 8, 'Mendoza', 'demo123',
        'Miguel', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '58773', '5831 Residential Respect Track', 't',
        'ND', 'Powers lake', '', 'Burke', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999338966', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 1, 'ldickinson', 7, 'Dickinson', 'demo123',
        'Lee', 'Annie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '12803', '5030 Vision Loop', 't',
        'NY', 'South glens falls', '', 'Saratoga', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999328210', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 1, 'awilliams', 7, 'Williams', 'demo123',
        'Angelina', 'Joan', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '25054', '1723 Multiple Object Canyon', 't',
        'WV', 'Dawes', '', 'Kanawha', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999373939', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 1, 'bsanchez', 6, 'Sanchez', 'demo123',
        'Beth', 'Deborah', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '36426', '5148 Shaggy Farm Center', 't',
        'AL', 'Brewton', '', 'Escambia', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999354471', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 3, 'ethompson', 6, 'Thompson', 'demo123',
        'Elvin', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '67664', '2800 Cheerful Animal Valley', 't',
        'KS', 'Prairie view', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999320974', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 1, 'dlawson', 5, 'Lawson', 'demo123',
        'Dora', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '63957', '6016 General Dog Divide', 't',
        'MO', 'Piedmont', '', 'Wayne', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394437', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 1, 'lvargas', 5, 'Vargas', 'demo123',
        'Laura', 'Mildred', NOW() + '3 years'::INTERVAL, '1989-07-04', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '62526', '4689 Alert Minute Court', 't',
        'IL', 'Decatur', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999317988', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 3, 'wrandall', 4, 'Randall', 'demo123',
        'William', 'James', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '72117', '3448 Minor Solicitor Junction', 't',
        'AR', 'North little rock', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999393617', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (10, 1, 'csmith', 4, 'Smith', 'demo123',
        'Cathy', 'Cheryl', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '81420', '784 Striking Theatre Fords', 't', 
        'CO', 'Lazear', '', 'Delta', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999389406', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'alopez', 9, 'Lopez', 'demo123',
        'Arline', 'Amber', NOW() + '3 years'::INTERVAL, '1985-05-05', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '19053', '5012 Unemployed Other Harbor', 't',
        'PA', 'Feasterville trevose', '', 'Bucks', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999330939', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'epeterson', 9, 'Peterson', 'demo123',
        'Emma', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '07095', '9931 Hushed Passage Turnpike', 't',
        'NJ', 'Woodbridge', '', 'Middlesex', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999346297', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'okelly', 8, 'Kelly', 'demo123',
        'Opal', 'Sara', NOW() + '3 years'::INTERVAL, '1975-01-18', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '79550', '8572 Ltd Bar Brook', 't', 
        'TX', 'Snyder', '', 'Scurry', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999355455', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'cdonovan', 8, 'Donovan', 'demo123',
        'Charlie', 'David', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '54017', '1926 Double Effort Spring', 't',
        'WI', 'New richmond', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999348978', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 3, 'msmith', 7, 'Smith', 'demo123',
        'Martha', 'Raquel', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '80534', '7185 Arbitrary Contrast Freeway', 't',
        'CO', 'Johnstown', '', 'Weld', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394964', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 3, 'chouston', 7, 'Houston', 'demo123',
        'Cheryl', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '93703', '2782 Awake Day Square', 't', 
        'CA', 'Fresno', '', 'Fresno', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999320969', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'kwright', 6, 'Wright', 'demo123',
        'Kay', 'Anna', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '22834', '4585 Whole Harbor', 't', 
        'VA', 'Linville', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999398195', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 3, 'mlane', 6, 'Lane', 'demo123',
        'Michelle', 'Andrea', NOW() + '3 years'::INTERVAL, '1963-06-14', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '98110', '8676 Thundering Loss Field', 't', 
        'WA', 'Bainbridge island', '', 'Kitsap', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999333153', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'rsmith', 5, 'Smith', 'demo123',
        'Robert', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '00983', '231 Causal Expert Highway', 't',
        'PR', 'Carolina', '', 'Carolina', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999362675', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'cdodson', 5, 'Dodson', 'demo123',
        'Cleo', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '25266', '53 Nice Customer Green', 't',
        'WV', 'Newton', '', 'Roane', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999362218', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 1, 'mneal', 4, 'Neal', 'demo123',
        'Melvin', 'Richard', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '10150', '668 Unconscious Gun Spring', 't',
        'NY', 'New york', '', 'New york', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999317310', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (9, 3, 'awilliams', 4, 'Williams', 'demo123',
        'Anna', 'Justine', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '45809', '749 Software Center', 't', 
        'OH', 'Gomer', '', 'Allen', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999392361', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'emiller', 9, 'Miller', 'demo123',
        'Edmond', 'Vance', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '92007', '2632 Unlikely Assumption Tunnel', 't',
        'CA', 'Cardiff by the sea', '', 'San diego', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999371777', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 3, 'vlogan', 9, 'Logan', 'demo123',
        'Vanessa', 'Cassandra', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '44470', '2823 Eventual Hour Gateway', 't',
        'OH', 'Southington', '', 'Trumbull', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999372363', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'lthompson', 8, 'Thompson', 'demo123',
        'Lisa', 'Shirley', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '45690', '2166 Newspaper Grove', 't', 
        'OH', 'Waverly', '', 'Pike', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999321149', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'oshaffer', 8, 'Shaffer', 'demo123',
        'Ollie', 'Monica', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '15534', '2134 Inc Boat Turnpike', 't', 
        'PA', 'Buffalo mills', '', 'Bedford', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999335455', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'randrews', 7, 'Andrews', 'demo123',
        'Raymond', 'Willie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '06018', '1944 Hot Tape Valley', 't', 
        'CT', 'Canaan', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999346031', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 3, 'emartinez', 7, 'Martinez', 'demo123',
        'Edna', 'Judith', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '49270', '121 Consequence Club', 't',
        'MI', 'Petersburg', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999336926', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 3, 'jdavis', 6, 'Davis', 'demo123',
        'James', 'Jerry', NOW() + '3 years'::INTERVAL, '1970-06-11', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '58064', '5708 Brainy West Bend', 't',
        'ND', 'Page', '', 'Cass', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999363070', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'droberts', 6, 'Roberts', 'demo123',
        'Diane', 'Teresa', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '00692', '9609 Advanced Tool Mountain', 't', 
        'PR', 'Vega alta', '', 'Vega alta', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999357381', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'psantiago', 5, 'Santiago', 'demo123',
        'Paige', 'Helen', NOW() + '3 years'::INTERVAL, '1979-08-23', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '91608', '2852 Key Incident Avenue', 't', 
        'CA', 'Universal city', '', 'Los angeles', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394956', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'awright', 5, 'Wright', 'demo123',
        'Alyssa', 'Christine', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '80295', '7771 Alive Iron Mission', 't',
        'CO', 'Denver', '', 'Denver', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999367802', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 3, 'dbeck', 4, 'Beck', 'demo123',
        'Diana', 'Wilma', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '58776', '1146 Ability Centers', 't',
        'ND', 'Ross', '', 'Mountrail', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999361901', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (8, 1, 'mclark', 4, 'Clark', 'demo123',
        'Monty', 'Daniel', NOW() + '3 years'::INTERVAL, '1984-05-19', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '55168', '3541 Radical Sir Avenue', 't',
        'MN', 'Saint paul', '', 'Ramsey', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999381970', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 3, 'hstone', 9, 'Stone', 'demo123',
        'Hazel', 'Sylvia', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '93247', '4171 Impossible Defence Overpass', 't',
        'CA', 'Lindsay', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999367834', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 1, 'dgarza', 9, 'Garza', 'demo123',
        'David', 'Steven', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '22513', '3627 Retail Kind Lodge', 't',
        'VA', 'Merry point', '', 'Lancaster', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999377760', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 3, 'jevans', 8, 'Evans', 'demo123',
        'John', 'Timothy', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '64778', '1212 Mid Top Parkway', 't',
        'MO', 'Richards', '', 'Vernon', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999367573', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 3, 'rpayton', 8, 'Payton', 'demo123',
        'Robert', 'Steven', NOW() + '3 years'::INTERVAL, '1994-05-07', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '55336', '1642 Minor Potential Corners', 't',
        'MN', 'Glencoe', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394830', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 3, 'ddavis', 7, 'Davis', 'demo123',
        'Donald', 'Gene', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '48749', '5946 Gas Way', 't', 
        'MI', 'Omer', '', 'Arenac', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999340278', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 1, 'gadams', 7, 'Adams', 'demo123',
        'Gene', '', NOW() + '3 years'::INTERVAL, '1974-02-18', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '88525', '8265 Phone Trail', 't', 
        'TX', 'El paso', '', 'El paso', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999349290', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 1, 'hwhite', 6, 'White', 'demo123',
        'Humberto', 'Kevin', NOW() + '3 years'::INTERVAL, '1997-09-08', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '25926', '6558 Willing Master Valley', 't',
        'WV', 'Sprague', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999309750', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 3, 'asnyder', 6, 'Snyder', 'demo123',
        'Ana', '', NOW() + '3 years'::INTERVAL, '1991-05-23', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '00922', '8532 Spare Offer Cliffs', 't',
        'PR', 'San juan', '', 'San juan', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999332335', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 1, 'jroberts', 5, 'Roberts', 'demo123',
        'John', 'Theodore', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '79550', '279 Passing Conference Street', 't', 
        'TX', 'Snyder', '', 'Scurry', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999367122', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 3, 'sheath', 5, 'Heath', 'demo123',
        'Steven', 'Luke', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '94547', '4666 Pain Isle', 't',
        'CA', 'Hercules', '', 'Contra costa', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999375796', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 1, 'krush', 4, 'Rush', 'demo123',
        'Keith', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '15257', '4464 Sense Station', 't',
        'PA', 'Pittsburgh', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999345655', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (7, 3, 'lfarrell', 4, 'Farrell', 'demo123',
        'Linda', 'Linda', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '75155', '7746 Cooperative Fall Shoal', 't',
        'TX', 'Rice', '', 'Navarro', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999344872', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 3, 'rharrison', 9, 'Harrison', 'demo123',
        'Richard', 'Melvin', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '06601', '2896 Jewish Lack Lodge', 't',
        'CT', 'Bridgeport', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999399702', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'ksmith', 9, 'Smith', 'demo123',
        'Kevin', 'Timothy', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '81523', '5119 Lot Isle', 't', 
        'CO', 'Glade park', '', 'Mesa', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394646', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'fmoore', 8, 'Moore', 'demo123',
        'Florence', 'Michelle', NOW() + '3 years'::INTERVAL, '1977-02-07', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '39440', '6398 Mathematical Condition Arcade', 't', 
        'MS', 'Laurel', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999341034', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'bcruz', 8, 'Cruz', 'demo123',
        'Betty', 'Shirley', NOW() + '3 years'::INTERVAL, '1993-08-10', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '33630', '1062 Scornful Air Fort', 't',
        'FL', 'Tampa', '', 'Hillsborough', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999363183', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'jjohnson', 7, 'Johnson', 'demo123',
        'Joel', 'Allen', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '36028', '3220 Drunk Message Parkway', 't',
        'AL', 'Dozier', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999370090', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'kburton', 7, 'Burton', 'demo123',
        'Kristen', 'Dena', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '42413', '4924 Part-time Charge Knoll', 't',
        'KY', 'Hanson', '', 'Hopkins', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999372936', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'rpineda', 6, 'Pineda', 'demo123',
        'Robert', 'Gordon', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '47703', '1587 Labour Holiday Park', 't', 
        'IN', 'Evansville', '', 'Vanderburgh', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999349988', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'avaldez', 6, 'Valdez', 'demo123',
        'Alissa', 'Gladys', NOW() + '3 years'::INTERVAL, '1994-03-25', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '64735', '4372 Fact Junction', 't',
        'MO', 'Clinton', '', 'Henry', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999332255', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 3, 'krowland', 5, 'Rowland', 'demo123',
        'Kenneth', 'Ernest', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '98131', '8373 Resonant Investment Mission', 't',
        'WA', 'Seattle', '', 'King', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999354715', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'thansen', 5, 'Hansen', 'demo123',
        'Terrance', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '16550', '4446 Formidable Way Knolls', 't', 
        'PA', 'Erie', '', 'Erie', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999363646', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 3, 'breid', 4, 'Reid', 'demo123',
        'Barbara', 'Amanda', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '04056', '3517 Hot School Brook', 't',
        'ME', 'Newfield', '', 'York', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999365307', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (6, 1, 'mroberts', 4, 'Roberts', 'demo123',
        'Michael', 'Stephen', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '63541', '4668 Start Inlet', 't',
        'MO', 'Glenwood', '', 'Schuyler', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999332788', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 3, 'rkaufman', 9, 'Kaufman', 'demo123',
        'Rachel', 'Vickie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '68659', '7270 Development Row', 't',
        'NE', 'Rogers', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999340790', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 3, 'csims', 9, 'Sims', 'demo123',
        'Christopher', 'John', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '89013', '5637 Plastic Mill', 't', 
        'NV', 'Goldfield', '', 'Esmeralda', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999386091', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 1, 'srobinson', 8, 'Robinson', 'demo123',
        'Sarah', '', NOW() + '3 years'::INTERVAL, '1996-01-28', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '65897', '8092 Pure Name Bridge', 't',
        'MO', 'Springfield', '', 'Greene', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999340199', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 3, 'jpayton', 8, 'Payton', 'demo123',
        'Johnny', 'Vincent', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '85738', '8772 Forthcoming Hope Fort', 't',
        'AZ', 'Catalina', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999387186', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 3, 'djamison', 7, 'Jamison', 'demo123',
        'David', 'Eric', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '59604', '9218 Moral Worker Summit', 't',
        'MT', 'Helena', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999340530', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 3, 'jford', 7, 'Ford', 'demo123',
        'Jamie', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '41746', '8268 Hill Valleys', 't', 
        'KY', 'Happy', '', 'Perry', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999384455', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 1, 'gwatson', 6, 'Watson', 'demo123',
        'Gerald', 'Larry', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '85063', '881 Scary Holiday Radial', 't',
        'AZ', 'Phoenix', '', 'Maricopa', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999385100', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 1, 'clambert', 6, 'Lambert', 'demo123',
        'Charles', 'William', NOW() + '3 years'::INTERVAL, '1995-09-22', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '40291', '6026 Wide Development Port', 't',
        'KY', 'Louisville', '', 'Jefferson', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999335749', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 1, 'mbarber', 5, 'Barber', 'demo123',
        'Micheal', 'Ramon', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '91357', '9727 Proposed Executive Plaza', 't', 
        'CA', 'Tarzana', '', 'Los angeles', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999361522', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 3, 'tcruz', 5, 'Cruz', 'demo123',
        'Tom', 'Eugene', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '40546', '7481 Reform Road', 't', 
        'KY', 'Lexington', '', 'Fayette', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394278', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 1, 'iwalton', 4, 'Walton', 'demo123',
        'Inez', 'Amanda', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '29053', '8589 Official Valleys', 't',
        'SC', 'Gaston', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999356283', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (5, 3, 'mtownsend', 4, 'Townsend', 'demo123',
        'Mary', '', NOW() + '3 years'::INTERVAL, '1995-03-03', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '72464', '3321 Answer Stravenue', 't', 
        'AR', 'Saint francis', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999336350', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 3, 'cmartinez', 9, 'Martinez', 'demo123',
        'Carolyn', 'Sandra', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '49654', '7081 Appalling Plant Causeway', 't', 
        'MI', 'Leland', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999397121', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 1, 'jjohnson', 9, 'Johnson', 'demo123',
        'Jeremy', 'Mark', NOW() + '3 years'::INTERVAL, '1970-03-14', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '70358', '4786 Prior Politics Mission', 't',
        'LA', 'Grand isle', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999397850', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 9);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 9;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 1, 'mscott', 8, 'Scott', 'demo123',
        'Mae', 'Sue', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '14723', '1060 Letter Stravenue', 't',
        'NY', 'Cherry creek', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999395984', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 3, 'rstevens', 8, 'Stevens', 'demo123',
        'Russell', 'Daniel', NOW() + '3 years'::INTERVAL, '1973-08-15', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '29582', '7735 Street Creek', 't',
        'SC', 'North myrtle beach', '', 'Horry', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999340524', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 8);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 8;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 3, 'therrera', 7, 'Herrera', 'demo123',
        'Traci', 'Edith', NOW() + '3 years'::INTERVAL, '1994-07-07', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '84133', '7301 Watery Arrangement Radial', 't',
        'UT', 'Salt lake city', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999386259', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 3, 'vgrimes', 7, 'Grimes', 'demo123',
        'Virginia', 'Jennifer', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '87027', '8666 Fluttering Situation Heights', 't',
        'NM', 'La jara', '', 'Sandoval', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999318163', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 7);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 7;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 1, 'pward', 6, 'Ward', 'demo123',
        'Paul', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '38233', '8859 Roasted Energy Falls', 't',
        'TN', 'Kenton', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999346968', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 3, 'bgreen', 6, 'Green', 'demo123',
        'Beatrice', 'Janette', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '65438', '9082 Plain Bed Avenue', 't',
        'MO', 'Birch tree', '', 'Shannon', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999345139', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 6);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 6;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 1, 'sschmidt', 5, 'Schmidt', 'demo123',
        'Scott', 'Kyle', NOW() + '3 years'::INTERVAL, NULL, 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '99670', '2204 Status Avenue', 't',
        'AK', 'South naknek', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999393981', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 3, 'jclark', 5, 'Clark', 'demo123',
        'Joanne', 'Andrea', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '35175', '7622 Thoughtless Science Pines', 't',
        'AL', 'Union grove', '', 'Marshall', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999366354', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 5);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 5;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 1, 'bbrown', 4, 'Brown', 'demo123',
        'Beverly', 'Florence', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '29058', '2991 Trip Crescent', 't', 
        'SC', 'Heath springs', '', 'Lancaster', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999338317', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;

INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (4, 3, 'jmcginnis', 4, 'Mcginnis', 'demo123',
        'Jose', 'David', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '65055', '8231 Relieved Debt Cape', 't',
        'MO', 'Mc girk', '', 'Moniteau', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999316430', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO permission.usr_work_ou_map (usr, work_ou) 
    VALUES (CURRVAL('actor.usr_id_seq'), 4);

UPDATE actor.usr usr SET usrname = LOWER(aou.shortname) || usrname 
    FROM actor.org_unit aou 
    WHERE usr.id = CURRVAL('actor.usr_id_seq') AND aou.id = 4;
