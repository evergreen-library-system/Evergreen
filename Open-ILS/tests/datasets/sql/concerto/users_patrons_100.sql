
-- expired patron
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999395390', 9, 'Brooks', 'demo123',
        'Terri', 'Maria', '2008-01-01', NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '32961', '1809 Target Way', 't', 
        'FL', 'Vero beach', '', 'Indian river', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999395390', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- expired patron
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999320945', 5, 'Jackson', 'demo123',
        'Shannon', 'Thomas', '1999-01-01', NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '41301', '3481 Facility Island', 't',
        'KY', 'Campton', '', 'Wolfe', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999320945', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- Soon to expire patron
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999355250', 5, 'Jones', 'demo123',
        'Gregory', '', NOW() + '1 day'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '55927', '5150 Dinner Expressway', 't',
        'MN', 'Dodge center', '', 'Dodge', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999355250', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- Soon to expire patron
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999387993', 9, 'Moran', 'demo123',
        'Vincent', 'Kenneth', NOW() + '1 week'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '22611', '8496 Random Trust Points', 't',
        'VA', 'Berryville', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999387993', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- Soon to expire patron
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999335859', 8, 'Jones', 'demo123',
        'Gregory', 'Adam', NOW() + '3 weeks'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '99502', '7626 Secret Institute Courts', 't',
        'AK', 'Anchorage', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999335859', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- Recently expired patron
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999373186', 7, 'Walker', 'demo123',
        'Brittany', 'Geraldine', NOW() - '1 week'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '40445', '7044 Regular Index Path', 't',
        'KY', 'Livingston', '', 'Rockcastle', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999373186', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- Recently expired patron
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999384262', 9, 'Miller', 'demo123',
        'Ernesto', 'Robert', NOW() - '3 weeks'::INTERVAL, '1997-02-02', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '33157', '3403 Thundering Heat Meadows', 't',
        'FL', 'Miami', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999384262', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- Invalid address
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999373998', 9, 'Hill', 'demo123',
        'Robert', 'Louis', NOW() + '3 years'::INTERVAL, NULL, 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '18960', '759 Doubtful Government Extension', 'f',
        'PA', 'Sellersville', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999373998', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


-- Invalid address
INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999376669', 7, 'Lopez', 'demo123',
        'Edward', 'Robert', NOW() + '3 years'::INTERVAL, NULL, 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '29593', '5431 Japanese Work Rapid', 'f',
        'SC', 'Society hill', '', 'Darlington', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999376669', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999361076', 8, 'Bell', 'demo123',
        'Andrew', 'Alberto', NOW() + '3 years'::INTERVAL, NULL, 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '61936', '5253 Agricultural Exhibition Stravenue', 't',
        'IL', 'La place', '', 'Piatt', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999361076', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999376988', 9, 'Mitchell', 'demo123',
        'Jennifer', 'Dorothy', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '61822', '8649 Raspy Goal Terrace', 't', 
        'IL', 'Champaign', '', 'Champaign', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999376988', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999390791', 7, 'Ortiz', 'demo123',
        'Richard', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '23885', '2433 Uncomfortable Nature Greens', 't',
        'VA', 'Sutherland', '', 'Dinwiddie', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999390791', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999378730', 6, 'Wade', 'demo123',
        'Robert', 'Coy', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '55796', '3241 Communist Boat Boulevard', 't',
        'MN', 'Winton', '', 'Saint louis', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999378730', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999360638', 5, 'Wise', 'demo123',
        'Janet', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '64126', '6773 Government Hill', 't',
        'MO', 'Kansas city', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999360638', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999350419', 4, 'Torres', 'demo123',
        'Donald', 'Arnold', NOW() + '3 years'::INTERVAL, '1974-06-26', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '40847', '7194 Gorgeous Edge Dale', 't',
        'KY', 'Kenvir', '', 'Harlan', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999350419', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999354736', 4, 'Miller', 'demo123',
        'Jeff', 'James', NOW() + '3 years'::INTERVAL, NULL, 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '80920', '9674 Filthy Firm Meadows', 't',
        'CO', 'Colorado springs', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999354736', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999329662', 9, 'Estes', 'demo123',
        'Leonard', '', NOW() + '3 years'::INTERVAL, '1994-05-07', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '20724', '6145 Superior Dress Prairie', 't', 
        'MD', 'Laurel', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999329662', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999397601', 8, 'Dunn', 'demo123',
        'Brittney', 'Pamela', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '73838', '9753 Confident Limit Shoal', 't',
        'OK', 'Chester', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999397601', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999377594', 4, 'Wiggins', 'demo123',
        'Jean', 'Verna', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '23018', '6115 Thoughtful Country Ridge', 't',
        'VA', 'Bena', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999377594', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999371252', 9, 'Thomas', 'demo123',
        'Lela', 'Sarah', NOW() + '3 years'::INTERVAL, '1968-04-11', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '60609', '4223 Spotty Chemical Stravenue', 't',
        'IL', 'Chicago', '', 'Cook', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999371252', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999398023', 8, 'Phillips', 'demo123',
        'Noah', 'Joseph', NOW() + '3 years'::INTERVAL, NULL, 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '33593', '2005 Inner Entry Harbor', 't',
        'FL', 'Trilby', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999398023', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999324566', 5, 'Mitchell', 'demo123',
        'Carolyn', 'Patrica', NOW() + '3 years'::INTERVAL, '1981-09-03', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '50652', '5259 Film Crossing', 't', 
        'IA', 'Lincoln', '', 'Tama', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999324566', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999379221', 5, 'Wells', 'demo123',
        'Kristen', 'Vivian', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '12450', '2302 Prisoner Way', 't',
        'NY', 'Lanesville', '', 'Greene', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999379221', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999373350', 8, 'Lindsey', 'demo123',
        'Noah', 'Keith', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '50108', '7583 Low Surface Overpass', 't',
        'IA', 'Grand river', '', 'Decatur', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999373350', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999340920', 4, 'Williams', 'demo123',
        'Bertha', 'Katherine', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '20646', '3301 Acid Canyon', 't',
        'MD', 'La plata', '', 'Charles', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999340920', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999398482', 7, 'Rodriguez', 'demo123',
        'James', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '95066', '9801 Working-class Flower Meadow', 't',
        'CA', 'Scotts valley', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999398482', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999394378', 5, 'Byrd', 'demo123',
        'Matthew', 'David', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '43015', '9029 Note Court', 't', 
        'OH', 'Delaware', '', 'Delaware', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394378', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999382659', 4, 'Kelley', 'demo123',
        'Sandra', 'Pearlie', NOW() + '3 years'::INTERVAL, '1977-01-18', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '56568', '4246 Fun Post Street', 't',
        'MN', 'Nielsville', '', 'Polk', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999382659', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999387130', 7, 'Wilson', 'demo123',
        'Beth', 'Michelle', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '15341', '7780 Horrible Winner Island', 't',
        'PA', 'Holbrook', '', 'Greene', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999387130', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999310765', 8, 'Daniels', 'demo123',
        'Randy', 'Lawrence', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '29680', '4697 Subsequent Culture Pass', 't',
        'SC', 'Simpsonville', '', 'Greenville', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999310765', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999335545', 9, 'Simpson', 'demo123',
        'Steve', 'Raymond', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '88118', '2400 Communication Mount', 't',
        'NM', 'Floyd', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999335545', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999360529', 5, 'Hoskins', 'demo123',
        'Jim', 'Michael', NOW() + '3 years'::INTERVAL, '1983-08-02', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '15015', '7815 Principal Element Center', 't', 
        'PA', 'Bradfordwoods', '', 'Allegheny', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999360529', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999357038', 5, 'May', 'demo123',
        'Michael', '', NOW() + '3 years'::INTERVAL, '1988-03-06', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '20064', '4827 Shoulder Center', 't',
        'DC', 'Washington', '', 'District of columbia', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999357038', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999371688', 8, 'Ellison', 'demo123',
        'Don', 'John', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '20643', '1298 Golden Speed Hills', 't', 
        'MD', 'Ironsides', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999371688', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999312757', 4, 'Hughes', 'demo123',
        'Joseph', 'Bryant', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '48613', '9736 Profitable Wine Spring', 't',
        'MI', 'Bentley', '', 'Bay', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999312757', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999399015', 8, 'Turner', 'demo123',
        'Cristina', 'Karen', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '45844', '6445 Turkish Strike Shoal', 't', 
        'OH', 'Fort jennings', '', 'Putnam', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999399015', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999313973', 4, 'Langley', 'demo123',
        'Victor', 'James', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '94576', '1082 Capacity Hill', 't',
        'CA', 'Deer park', '', 'Napa', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999313973', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999311521', 6, 'Fields', 'demo123',
        'David', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '73939', '8788 Religious Writer Isle', 't',
        'OK', 'Goodwell', '', 'Texas', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999311521', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999388816', 7, 'Hoffman', 'demo123',
        'Gregory', 'Thomas', NOW() + '3 years'::INTERVAL, '1999-11-13', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '47163', '4971 Assembly Parkways', 't',
        'IN', 'Otisco', '', 'Clark', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999388816', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999345160', 8, 'Gonzalez', 'demo123',
        'Natalie', 'Joan', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '17120', '8835 Amazing Reduction Course', 't',
        'PA', 'Harrisburg', '', 'Dauphin', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999345160', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999328966', 9, 'Rucker', 'demo123',
        'Drew', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '92253', '5158 Redundant Reality Creek', 't',
        'CA', 'La quinta', '', 'Riverside', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999328966', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999394635', 9, 'Mitchell', 'demo123',
        'Kimberly', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '85375', '9724 Land Corner', 't',
        'AZ', 'Sun city west', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394635', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999333308', 7, 'Murray', 'demo123',
        'Heather', 'Margaret', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '51239', '5555 Project Bypass', 't',
        'IA', 'Hull', '', 'Sioux', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999333308', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999316647', 7, 'Sosa', 'demo123',
        'Roberta', 'Norma', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '94010', '4571 Jealous Comparison Wells', 't',
        'CA', 'Burlingame', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999316647', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999389066', 4, 'Ramos', 'demo123',
        'Annette', 'Angela', NOW() + '3 years'::INTERVAL, '1967-11-04', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '29621', '9196 Old Future Fort', 't',
        'SC', 'Anderson', '', 'Anderson', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999389066', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999380162', 8, 'Jackson', 'demo123',
        'Paul', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '77651', '9869 Convention Pine', 't', 
        'TX', 'Port neches', '', 'Jefferson', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999380162', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999318240', 7, 'Graham', 'demo123',
        'John', 'Charles', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '03216', '3676 Sweet Campaign Courts', 't',
        'NH', 'Andover', '', 'Merrimack', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999318240', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999347267', 7, 'Michael', 'demo123',
        'Adam', 'John', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '68113', '7244 Brief Tree Crescent', 't',
        'NE', 'Offutt a f b', '', 'Sarpy', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999347267', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999344618', 7, 'Thomas', 'demo123',
        'Helen', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '43534', '5066 Disabled Drink Ford', 't',
        'OH', 'Mc clure', '', 'Henry', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999344618', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999301966', 7, 'Rivas', 'demo123',
        'Meghan', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '48328', '1604 Other Factor Harbor', 't', 
        'MI', 'Waterford', '', 'Oakland', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999301966', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999306663', 5, 'Hurst', 'demo123',
        'William', 'Ian', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '76937', '7986 Line Grove', 't',
        'TX', 'Eola', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999306663', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999329410', 8, 'Bridges', 'demo123',
        'Kimberly', 'Anna', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '21047', '9992 Show Village', 't',
        'MD', 'Fallston', '', 'Harford', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999329410', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999396820', 6, 'Stewart', 'demo123',
        'Beatrice', 'Gloria', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '64123', '7373 Social Fact Roads', 't',
        'MO', 'Kansas city', '', 'Jackson', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999396820', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999398998', 7, 'Welsh', 'demo123',
        'Alejandra', 'Christine', NOW() + '3 years'::INTERVAL, '1973-11-18', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '91615', '4270 Deafening Speed Stream', 't',
        'CA', 'North hollywood', '', 'Los angeles', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999398998', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999308688', 9, 'Osborne', 'demo123',
        'Leona', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '65261', '1368 Defiant Visit Drive', 't',
        'MO', 'Keytesville', '', 'Chariton', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999308688', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999321465', 4, 'Sinclair', 'demo123',
        'Luella', 'Carole', NOW() + '3 years'::INTERVAL, '1993-10-15', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '45314', '3011 Thoughtful Law Terrace', 't',
        'OH', 'Cedarville', '', 'Greene', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999321465', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999399294', 5, 'Jones', 'demo123',
        'Joe', 'Wayne', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '12167', '1641 Jolly Period Bend', 't',
        'NY', 'Stamford', '', 'Delaware', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999399294', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999355645', 6, 'Duncan', 'demo123',
        'Willie', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '34682', '9904 Australian Cash Squares', 't',
        'FL', 'Palm harbor', '', 'Pinellas', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999355645', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999359616', 6, 'Carney', 'demo123',
        'Andrea', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '23442', '9706 Jealous Alternative Fort', 't', 
        'VA', 'Temperanceville', '', 'Accomack', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999359616', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999359143', 9, 'Hunt', 'demo123',
        'Howard', 'Ralph', NOW() + '3 years'::INTERVAL, '1971-05-09', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '49337', '1182 Radical Letter Square', 't',
        'MI', 'Newaygo', '', 'Newaygo', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999359143', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999389009', 6, 'Martin', 'demo123',
        'Eddie', 'Anthony', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '95031', '1938 Fundamental Distribution Lane', 't',
        'CA', 'Los gatos', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999389009', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999327461', 9, 'Barry', 'demo123',
        'Paul', 'Richard', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '40583', '9317 Testy Soil Place', 't',
        'KY', 'Lexington', '', 'Fayette', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999327461', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999319193', 7, 'Wright', 'demo123',
        'Dennis', 'Jimmie', NOW() + '3 years'::INTERVAL, '1992-09-05', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '24925', '7338 Drab Development Underpass', 't', 
        'WV', 'Caldwell', '', 'Greenbrier', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999319193', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999378520', 5, 'Saunders', 'demo123',
        'Ruben', 'Eric', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '32648', '2941 Conservation Race Haven', 't',
        'FL', 'Horseshoe beach', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999378520', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999366196', 7, 'Lane', 'demo123',
        'Jennifer', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '12456', '5547 Knee Underpass', 't',
        'NY', 'Mount marion', '', 'Ulster', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999366196', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999324371', 5, 'Madden', 'demo123',
        'Jo', 'Mae', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '19612', '3125 League Brook', 't',
        'PA', 'Reading', '', 'Berks', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999324371', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999316280', 8, 'Harding', 'demo123',
        'Naomi', 'Julie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '93021', '6693 Thin Entry Lake', 't', 
        'CA', 'Moorpark', '', 'Ventura', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999316280', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999388575', 5, 'Davis', 'demo123',
        'Blake', 'George', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '13856', '8634 Need Bridge', 't',
        'NY', 'Walton', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999388575', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999336610', 4, 'Barnes', 'demo123',
        'Norma', 'Gail', NOW() + '3 years'::INTERVAL, NOW() + '3 years'::INTERVAL, '');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '23107', '218 Region River', 't',
        'VA', 'Maryus', '', 'Gloucester', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999336610', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999376864', 4, 'Anderson', 'demo123',
        'Leon', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '27315', '9834 Standard Stravenue', 't',
        'NC', 'Providence', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999376864', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999391951', 7, 'Gillespie', 'demo123',
        'Misty', 'Margaret', NOW() + '3 years'::INTERVAL, '1993-10-19', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '47273', '4151 Severe Look Fort', 't',
        'IN', 'Scipio', '', 'Jennings', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999391951', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999368950', 7, 'Santos', 'demo123',
        'Esther', 'Mary', NOW() + '3 years'::INTERVAL, '1961-12-17', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '06468', '2774 Melted Stone Islands', 't',
        'CT', 'Monroe', '', 'Fairfield', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999368950', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999343281', 7, 'Bradley', 'demo123',
        'Rebecca', 'Vanessa', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '66948', '5933 Changing Terms Pike', 't',
        'KS', 'Jamestown', '', 'Cloud', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999343281', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999394534', 4, 'Hart', 'demo123',
        'Victor', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '16833', '677 Breezy Agreement Mountain', 't',
        'PA', 'Curwensville', '', 'Clearfield', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394534', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999323404', 8, 'Riley', 'demo123',
        'Edward', 'Lonnie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '84412', '5806 Metropolitan Problem Annex', 't',
        'UT', 'Ogden', '', 'Weber', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999323404', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999375760', 5, 'Jordan', 'demo123',
        'Michelle', '', NOW() + '3 years'::INTERVAL, '1973-05-07', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '46970', '8951 Great Arrangement Mills', 't',
        'IN', 'Peru', '', 'Miami', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999375760', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999315742', 7, 'Brown', 'demo123',
        'Mary', 'Jill', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '75663', '4845 Boat Course', 't',
        'TX', 'Kilgore', '', 'Gregg', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999315742', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999322514', 7, 'Barber', 'demo123',
        'Shawn', 'Thomas', NOW() + '3 years'::INTERVAL, '1988-10-21', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '98464', '7111 Accurate Talk Canyon', 't', 
        'WA', 'Tacoma', '', 'Pierce', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999322514', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999342144', 8, 'Harrison', 'demo123',
        'William', 'Phillip', NOW() + '3 years'::INTERVAL, '1990-04-09', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '79085', '9798 Marked West Fork', 't', 
        'TX', 'Summerfield', '', 'Castro', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999342144', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999320546', 7, 'Porter', 'demo123',
        'Darlene', 'Lisa', NOW() + '3 years'::INTERVAL, '1987-02-23', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '24910', '3522 Channel Radial', 't',
        'WV', 'Alderson', '', 'Monroe', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999320546', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999315474', 8, 'Lopez', 'demo123',
        'Joyce', 'Donna', NOW() + '3 years'::INTERVAL, '1980-06-28', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '89101', '9734 Civilian Position Hollow', 't',
        'NV', 'Las vegas', '', 'Clark', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999315474', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999371586', 9, 'Stevenson', 'demo123',
        'Larry', '', NOW() + '3 years'::INTERVAL, '1990-12-20', 'Sr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '46241', '5799 Constitutional Roof Groves', 't',
        'IN', 'Indianapolis', '', 'Marion', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999371586', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999329832', 4, 'Kinney', 'demo123',
        'Nicholas', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '90606', '411 Preliminary Library Square', 't', 
        'CA', 'Whittier', '', 'Los angeles', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999329832', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999342948', 5, 'Bernard', 'demo123',
        'Omar', 'David', NOW() + '3 years'::INTERVAL, '1981-08-19', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '41567', '2546 Marvellous Index Ways', 't',
        'KY', 'Stone', '', 'Pike', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999342948', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999335091', 9, 'Brown', 'demo123',
        'Mary', 'Annie', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '07630', '48 Look Ridge', 't',
        'NJ', 'Emerson', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999335091', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999303411', 8, 'Smith', 'demo123',
        'Sarah', '', NOW() + '3 years'::INTERVAL, '1990-01-13', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '34972', '845 Relative Dress Mall', 't',
        'FL', 'Okeechobee', '', 'Okeechobee', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999303411', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999327083', 8, 'Jones', 'demo123',
        'Cora', '', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '65262', '9202 Tight Subject Highway', 't',
        'MO', 'Kingdom city', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999327083', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999300523', 7, 'Little', 'demo123',
        'Shawn', 'Joseph', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '86343', '8169 Vast Passage Key', 't',
        'AZ', 'Crown king', '', 'Yavapai', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999300523', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999328829', 6, 'Thurman', 'demo123',
        'Luann', 'Donna', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '63463', '1967 Interesting Court Ford', 't',
        'MO', 'Philadelphia', '', 'Marion', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999328829', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999394673', 6, 'Scott', 'demo123',
        'Patricia', 'Robin', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '44241', '8955 Due Population Alley', 't',
        'OH', 'Streetsboro', '', 'Portage', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999394673', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999355318', 5, 'Lamb', 'demo123',
        'Esperanza', 'Beth', NOW() + '3 years'::INTERVAL, '1995-06-13', 'III');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '05501', '9042 Just Show Turnpike', 't',
        'MA', 'Andover', '', 'Essex', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999355318', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999377675', 8, 'Brown', 'demo123',
        'Wendi', 'Mary', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '37721', '7546 Rude Agreement Highway', 't',
        'TN', 'Corryton', '', 'Knox', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999377675', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999363186', 5, 'Clarke', 'demo123',
        'Lawrence', 'Vern', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '76234', '7903 Surprised Rule Loop', 't',
        'TX', 'Decatur', '', 'Wise', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999363186', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999346314', 8, 'Clark', 'demo123',
        'Daniel', 'Ricky', NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '70706', '8604 Defensive Case Trace', 't', 
        'LA', 'Denham springs', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999346314', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999353477', 6, 'Dennis', 'demo123',
        'John', 'Robert', NOW() + '3 years'::INTERVAL, '1975-03-04', NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '14480', '8712 Legislative Box Shore', 't',
        'NY', 'Lakeville', '', 'Livingston', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999353477', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999312358', 4, 'Copeland', 'demo123',
        'Jan', 'Lindsey', NOW() + '3 years'::INTERVAL, '1998-06-14', 'Jr');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 'f', '83204', '6713 River Bridge', 't',
        'ID', 'Pocatello', '', 'Bannock', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999312358', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999360839', 8, 'Brooks', 'demo123',
        'Penny', 'Martha', NOW() + '3 years'::INTERVAL, '1980-03-13', 'II');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '79120', '8208 Death Ramp', 't',
        'TX', 'Amarillo', '', 'Potter', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999360839', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999342446', 8, 'Johnson', 'demo123',
        'Jeanne', '', NOW() + '3 years'::INTERVAL, '1980-02-03', NULL);

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '85036', '9634 Tough Division Junction', 't', 
        'AZ', 'Phoenix', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999342446', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 1, '99999358416', 4, 'Sanford', 'demo123',
        'Elizabeth', 'Vanessa', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '98357', '6767 Application Course', 't',
        'WA', 'Neah bay', '', 'Clallam', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999358416', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');


INSERT INTO actor.usr 
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix) 
    VALUES (2, 3, '99999361389', 9, 'Ramirez', 'demo123',
        'Alan', 'Claude', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address 
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr) 
    VALUES ('USA', 't', '76060', '9964 Skinny Party Orchard', 't', 
        'TX', 'Kennedale', '', 'Tarrant', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr) 
    VALUES ('99999361389', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET 
    card = CURRVAL('actor.card_id_seq'), 
    billing_address = CURRVAL('actor.usr_address_id_seq'), 
    credit_forward_balance = '0', 
    mailing_address = CURRVAL('actor.usr_address_id_seq') 
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, 'jbautista', 9, 'Bautista', 'demo123',
        'José', 'Antonio', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('Canada', 't', 'H3B 1X9', '800 René-Lévesque Blvd W', 't',
        'QC', 'Montréal', 'Suite 201', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999361323', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');

INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, 'mkawasaki', 9, 'Kawasaki', 'demo123',
        '川﨑 宗則', 'Munenori', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('Canada', 't', 'H3B 1X9', '800 René-Lévesque Blvd W', 't',
        'QC', 'Montréal', 'Suite 101', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999361366', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');


-- users for auth testing
-- barcode pattern: 99999393XXX

-- expired
INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, '99999393001', 4, 'Simpson', 'demo123',
        'Marge', '', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('USA', 't', '20521', '742 Evergreen Terrace', 't',
        'NT', 'Springfield', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999393001', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');

UPDATE actor.usr SET expire_date = '2010-01-01' WHERE id=CURRVAL('actor.usr_id_seq');

-- deleted
INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, '99999393002', 4, 'Simpson', 'demo123',
        'Homer', '', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('USA', 't', '20521', '742 Evergreen Terrace', 't',
        'NT', 'Springfield', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999393002', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');

UPDATE actor.usr SET deleted = TRUE WHERE id=CURRVAL('actor.usr_id_seq');

-- barred
INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, '99999393003', 4, 'Simpson', 'demo123',
        'Bart', '', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('USA', 't', '20521', '742 Evergreen Terrace', 't',
        'NT', 'Springfield', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999393003', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');

UPDATE actor.usr SET barred = TRUE WHERE id=CURRVAL('actor.usr_id_seq');

-- valid
INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, '99999393004', 4, 'Simpson', 'demo123',
        'Lisa', '', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('USA', 't', '20521', '742 Evergreen Terrace', 't',
        'NT', 'Springfield', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999393004', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');

-- inactive
INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, '99999393005', 4, 'Simpson', 'demo123',
        'Maggie', '', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('USA', 't', '20521', '742 Evergreen Terrace', 't',
        'NT', 'Springfield', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999393005', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');

UPDATE actor.usr SET active = FALSE WHERE id=CURRVAL('actor.usr_id_seq');

-- external
INSERT INTO actor.usr
    (profile, ident_type, usrname, home_ou, family_name, passwd, first_given_name, second_given_name, expire_date, dob, suffix)
    VALUES (2, 3, '99999393100', 6, 'Manhattan', 'demo123',
        'Shelbyville', '', NOW() + '3 years'::INTERVAL, NULL, '');

INSERT INTO actor.usr_address
    (country, within_city_limits, post_code, street1, valid, state, city, street2, county, usr)
    VALUES ('USA', 't', '20521', '1 Shelbyville Way', 't',
        'NT', 'Shelbyville', '', '', CURRVAL('actor.usr_id_seq'));

INSERT INTO actor.card (barcode, usr)
    VALUES ('99999393100', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr SET
    card = CURRVAL('actor.card_id_seq'),
    billing_address = CURRVAL('actor.usr_address_id_seq'),
    credit_forward_balance = '0',
    mailing_address = CURRVAL('actor.usr_address_id_seq')
    WHERE id=CURRVAL('actor.usr_id_seq');
