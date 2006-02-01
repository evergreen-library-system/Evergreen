
DROP SCHEMA stats CASCADE;
DROP SCHEMA config CASCADE;

BEGIN;
CREATE SCHEMA stats;

CREATE SCHEMA config;
COMMENT ON SCHEMA config IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * The config schema holds static configuration data for the
 * Open-ILS installation.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;


CREATE TABLE config.bib_source (
	id	SERIAL	PRIMARY KEY,
	quality	INT	CHECK ( quality BETWEEN 0 AND 100 ),
	source	TEXT	NOT NULL UNIQUE
);
COMMENT ON TABLE config.bib_source IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Valid sources of MARC records
 *
 * This is table is used to set up the relative "quality" of each
 * MARC source, such as OCLC.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;


INSERT INTO config.bib_source (quality, source) VALUES (90, 'OcLC');
INSERT INTO config.bib_source (quality, source) VALUES (10, 'System Local');

CREATE TABLE config.standing (
	id		SERIAL	PRIMARY KEY,
	value		TEXT	NOT NULL UNIQUE
);
COMMENT ON TABLE config.standing IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Patron Standings
 *
 * This table contains the values that can be applied to a patron
 * by a staff member.  These values should not be changed, other
 * that for translation, as the ID column is currently a "magic
 * number" in the source. :(
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

INSERT INTO config.standing (value) VALUES ('Good');
INSERT INTO config.standing (value) VALUES ('Barred');



CREATE TABLE config.metabib_field (
	id		SERIAL	PRIMARY KEY,
	field_class	TEXT	NOT NULL CHECK (lower(field_class) IN ('title','author','subject','keyword','series')),
	name		TEXT	NOT NULL UNIQUE,
	xpath		TEXT	NOT NULL
);
COMMENT ON TABLE config.metabib_field IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * XPath used for WoRMing
 *
 * This table contains the XPath used to chop up MODS into it's
 * indexable parts.  Each XPath entry is named and assigned to
 * a "class" of either title, subject, author, keyword or series.
 * 
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;


INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'series', 'seriestitle', $$//mods:mods/mods:relatedItem[@type="series"]/mods:titleInfo$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'abbreviated', $$//mods:mods/mods:titleInfo[mods:title and (@type='abreviated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'translated', $$//mods:mods/mods:titleInfo[mods:title and (@type='translated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'uniform', $$//mods:mods/mods:titleInfo[mods:title and (@type='uniform')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'proper', $$//mods:mods/mods:titleInfo[mods:title and not (@type)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'corporate', $$//mods:mods/mods:name[@type='corporate']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'personal', $$//mods:mods/mods:name[@type='personal']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'conference', $$//mods:mods/mods:name[@type='conference']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'other', $$//mods:mods/mods:name[@type='personal']/mods:namePart[not(../mods:role)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'geographic', $$//mods:mods/mods:subject/mods:geographic$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'name', $$//mods:mods/mods:subject/mods:name$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'temporal', $$//mods:mods/mods:subject/mods:temporal$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'topic', $$//mods:mods/mods:subject/mods:topic$$ );
-- INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'genre', $$//mods:mods/mods:genre$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'keyword', 'keyword', $$//mods:mods/*[not(local-name()='originInfo')]$$ ); -- /* to fool vim */

CREATE TABLE config.non_cataloged_type (
	id		SERIAL		PRIMARY KEY,
	owning_lib	INT		NOT NULL, -- REFERENCES actor.org_unit (id),
	name		TEXT		NOT NULL UNIQUE,
	circ_duration	INTERVAL	NOT NULL DEFAULT '14 days'::INTERVAL
);
COMMENT ON TABLE config.non_cataloged_type IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Types of valid non-cataloged items.
 *
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;


INSERT INTO config.non_cataloged_type ( owning_lib, name ) VALUES ( 1, 'Paperback Book' );

CREATE TABLE config.identification_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE
);
COMMENT ON TABLE config.identification_type IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Types of valid patron identification.
 *
 * Each patron must display at least one valid form of identification
 * in order to get a library card.  This table lists those forms.
 * 
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;


INSERT INTO config.identification_type ( name ) VALUES ( 'Drivers Licence' );
INSERT INTO config.identification_type ( name ) VALUES ( 'Voter Card' );
INSERT INTO config.identification_type ( name ) VALUES ( 'Two Utility Bills' );
INSERT INTO config.identification_type ( name ) VALUES ( 'State ID' );
INSERT INTO config.identification_type ( name ) VALUES ( 'SSN' );

CREATE TABLE config.rule_circ_duration (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	extended	INTERVAL	NOT NULL,
	normal		INTERVAL	NOT NULL,
	shrt		INTERVAL	NOT NULL,
	max_renewals	INT		NOT NULL
);
COMMENT ON TABLE config.rule_circ_duration IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Circulation Duration rules
 *
 * Each circulation is given a duration based on one of these rules.
 * 
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

INSERT INTO config.rule_circ_duration VALUES (DEFAULT, '2wk_default', '21 days', '14 days', '7 days', 2);


CREATE TABLE config.rule_max_fine (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	amount	NUMERIC(6,2)	NOT NULL
);
COMMENT ON TABLE config.rule_max_fine IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Circulation Max Fine rules
 *
 * Each circulation is given a maximum fine based on one of
 * these rules.
 * 
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

INSERT INTO config.rule_max_fine VALUES (DEFAULT, 'books', 50.00);


CREATE TABLE config.rule_recuring_fine (
	id			SERIAL		PRIMARY KEY,
	name			TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	high			NUMERIC(6,2)	NOT NULL,
	normal			NUMERIC(6,2)	NOT NULL,
	low			NUMERIC(6,2)	NOT NULL,
	recurance_interval	INTERVAL	NOT NULL DEFAULT '1 day'::INTERVAL
);
COMMENT ON TABLE config.rule_recuring_fine IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Circulation Recuring Fine rules
 *
 * Each circulation is given a recuring fine amount based on one of
 * these rules.  The recurance_interval should not be any shorter
 * than the interval between runs of the fine_processor.pl script
 * (which is run from CRON), or you could miss fines.
 * 
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

INSERT INTO config.rule_recuring_fine VALUES (1, 'books', 0.50, 0.10, 0.10, '1 day');


CREATE TABLE config.rule_age_hold_protect (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	age	INTERVAL	NOT NULL,
	prox	INT		NOT NULL
);
COMMENT ON TABLE config.rule_age_hold_protect IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Hold Item Age Protection rules
 *
 * A hold request can only capture new(ish) items when they are
 * within a particular proximity of the home_ou of the requesting
 * user.  The proximity ('prox' column) is calculated by counting
 * the number of tree edges beween the user's home_ou and the owning_lib
 * of the copy that could fulfill the hold.
 * 
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

INSERT INTO config.rule_age_hold_protect VALUES (DEFAULT, '3month', '3 mons', 0);
INSERT INTO config.rule_age_hold_protect VALUES (DEFAULT, '6month', '6 mons', 2);


CREATE TABLE config.copy_status (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	holdable	BOOL	NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE config.copy_status IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Copy Statuses
 *
 * The available copy statuses, and whether a copy in that
 * status is available for hold request capture.  0 (zero) is
 * the only special number in this set, meaning that the item
 * is available for imediate checkout, and is counted as available
 * in the OPAC.
 *
 * Statuses with an ID below 100 are not removable, and have special
 * meaning in the code.  Do not change them except to translate the
 * textual name.
 *
 * You may add and remove statuses above 100, and these can be used
 * to remove items from normal circulation without affecting the rest
 * of the copy's values or it's location.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

INSERT INTO config.copy_status (id,name,holdable)	VALUES (0,'Available','t');
INSERT INTO config.copy_status (name,holdable)		VALUES ('Checked out','t');
INSERT INTO config.copy_status (name)			VALUES ('Bindery');
INSERT INTO config.copy_status (name)			VALUES ('Lost');
INSERT INTO config.copy_status (name)			VALUES ('Missing');
INSERT INTO config.copy_status (name,holdable)		VALUES ('In process','t');
INSERT INTO config.copy_status (name,holdable)		VALUES ('In transit','t');
INSERT INTO config.copy_status (name,holdable)		VALUES ('Reshelving','t');
INSERT INTO config.copy_status (name)			VALUES ('On holds shelf');
INSERT INTO config.copy_status (name,holdable)		VALUES ('On order','t');
INSERT INTO config.copy_status (name)			VALUES ('ILL');
INSERT INTO config.copy_status (name)			VALUES ('Cataloging');
INSERT INTO config.copy_status (name)			VALUES ('Reserves');
INSERT INTO config.copy_status (name)			VALUES ('Discard/Weed');

SELECT SETVAL('config.copy_status_id_seq'::TEXT, 100);


CREATE TABLE config.net_access_level (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE
);
COMMENT ON TABLE config.net_access_level IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Patron Network Access level
 *
 * This will be used to inform the in-library firewall of how much
 * internet access the using patron should be allowed.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

INSERT INTO config.net_access_level (name) VALUES ('Restricted');
INSERT INTO config.net_access_level (name) VALUES ('Full');
INSERT INTO config.net_access_level (name) VALUES ('None');

CREATE TABLE config.language_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

COPY config.language_map FROM STDIN;
aar	Afar
abk	Abkhaz
ace	Achinese
ach	Acoli
ada	Adangme
ady	Adygei
afa	Afroasiatic (Other)
afh	Afrihili (Artificial language)
afr	Afrikaans
-ajm	Aljamía
aka	Akan
akk	Akkadian
alb	Albanian
ale	Aleut
alg	Algonquian (Other)
amh	Amharic
ang	English, Old (ca. 450-1100)
apa	Apache languages
ara	Arabic
arc	Aramaic
arg	Aragonese Spanish
arm	Armenian
arn	Mapuche
arp	Arapaho
art	Artificial (Other)
arw	Arawak
asm	Assamese
ast	Bable
ath	Athapascan (Other)
aus	Australian languages
ava	Avaric
ave	Avestan
awa	Awadhi
aym	Aymara
aze	Azerbaijani
bad	Banda
bai	Bamileke languages
bak	Bashkir
bal	Baluchi
bam	Bambara
ban	Balinese
baq	Basque
bas	Basa
bat	Baltic (Other)
bej	Beja
bel	Belarusian
bem	Bemba
ben	Bengali
ber	Berber (Other)
bho	Bhojpuri
bih	Bihari
bik	Bikol
bin	Edo
bis	Bislama
bla	Siksika
bnt	Bantu (Other)
bos	Bosnian
bra	Braj
bre	Breton
btk	Batak
bua	Buriat
bug	Bugis
bul	Bulgarian
bur	Burmese
cad	Caddo
cai	Central American Indian (Other)
-cam	Khmer
car	Carib
cat	Catalan
cau	Caucasian (Other)
ceb	Cebuano
cel	Celtic (Other)
cha	Chamorro
chb	Chibcha
che	Chechen
chg	Chagatai
chi	Chinese
chk	Truk
chm	Mari
chn	Chinook jargon
cho	Choctaw
chp	Chipewyan
chr	Cherokee
chu	Church Slavic
chv	Chuvash
chy	Cheyenne
cmc	Chamic languages
cop	Coptic
cor	Cornish
cos	Corsican
cpe	Creoles and Pidgins, English-based (Other)
cpf	Creoles and Pidgins, French-based (Other)
cpp	Creoles and Pidgins, Portuguese-based (Other)
cre	Cree
crh	Crimean Tatar
crp	Creoles and Pidgins (Other)
cus	Cushitic (Other)
cze	Czech
dak	Dakota
dan	Danish
dar	Dargwa
day	Dayak
del	Delaware
den	Slave
dgr	Dogrib
din	Dinka
div	Divehi
doi	Dogri
dra	Dravidian (Other)
dua	Duala
dum	Dutch, Middle (ca. 1050-1350)
dut	Dutch
dyu	Dyula
dzo	Dzongkha
efi	Efik
egy	Egyptian
eka	Ekajuk
elx	Elamite
eng	English
enm	English, Middle (1100-1500)
epo	Esperanto
-esk	Eskimo languages
-esp	Esperanto
est	Estonian
-eth	Ethiopic
ewe	Ewe
ewo	Ewondo
fan	Fang
fao	Faroese
-far	Faroese
fat	Fanti
fij	Fijian
fin	Finnish
fiu	Finno-Ugrian (Other)
fon	Fon
fre	French
-fri	Frisian
frm	French, Middle (ca. 1400-1600)
fro	French, Old (ca. 842-1400)
fry	Frisian
ful	Fula
fur	Friulian
gaa	Gã
-gae	Scottish Gaelic
-gag	Galician
-gal	Oromo
gay	Gayo
gba	Gbaya
gem	Germanic (Other)
geo	Georgian
ger	German
gez	Ethiopic
gil	Gilbertese
gla	Scottish Gaelic
gle	Irish
glg	Galician
glv	Manx
gmh	German, Middle High (ca. 1050-1500)
goh	German, Old High (ca. 750-1050)
gon	Gondi
gor	Gorontalo
got	Gothic
grb	Grebo
grc	Greek, Ancient (to 1453)
gre	Greek, Modern (1453- )
grn	Guarani
-gua	Guarani
guj	Gujarati
gwi	Gwich'in
hai	Haida
hat	Haitian French Creole
hau	Hausa
haw	Hawaiian
heb	Hebrew
her	Herero
hil	Hiligaynon
him	Himachali
hin	Hindi
hit	Hittite
hmn	Hmong
hmo	Hiri Motu
hun	Hungarian
hup	Hupa
iba	Iban
ibo	Igbo
ice	Icelandic
ido	Ido
iii	Sichuan Yi
ijo	Ijo
iku	Inuktitut
ile	Interlingue
ilo	Iloko
ina	Interlingua (International Auxiliary Language Association)
inc	Indic (Other)
ind	Indonesian
ine	Indo-European (Other)
inh	Ingush
-int	Interlingua (International Auxiliary Language Association)
ipk	Inupiaq
ira	Iranian (Other)
-iri	Irish
iro	Iroquoian (Other)
ita	Italian
jav	Javanese
jpn	Japanese
jpr	Judeo-Persian
jrb	Judeo-Arabic
kaa	Kara-Kalpak
kab	Kabyle
kac	Kachin
kal	Kalâtdlisut
kam	Kamba
kan	Kannada
kar	Karen
kas	Kashmiri
kau	Kanuri
kaw	Kawi
kaz	Kazakh
kbd	Kabardian
kha	Khasi
khi	Khoisan (Other)
khm	Khmer
kho	Khotanese
kik	Kikuyu
kin	Kinyarwanda
kir	Kyrgyz
kmb	Kimbundu
kok	Konkani
kom	Komi
kon	Kongo
kor	Korean
kos	Kusaie
kpe	Kpelle
kro	Kru
kru	Kurukh
kua	Kuanyama
kum	Kumyk
kur	Kurdish
-kus	Kusaie
kut	Kutenai
lad	Ladino
lah	Lahnda
lam	Lamba
-lan	Occitan (post-1500)
lao	Lao
-lap	Sami
lat	Latin
lav	Latvian
lez	Lezgian
lim	Limburgish
lin	Lingala
lit	Lithuanian
lol	Mongo-Nkundu
loz	Lozi
ltz	Letzeburgesch
lua	Luba-Lulua
lub	Luba-Katanga
lug	Ganda
lui	Luiseño
lun	Lunda
luo	Luo (Kenya and Tanzania)
lus	Lushai
mac	Macedonian
mad	Madurese
mag	Magahi
mah	Marshallese
mai	Maithili
mak	Makasar
mal	Malayalam
man	Mandingo
mao	Maori
map	Austronesian (Other)
mar	Marathi
mas	Masai
-max	Manx
may	Malay
mdr	Mandar
men	Mende
mga	Irish, Middle (ca. 1100-1550)
mic	Micmac
min	Minangkabau
mis	Miscellaneous languages
mkh	Mon-Khmer (Other)
-mla	Malagasy
mlg	Malagasy
mlt	Maltese
mnc	Manchu
mni	Manipuri
mno	Manobo languages
moh	Mohawk
mol	Moldavian
mon	Mongolian
mos	Mooré
mul	Multiple languages
mun	Munda (Other)
mus	Creek
mwr	Marwari
myn	Mayan languages
nah	Nahuatl
nai	North American Indian (Other)
nap	Neapolitan Italian
nau	Nauru
nav	Navajo
nbl	Ndebele (South Africa)
nde	Ndebele (Zimbabwe)  
ndo	Ndonga
nds	Low German
nep	Nepali
new	Newari
nia	Nias
nic	Niger-Kordofanian (Other)
niu	Niuean
nno	Norwegian (Nynorsk)
nob	Norwegian (Bokmål)
nog	Nogai
non	Old Norse
nor	Norwegian
nso	Northern Sotho
nub	Nubian languages
nya	Nyanja
nym	Nyamwezi
nyn	Nyankole
nyo	Nyoro
nzi	Nzima
oci	Occitan (post-1500)
oji	Ojibwa
ori	Oriya
orm	Oromo
osa	Osage
oss	Ossetic
ota	Turkish, Ottoman
oto	Otomian languages
paa	Papuan (Other)
pag	Pangasinan
pal	Pahlavi
pam	Pampanga
pan	Panjabi
pap	Papiamento
pau	Palauan
peo	Old Persian (ca. 600-400 B.C.)
per	Persian
phi	Philippine (Other)
phn	Phoenician
pli	Pali
pol	Polish
pon	Ponape
por	Portuguese
pra	Prakrit languages
pro	Provençal (to 1500)
pus	Pushto
que	Quechua
raj	Rajasthani
rap	Rapanui
rar	Rarotongan
roa	Romance (Other)
roh	Raeto-Romance
rom	Romani
rum	Romanian
run	Rundi
rus	Russian
sad	Sandawe
sag	Sango (Ubangi Creole)
sah	Yakut
sai	South American Indian (Other)
sal	Salishan languages
sam	Samaritan Aramaic
san	Sanskrit
-sao	Samoan
sas	Sasak
sat	Santali
scc	Serbian
sco	Scots
scr	Croatian
sel	Selkup
sem	Semitic (Other)
sga	Irish, Old (to 1100)
sgn	Sign languages
shn	Shan
-sho	Shona
sid	Sidamo
sin	Sinhalese
sio	Siouan (Other)
sit	Sino-Tibetan (Other)
sla	Slavic (Other)
slo	Slovak
slv	Slovenian
sma	Southern Sami
sme	Northern Sami
smi	Sami
smj	Lule Sami
smn	Inari Sami
smo	Samoan
sms	Skolt Sami
sna	Shona
snd	Sindhi
-snh	Sinhalese
snk	Soninke
sog	Sogdian
som	Somali
son	Songhai
sot	Sotho
spa	Spanish
srd	Sardinian
srr	Serer
ssa	Nilo-Saharan (Other)
-sso	Sotho
ssw	Swazi
suk	Sukuma
sun	Sundanese
sus	Susu
sux	Sumerian
swa	Swahili
swe	Swedish
-swz	Swazi
syr	Syriac
-tag	Tagalog
tah	Tahitian
tai	Tai (Other)
-taj	Tajik
tam	Tamil
-tar	Tatar
tat	Tatar
tel	Telugu
tem	Temne
ter	Terena
tet	Tetum
tgk	Tajik
tgl	Tagalog
tha	Thai
tib	Tibetan
tig	Tigré
tir	Tigrinya
tiv	Tiv
tkl	Tokelauan
tli	Tlingit
tmh	Tamashek
tog	Tonga (Nyasa)
ton	Tongan
tpi	Tok Pisin
-tru	Truk
tsi	Tsimshian
tsn	Tswana
tso	Tsonga
-tsw	Tswana
tuk	Turkmen
tum	Tumbuka
tup	Tupi languages
tur	Turkish
tut	Altaic (Other)
tvl	Tuvaluan
twi	Twi
tyv	Tuvinian
udm	Udmurt
uga	Ugaritic
uig	Uighur
ukr	Ukrainian
umb	Umbundu
und	Undetermined
urd	Urdu
uzb	Uzbek
vai	Vai
ven	Venda
vie	Vietnamese
vol	Volapük
vot	Votic
wak	Wakashan languages
wal	Walamo
war	Waray
was	Washo
wel	Welsh
wen	Sorbian languages
wln	Walloon
wol	Wolof
xal	Kalmyk
xho	Xhosa
yao	Yao (Africa)
yap	Yapese
yid	Yiddish
yor	Yoruba
ypk	Yupik languages
zap	Zapotec
zen	Zenaga
zha	Zhuang
znd	Zande
zul	Zulu
zun	Zuni
\.

CREATE TABLE config.item_form_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

COPY config.item_form_map FROM STDIN;
a	Microfilm
b	Microfiche
c	Microopaque
d	Large print
f	Braille
r	Regular print reproduction
s	Electronic
\.

CREATE TABLE config.item_type_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

COPY config.item_type_map FROM STDIN;
a	Language material
t	Manuscript language material
g	Projected medium
k	Two-dimensional nonprojectable graphic
r	Three-dimensional artifact or naturally occurring object
o	Kit
p	Mixed materials
e	Cartographic material
f	Manuscript cartographic material
c	Notated music
d	Manuscript notated music
i	Nonmusical sound recording
j	Musical sound recording
m	Computer file
\.

COMMIT;

