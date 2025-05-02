BEGIN;

SELECT evergreen.upgrade_deps_block_check('1416_fix', :eg_version);

TRUNCATE config.coded_value_map CASCADE;

-- TO-DO: Auto-generate these values from CLDR
-- XXX These are the values used in MARC records ... does that match CLDR, including deprecated languages?
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
    (1, 'item_lang', 'aar', oils_i18n_gettext('aar', 'Afar', 'ccvm', 'value')),
    (2, 'item_lang', 'abk', oils_i18n_gettext('abk', 'Abkhaz', 'ccvm', 'value')),
    (3, 'item_lang', 'ace', oils_i18n_gettext('ace', 'Achinese', 'ccvm', 'value')),
    (4, 'item_lang', 'ach', oils_i18n_gettext('ach', 'Acoli', 'ccvm', 'value')),
    (5, 'item_lang', 'ada', oils_i18n_gettext('ada', 'Adangme', 'ccvm', 'value')),
    (6, 'item_lang', 'ady', oils_i18n_gettext('ady', 'Adygei', 'ccvm', 'value')),
    (7, 'item_lang', 'afa', oils_i18n_gettext('afa', 'Afroasiatic (Other)', 'ccvm', 'value')),
    (8, 'item_lang', 'afh', oils_i18n_gettext('afh', 'Afrihili (Artificial language)', 'ccvm', 'value')),
    (9, 'item_lang', 'afr', oils_i18n_gettext('afr', 'Afrikaans', 'ccvm', 'value')),
    (10, 'item_lang', '-ajm', oils_i18n_gettext('-ajm', 'Aljamía', 'ccvm', 'value')),
    (11, 'item_lang', 'aka', oils_i18n_gettext('aka', 'Akan', 'ccvm', 'value')),
    (12, 'item_lang', 'akk', oils_i18n_gettext('akk', 'Akkadian', 'ccvm', 'value')),
    (13, 'item_lang', 'alb', oils_i18n_gettext('alb', 'Albanian', 'ccvm', 'value')),
    (14, 'item_lang', 'ale', oils_i18n_gettext('ale', 'Aleut', 'ccvm', 'value')),
    (15, 'item_lang', 'alg', oils_i18n_gettext('alg', 'Algonquian (Other)', 'ccvm', 'value')),
    (16, 'item_lang', 'amh', oils_i18n_gettext('amh', 'Amharic', 'ccvm', 'value')),
    (17, 'item_lang', 'ang', oils_i18n_gettext('ang', 'English, Old (ca. 450-1100)', 'ccvm', 'value')),
    (18, 'item_lang', 'apa', oils_i18n_gettext('apa', 'Apache languages', 'ccvm', 'value')),
    (19, 'item_lang', 'ara', oils_i18n_gettext('ara', 'Arabic', 'ccvm', 'value')),
    (20, 'item_lang', 'arc', oils_i18n_gettext('arc', 'Aramaic', 'ccvm', 'value')),
    (21, 'item_lang', 'arg', oils_i18n_gettext('arg', 'Aragonese Spanish', 'ccvm', 'value')),
    (22, 'item_lang', 'arm', oils_i18n_gettext('arm', 'Armenian', 'ccvm', 'value')),
    (23, 'item_lang', 'arn', oils_i18n_gettext('arn', 'Mapuche', 'ccvm', 'value')),
    (24, 'item_lang', 'arp', oils_i18n_gettext('arp', 'Arapaho', 'ccvm', 'value')),
    (25, 'item_lang', 'art', oils_i18n_gettext('art', 'Artificial (Other)', 'ccvm', 'value')),
    (26, 'item_lang', 'arw', oils_i18n_gettext('arw', 'Arawak', 'ccvm', 'value')),
    (27, 'item_lang', 'asm', oils_i18n_gettext('asm', 'Assamese', 'ccvm', 'value')),
    (28, 'item_lang', 'ast', oils_i18n_gettext('ast', 'Bable', 'ccvm', 'value')),
    (29, 'item_lang', 'ath', oils_i18n_gettext('ath', 'Athapascan (Other)', 'ccvm', 'value')),
    (30, 'item_lang', 'aus', oils_i18n_gettext('aus', 'Australian languages', 'ccvm', 'value')),
    (31, 'item_lang', 'ava', oils_i18n_gettext('ava', 'Avaric', 'ccvm', 'value')),
    (32, 'item_lang', 'ave', oils_i18n_gettext('ave', 'Avestan', 'ccvm', 'value')),
    (33, 'item_lang', 'awa', oils_i18n_gettext('awa', 'Awadhi', 'ccvm', 'value')),
    (34, 'item_lang', 'aym', oils_i18n_gettext('aym', 'Aymara', 'ccvm', 'value')),
    (35, 'item_lang', 'aze', oils_i18n_gettext('aze', 'Azerbaijani', 'ccvm', 'value')),
    (36, 'item_lang', 'bad', oils_i18n_gettext('bad', 'Banda', 'ccvm', 'value')),
    (37, 'item_lang', 'bai', oils_i18n_gettext('bai', 'Bamileke languages', 'ccvm', 'value')),
    (38, 'item_lang', 'bak', oils_i18n_gettext('bak', 'Bashkir', 'ccvm', 'value')),
    (39, 'item_lang', 'bal', oils_i18n_gettext('bal', 'Baluchi', 'ccvm', 'value')),
    (40, 'item_lang', 'bam', oils_i18n_gettext('40', 'Bambara', 'ccvm', 'value')),
    (41, 'item_lang', 'ban', oils_i18n_gettext('41', 'Balinese', 'ccvm', 'value')),
    (42, 'item_lang', 'baq', oils_i18n_gettext('42', 'Basque', 'ccvm', 'value')),
    (43, 'item_lang', 'bas', oils_i18n_gettext('43', 'Basa', 'ccvm', 'value')),
    (44, 'item_lang', 'bat', oils_i18n_gettext('44', 'Baltic (Other)', 'ccvm', 'value')),
    (45, 'item_lang', 'bej', oils_i18n_gettext('45', 'Beja', 'ccvm', 'value')),
    (46, 'item_lang', 'bel', oils_i18n_gettext('46', 'Belarusian', 'ccvm', 'value')),
    (47, 'item_lang', 'bem', oils_i18n_gettext('47', 'Bemba', 'ccvm', 'value')),
    (48, 'item_lang', 'ben', oils_i18n_gettext('48', 'Bengali', 'ccvm', 'value')),
    (49, 'item_lang', 'ber', oils_i18n_gettext('49', 'Berber (Other)', 'ccvm', 'value')),
    (50, 'item_lang', 'bho', oils_i18n_gettext('50', 'Bhojpuri', 'ccvm', 'value')),
    (51, 'item_lang', 'bih', oils_i18n_gettext('51', 'Bihari', 'ccvm', 'value')),
    (52, 'item_lang', 'bik', oils_i18n_gettext('52', 'Bikol', 'ccvm', 'value')),
    (53, 'item_lang', 'bin', oils_i18n_gettext('53', 'Edo', 'ccvm', 'value')),
    (54, 'item_lang', 'bis', oils_i18n_gettext('54', 'Bislama', 'ccvm', 'value')),
    (55, 'item_lang', 'bla', oils_i18n_gettext('55', 'Siksika', 'ccvm', 'value')),
    (56, 'item_lang', 'bnt', oils_i18n_gettext('56', 'Bantu (Other)', 'ccvm', 'value')),
    (57, 'item_lang', 'bos', oils_i18n_gettext('57', 'Bosnian', 'ccvm', 'value')),
    (58, 'item_lang', 'bra', oils_i18n_gettext('58', 'Braj', 'ccvm', 'value')),
    (59, 'item_lang', 'bre', oils_i18n_gettext('59', 'Breton', 'ccvm', 'value')),
    (60, 'item_lang', 'btk', oils_i18n_gettext('60', 'Batak', 'ccvm', 'value')),
    (61, 'item_lang', 'bua', oils_i18n_gettext('61', 'Buriat', 'ccvm', 'value')),
    (62, 'item_lang', 'bug', oils_i18n_gettext('62', 'Bugis', 'ccvm', 'value')),
    (63, 'item_lang', 'bul', oils_i18n_gettext('63', 'Bulgarian', 'ccvm', 'value')),
    (64, 'item_lang', 'bur', oils_i18n_gettext('64', 'Burmese', 'ccvm', 'value')),
    (65, 'item_lang', 'cad', oils_i18n_gettext('65', 'Caddo', 'ccvm', 'value')),
    (66, 'item_lang', 'cai', oils_i18n_gettext('66', 'Central American Indian (Other)', 'ccvm', 'value')),
    (67, 'item_lang', '-cam', oils_i18n_gettext('67', 'Khmer', 'ccvm', 'value')),
    (68, 'item_lang', 'car', oils_i18n_gettext('68', 'Carib', 'ccvm', 'value')),
    (69, 'item_lang', 'cat', oils_i18n_gettext('69', 'Catalan', 'ccvm', 'value')),
    (70, 'item_lang', 'cau', oils_i18n_gettext('70', 'Caucasian (Other)', 'ccvm', 'value')),
    (71, 'item_lang', 'ceb', oils_i18n_gettext('71', 'Cebuano', 'ccvm', 'value')),
    (72, 'item_lang', 'cel', oils_i18n_gettext('72', 'Celtic (Other)', 'ccvm', 'value')),
    (73, 'item_lang', 'cha', oils_i18n_gettext('73', 'Chamorro', 'ccvm', 'value')),
    (74, 'item_lang', 'chb', oils_i18n_gettext('74', 'Chibcha', 'ccvm', 'value')),
    (75, 'item_lang', 'che', oils_i18n_gettext('75', 'Chechen', 'ccvm', 'value')),
    (76, 'item_lang', 'chg', oils_i18n_gettext('76', 'Chagatai', 'ccvm', 'value')),
    (77, 'item_lang', 'chi', oils_i18n_gettext('77', 'Chinese', 'ccvm', 'value')),
    (78, 'item_lang', 'chk', oils_i18n_gettext('78', 'Truk', 'ccvm', 'value')),
    (79, 'item_lang', 'chm', oils_i18n_gettext('79', 'Mari', 'ccvm', 'value')),
    (80, 'item_lang', 'chn', oils_i18n_gettext('80', 'Chinook jargon', 'ccvm', 'value')),
    (81, 'item_lang', 'cho', oils_i18n_gettext('81', 'Choctaw', 'ccvm', 'value')),
    (82, 'item_lang', 'chp', oils_i18n_gettext('82', 'Chipewyan', 'ccvm', 'value')),
    (83, 'item_lang', 'chr', oils_i18n_gettext('83', 'Cherokee', 'ccvm', 'value')),
    (84, 'item_lang', 'chu', oils_i18n_gettext('84', 'Church Slavic', 'ccvm', 'value')),
    (85, 'item_lang', 'chv', oils_i18n_gettext('85', 'Chuvash', 'ccvm', 'value')),
    (86, 'item_lang', 'chy', oils_i18n_gettext('86', 'Cheyenne', 'ccvm', 'value')),
    (87, 'item_lang', 'cmc', oils_i18n_gettext('87', 'Chamic languages', 'ccvm', 'value')),
    (88, 'item_lang', 'cop', oils_i18n_gettext('88', 'Coptic', 'ccvm', 'value')),
    (89, 'item_lang', 'cor', oils_i18n_gettext('89', 'Cornish', 'ccvm', 'value')),
    (90, 'item_lang', 'cos', oils_i18n_gettext('90', 'Corsican', 'ccvm', 'value')),
    (91, 'item_lang', 'cpe', oils_i18n_gettext('91', 'Creoles and Pidgins, English-based (Other)', 'ccvm', 'value')),
    (92, 'item_lang', 'cpf', oils_i18n_gettext('92', 'Creoles and Pidgins, French-based (Other)', 'ccvm', 'value')),
    (93, 'item_lang', 'cpp', oils_i18n_gettext('93', 'Creoles and Pidgins, Portuguese-based (Other)', 'ccvm', 'value')),
    (94, 'item_lang', 'cre', oils_i18n_gettext('94', 'Cree', 'ccvm', 'value')),
    (95, 'item_lang', 'crh', oils_i18n_gettext('95', 'Crimean Tatar', 'ccvm', 'value')),
    (96, 'item_lang', 'crp', oils_i18n_gettext('96', 'Creoles and Pidgins (Other)', 'ccvm', 'value')),
    (97, 'item_lang', 'cus', oils_i18n_gettext('97', 'Cushitic (Other)', 'ccvm', 'value')),
    (98, 'item_lang', 'cze', oils_i18n_gettext('98', 'Czech', 'ccvm', 'value')),
    (99, 'item_lang', 'dak', oils_i18n_gettext('99', 'Dakota', 'ccvm', 'value')),
    (100, 'item_lang', 'dan', oils_i18n_gettext('100', 'Danish', 'ccvm', 'value')),
    (101, 'item_lang', 'dar', oils_i18n_gettext('101', 'Dargwa', 'ccvm', 'value')),
    (102, 'item_lang', 'day', oils_i18n_gettext('102', 'Dayak', 'ccvm', 'value')),
    (103, 'item_lang', 'del', oils_i18n_gettext('103', 'Delaware', 'ccvm', 'value')),
    (104, 'item_lang', 'den', oils_i18n_gettext('104', 'Slave', 'ccvm', 'value')),
    (105, 'item_lang', 'dgr', oils_i18n_gettext('105', 'Dogrib', 'ccvm', 'value')),
    (106, 'item_lang', 'din', oils_i18n_gettext('106', 'Dinka', 'ccvm', 'value')),
    (107, 'item_lang', 'div', oils_i18n_gettext('107', 'Divehi', 'ccvm', 'value')),
    (108, 'item_lang', 'doi', oils_i18n_gettext('108', 'Dogri', 'ccvm', 'value')),
    (109, 'item_lang', 'dra', oils_i18n_gettext('109', 'Dravidian (Other)', 'ccvm', 'value')),
    (110, 'item_lang', 'dua', oils_i18n_gettext('110', 'Duala', 'ccvm', 'value')),
    (111, 'item_lang', 'dum', oils_i18n_gettext('111', 'Dutch, Middle (ca. 1050-1350)', 'ccvm', 'value')),
    (112, 'item_lang', 'dut', oils_i18n_gettext('112', 'Dutch', 'ccvm', 'value')),
    (113, 'item_lang', 'dyu', oils_i18n_gettext('113', 'Dyula', 'ccvm', 'value')),
    (114, 'item_lang', 'dzo', oils_i18n_gettext('114', 'Dzongkha', 'ccvm', 'value')),
    (115, 'item_lang', 'efi', oils_i18n_gettext('115', 'Efik', 'ccvm', 'value')),
    (116, 'item_lang', 'egy', oils_i18n_gettext('116', 'Egyptian', 'ccvm', 'value')),
    (117, 'item_lang', 'eka', oils_i18n_gettext('117', 'Ekajuk', 'ccvm', 'value')),
    (118, 'item_lang', 'elx', oils_i18n_gettext('118', 'Elamite', 'ccvm', 'value')),
    (119, 'item_lang', 'eng', oils_i18n_gettext('119', 'English', 'ccvm', 'value')),
    (120, 'item_lang', 'enm', oils_i18n_gettext('120', 'English, Middle (1100-1500)', 'ccvm', 'value')),
    (121, 'item_lang', 'epo', oils_i18n_gettext('121', 'Esperanto', 'ccvm', 'value')),
    (122, 'item_lang', '-esk', oils_i18n_gettext('122', 'Eskimo languages', 'ccvm', 'value')),
    (123, 'item_lang', '-esp', oils_i18n_gettext('123', 'Esperanto', 'ccvm', 'value')),
    (124, 'item_lang', 'est', oils_i18n_gettext('124', 'Estonian', 'ccvm', 'value')),
    (125, 'item_lang', '-eth', oils_i18n_gettext('125', 'Ethiopic', 'ccvm', 'value')),
    (126, 'item_lang', 'ewe', oils_i18n_gettext('126', 'Ewe', 'ccvm', 'value')),
    (127, 'item_lang', 'ewo', oils_i18n_gettext('127', 'Ewondo', 'ccvm', 'value')),
    (128, 'item_lang', 'fan', oils_i18n_gettext('128', 'Fang', 'ccvm', 'value')),
    (129, 'item_lang', 'fao', oils_i18n_gettext('129', 'Faroese', 'ccvm', 'value')),
    (130, 'item_lang', '-far', oils_i18n_gettext('130', 'Faroese', 'ccvm', 'value')),
    (131, 'item_lang', 'fat', oils_i18n_gettext('131', 'Fanti', 'ccvm', 'value')),
    (132, 'item_lang', 'fij', oils_i18n_gettext('132', 'Fijian', 'ccvm', 'value')),
    (133, 'item_lang', 'fin', oils_i18n_gettext('133', 'Finnish', 'ccvm', 'value')),
    (134, 'item_lang', 'fiu', oils_i18n_gettext('134', 'Finno-Ugrian (Other)', 'ccvm', 'value')),
    (135, 'item_lang', 'fon', oils_i18n_gettext('135', 'Fon', 'ccvm', 'value')),
    (136, 'item_lang', 'fre', oils_i18n_gettext('136', 'French', 'ccvm', 'value')),
    (137, 'item_lang', '-fri', oils_i18n_gettext('137', 'Frisian', 'ccvm', 'value')),
    (138, 'item_lang', 'frm', oils_i18n_gettext('138', 'French, Middle (ca. 1400-1600)', 'ccvm', 'value')),
    (139, 'item_lang', 'fro', oils_i18n_gettext('139', 'French, Old (ca. 842-1400)', 'ccvm', 'value')),
    (140, 'item_lang', 'fry', oils_i18n_gettext('140', 'Frisian', 'ccvm', 'value')),
    (141, 'item_lang', 'ful', oils_i18n_gettext('141', 'Fula', 'ccvm', 'value')),
    (142, 'item_lang', 'fur', oils_i18n_gettext('142', 'Friulian', 'ccvm', 'value')),
    (143, 'item_lang', 'gaa', oils_i18n_gettext('143', 'Gã', 'ccvm', 'value')),
    (144, 'item_lang', '-gae', oils_i18n_gettext('144', 'Scottish Gaelic', 'ccvm', 'value')),
    (145, 'item_lang', '-gag', oils_i18n_gettext('145', 'Galician', 'ccvm', 'value')),
    (146, 'item_lang', '-gal', oils_i18n_gettext('146', 'Oromo', 'ccvm', 'value')),
    (147, 'item_lang', 'gay', oils_i18n_gettext('147', 'Gayo', 'ccvm', 'value')),
    (148, 'item_lang', 'gba', oils_i18n_gettext('148', 'Gbaya', 'ccvm', 'value')),
    (149, 'item_lang', 'gem', oils_i18n_gettext('149', 'Germanic (Other)', 'ccvm', 'value')),
    (150, 'item_lang', 'geo', oils_i18n_gettext('150', 'Georgian', 'ccvm', 'value')),
    (151, 'item_lang', 'ger', oils_i18n_gettext('151', 'German', 'ccvm', 'value')),
    (152, 'item_lang', 'gez', oils_i18n_gettext('152', 'Ethiopic', 'ccvm', 'value')),
    (153, 'item_lang', 'gil', oils_i18n_gettext('153', 'Gilbertese', 'ccvm', 'value')),
    (154, 'item_lang', 'gla', oils_i18n_gettext('154', 'Scottish Gaelic', 'ccvm', 'value')),
    (155, 'item_lang', 'gle', oils_i18n_gettext('155', 'Irish', 'ccvm', 'value')),
    (156, 'item_lang', 'glg', oils_i18n_gettext('156', 'Galician', 'ccvm', 'value')),
    (157, 'item_lang', 'glv', oils_i18n_gettext('157', 'Manx', 'ccvm', 'value')),
    (158, 'item_lang', 'gmh', oils_i18n_gettext('158', 'German, Middle High (ca. 1050-1500)', 'ccvm', 'value')),
    (159, 'item_lang', 'goh', oils_i18n_gettext('159', 'German, Old High (ca. 750-1050)', 'ccvm', 'value')),
    (160, 'item_lang', 'gon', oils_i18n_gettext('160', 'Gondi', 'ccvm', 'value')),
    (161, 'item_lang', 'gor', oils_i18n_gettext('161', 'Gorontalo', 'ccvm', 'value')),
    (162, 'item_lang', 'got', oils_i18n_gettext('162', 'Gothic', 'ccvm', 'value')),
    (163, 'item_lang', 'grb', oils_i18n_gettext('163', 'Grebo', 'ccvm', 'value')),
    (164, 'item_lang', 'grc', oils_i18n_gettext('164', 'Greek, Ancient (to 1453)', 'ccvm', 'value')),
    (165, 'item_lang', 'gre', oils_i18n_gettext('165', 'Greek, Modern (1453- )', 'ccvm', 'value')),
    (166, 'item_lang', 'grn', oils_i18n_gettext('166', 'Guarani', 'ccvm', 'value')),
    (167, 'item_lang', '-gua', oils_i18n_gettext('167', 'Guarani', 'ccvm', 'value')),
    (168, 'item_lang', 'guj', oils_i18n_gettext('168', 'Gujarati', 'ccvm', 'value')),
    (169, 'item_lang', 'gwi', oils_i18n_gettext('169', 'Gwich''in', 'ccvm', 'value')),
    (170, 'item_lang', 'hai', oils_i18n_gettext('170', 'Haida', 'ccvm', 'value')),
    (171, 'item_lang', 'hat', oils_i18n_gettext('171', 'Haitian French Creole', 'ccvm', 'value')),
    (172, 'item_lang', 'hau', oils_i18n_gettext('172', 'Hausa', 'ccvm', 'value')),
    (173, 'item_lang', 'haw', oils_i18n_gettext('173', 'Hawaiian', 'ccvm', 'value')),
    (174, 'item_lang', 'heb', oils_i18n_gettext('174', 'Hebrew', 'ccvm', 'value')),
    (175, 'item_lang', 'her', oils_i18n_gettext('175', 'Herero', 'ccvm', 'value')),
    (176, 'item_lang', 'hil', oils_i18n_gettext('176', 'Hiligaynon', 'ccvm', 'value')),
    (177, 'item_lang', 'him', oils_i18n_gettext('177', 'Himachali', 'ccvm', 'value')),
    (178, 'item_lang', 'hin', oils_i18n_gettext('178', 'Hindi', 'ccvm', 'value')),
    (179, 'item_lang', 'hit', oils_i18n_gettext('179', 'Hittite', 'ccvm', 'value')),
    (180, 'item_lang', 'hmn', oils_i18n_gettext('180', 'Hmong', 'ccvm', 'value')),
    (181, 'item_lang', 'hmo', oils_i18n_gettext('181', 'Hiri Motu', 'ccvm', 'value')),
    (182, 'item_lang', 'hun', oils_i18n_gettext('182', 'Hungarian', 'ccvm', 'value')),
    (183, 'item_lang', 'hup', oils_i18n_gettext('183', 'Hupa', 'ccvm', 'value')),
    (184, 'item_lang', 'iba', oils_i18n_gettext('184', 'Iban', 'ccvm', 'value')),
    (185, 'item_lang', 'ibo', oils_i18n_gettext('185', 'Igbo', 'ccvm', 'value')),
    (186, 'item_lang', 'ice', oils_i18n_gettext('186', 'Icelandic', 'ccvm', 'value')),
    (187, 'item_lang', 'ido', oils_i18n_gettext('187', 'Ido', 'ccvm', 'value')),
    (188, 'item_lang', 'iii', oils_i18n_gettext('188', 'Sichuan Yi', 'ccvm', 'value')),
    (189, 'item_lang', 'ijo', oils_i18n_gettext('189', 'Ijo', 'ccvm', 'value')),
    (190, 'item_lang', 'iku', oils_i18n_gettext('190', 'Inuktitut', 'ccvm', 'value')),
    (191, 'item_lang', 'ile', oils_i18n_gettext('191', 'Interlingue', 'ccvm', 'value')),
    (192, 'item_lang', 'ilo', oils_i18n_gettext('192', 'Iloko', 'ccvm', 'value')),
    (193, 'item_lang', 'ina', oils_i18n_gettext('193', 'Interlingua (International Auxiliary Language Association)', 'ccvm', 'value')),
    (194, 'item_lang', 'inc', oils_i18n_gettext('194', 'Indic (Other)', 'ccvm', 'value')),
    (195, 'item_lang', 'ind', oils_i18n_gettext('195', 'Indonesian', 'ccvm', 'value')),
    (196, 'item_lang', 'ine', oils_i18n_gettext('196', 'Indo-European (Other)', 'ccvm', 'value')),
    (197, 'item_lang', 'inh', oils_i18n_gettext('197', 'Ingush', 'ccvm', 'value')),
    (198, 'item_lang', '-int', oils_i18n_gettext('198', 'Interlingua (International Auxiliary Language Association)', 'ccvm', 'value')),
    (199, 'item_lang', 'ipk', oils_i18n_gettext('199', 'Inupiaq', 'ccvm', 'value')),
    (200, 'item_lang', 'ira', oils_i18n_gettext('200', 'Iranian (Other)', 'ccvm', 'value')),
    (201, 'item_lang', '-iri', oils_i18n_gettext('201', 'Irish', 'ccvm', 'value')),
    (202, 'item_lang', 'iro', oils_i18n_gettext('202', 'Iroquoian (Other)', 'ccvm', 'value')),
    (203, 'item_lang', 'ita', oils_i18n_gettext('203', 'Italian', 'ccvm', 'value')),
    (204, 'item_lang', 'jav', oils_i18n_gettext('204', 'Javanese', 'ccvm', 'value')),
    (205, 'item_lang', 'jpn', oils_i18n_gettext('205', 'Japanese', 'ccvm', 'value')),
    (206, 'item_lang', 'jpr', oils_i18n_gettext('206', 'Judeo-Persian', 'ccvm', 'value')),
    (207, 'item_lang', 'jrb', oils_i18n_gettext('207', 'Judeo-Arabic', 'ccvm', 'value')),
    (208, 'item_lang', 'kaa', oils_i18n_gettext('208', 'Kara-Kalpak', 'ccvm', 'value')),
    (209, 'item_lang', 'kab', oils_i18n_gettext('209', 'Kabyle', 'ccvm', 'value')),
    (210, 'item_lang', 'kac', oils_i18n_gettext('210', 'Kachin', 'ccvm', 'value')),
    (211, 'item_lang', 'kal', oils_i18n_gettext('211', 'Kalâtdlisut', 'ccvm', 'value')),
    (212, 'item_lang', 'kam', oils_i18n_gettext('212', 'Kamba', 'ccvm', 'value')),
    (213, 'item_lang', 'kan', oils_i18n_gettext('213', 'Kannada', 'ccvm', 'value')),
    (214, 'item_lang', 'kar', oils_i18n_gettext('214', 'Karen', 'ccvm', 'value')),
    (215, 'item_lang', 'kas', oils_i18n_gettext('215', 'Kashmiri', 'ccvm', 'value')),
    (216, 'item_lang', 'kau', oils_i18n_gettext('216', 'Kanuri', 'ccvm', 'value')),
    (217, 'item_lang', 'kaw', oils_i18n_gettext('217', 'Kawi', 'ccvm', 'value')),
    (218, 'item_lang', 'kaz', oils_i18n_gettext('218', 'Kazakh', 'ccvm', 'value')),
    (219, 'item_lang', 'kbd', oils_i18n_gettext('219', 'Kabardian', 'ccvm', 'value')),
    (220, 'item_lang', 'kha', oils_i18n_gettext('220', 'Khasi', 'ccvm', 'value')),
    (221, 'item_lang', 'khi', oils_i18n_gettext('221', 'Khoisan (Other)', 'ccvm', 'value')),
    (222, 'item_lang', 'khm', oils_i18n_gettext('222', 'Khmer', 'ccvm', 'value')),
    (223, 'item_lang', 'kho', oils_i18n_gettext('223', 'Khotanese', 'ccvm', 'value')),
    (224, 'item_lang', 'kik', oils_i18n_gettext('224', 'Kikuyu', 'ccvm', 'value')),
    (225, 'item_lang', 'kin', oils_i18n_gettext('225', 'Kinyarwanda', 'ccvm', 'value')),
    (226, 'item_lang', 'kir', oils_i18n_gettext('226', 'Kyrgyz', 'ccvm', 'value')),
    (227, 'item_lang', 'kmb', oils_i18n_gettext('227', 'Kimbundu', 'ccvm', 'value')),
    (228, 'item_lang', 'kok', oils_i18n_gettext('228', 'Konkani', 'ccvm', 'value')),
    (229, 'item_lang', 'kom', oils_i18n_gettext('229', 'Komi', 'ccvm', 'value')),
    (230, 'item_lang', 'kon', oils_i18n_gettext('230', 'Kongo', 'ccvm', 'value')),
    (231, 'item_lang', 'kor', oils_i18n_gettext('231', 'Korean', 'ccvm', 'value')),
    (232, 'item_lang', 'kos', oils_i18n_gettext('232', 'Kusaie', 'ccvm', 'value')),
    (233, 'item_lang', 'kpe', oils_i18n_gettext('233', 'Kpelle', 'ccvm', 'value')),
    (234, 'item_lang', 'kro', oils_i18n_gettext('234', 'Kru', 'ccvm', 'value')),
    (235, 'item_lang', 'kru', oils_i18n_gettext('235', 'Kurukh', 'ccvm', 'value')),
    (236, 'item_lang', 'kua', oils_i18n_gettext('236', 'Kuanyama', 'ccvm', 'value')),
    (237, 'item_lang', 'kum', oils_i18n_gettext('237', 'Kumyk', 'ccvm', 'value')),
    (238, 'item_lang', 'kur', oils_i18n_gettext('238', 'Kurdish', 'ccvm', 'value')),
    (239, 'item_lang', '-kus', oils_i18n_gettext('239', 'Kusaie', 'ccvm', 'value')),
    (240, 'item_lang', 'kut', oils_i18n_gettext('240', 'Kutenai', 'ccvm', 'value')),
    (241, 'item_lang', 'lad', oils_i18n_gettext('241', 'Ladino', 'ccvm', 'value')),
    (242, 'item_lang', 'lah', oils_i18n_gettext('242', 'Lahnda', 'ccvm', 'value')),
    (243, 'item_lang', 'lam', oils_i18n_gettext('243', 'Lamba', 'ccvm', 'value')),
    (244, 'item_lang', '-lan', oils_i18n_gettext('244', 'Occitan (post-1500)', 'ccvm', 'value')),
    (245, 'item_lang', 'lao', oils_i18n_gettext('245', 'Lao', 'ccvm', 'value')),
    (246, 'item_lang', '-lap', oils_i18n_gettext('246', 'Sami', 'ccvm', 'value')),
    (247, 'item_lang', 'lat', oils_i18n_gettext('247', 'Latin', 'ccvm', 'value')),
    (248, 'item_lang', 'lav', oils_i18n_gettext('248', 'Latvian', 'ccvm', 'value')),
    (249, 'item_lang', 'lez', oils_i18n_gettext('249', 'Lezgian', 'ccvm', 'value')),
    (250, 'item_lang', 'lim', oils_i18n_gettext('250', 'Limburgish', 'ccvm', 'value')),
    (251, 'item_lang', 'lin', oils_i18n_gettext('251', 'Lingala', 'ccvm', 'value')),
    (252, 'item_lang', 'lit', oils_i18n_gettext('252', 'Lithuanian', 'ccvm', 'value')),
    (253, 'item_lang', 'lol', oils_i18n_gettext('253', 'Mongo-Nkundu', 'ccvm', 'value')),
    (254, 'item_lang', 'loz', oils_i18n_gettext('254', 'Lozi', 'ccvm', 'value')),
    (255, 'item_lang', 'ltz', oils_i18n_gettext('255', 'Letzeburgesch', 'ccvm', 'value')),
    (256, 'item_lang', 'lua', oils_i18n_gettext('256', 'Luba-Lulua', 'ccvm', 'value')),
    (257, 'item_lang', 'lub', oils_i18n_gettext('257', 'Luba-Katanga', 'ccvm', 'value')),
    (258, 'item_lang', 'lug', oils_i18n_gettext('258', 'Ganda', 'ccvm', 'value')),
    (259, 'item_lang', 'lui', oils_i18n_gettext('259', 'Luiseño', 'ccvm', 'value')),
    (260, 'item_lang', 'lun', oils_i18n_gettext('260', 'Lunda', 'ccvm', 'value')),
    (261, 'item_lang', 'luo', oils_i18n_gettext('261', 'Luo (Kenya and Tanzania)', 'ccvm', 'value')),
    (262, 'item_lang', 'lus', oils_i18n_gettext('262', 'Lushai', 'ccvm', 'value')),
    (263, 'item_lang', 'mac', oils_i18n_gettext('263', 'Macedonian', 'ccvm', 'value')),
    (264, 'item_lang', 'mad', oils_i18n_gettext('264', 'Madurese', 'ccvm', 'value')),
    (265, 'item_lang', 'mag', oils_i18n_gettext('265', 'Magahi', 'ccvm', 'value')),
    (266, 'item_lang', 'mah', oils_i18n_gettext('266', 'Marshallese', 'ccvm', 'value')),
    (267, 'item_lang', 'mai', oils_i18n_gettext('267', 'Maithili', 'ccvm', 'value')),
    (268, 'item_lang', 'mak', oils_i18n_gettext('268', 'Makasar', 'ccvm', 'value')),
    (269, 'item_lang', 'mal', oils_i18n_gettext('269', 'Malayalam', 'ccvm', 'value')),
    (270, 'item_lang', 'man', oils_i18n_gettext('270', 'Mandingo', 'ccvm', 'value')),
    (271, 'item_lang', 'mao', oils_i18n_gettext('271', 'Maori', 'ccvm', 'value')),
    (272, 'item_lang', 'map', oils_i18n_gettext('272', 'Austronesian (Other)', 'ccvm', 'value')),
    (273, 'item_lang', 'mar', oils_i18n_gettext('273', 'Marathi', 'ccvm', 'value')),
    (274, 'item_lang', 'mas', oils_i18n_gettext('274', 'Masai', 'ccvm', 'value')),
    (275, 'item_lang', '-max', oils_i18n_gettext('275', 'Manx', 'ccvm', 'value')),
    (276, 'item_lang', 'may', oils_i18n_gettext('276', 'Malay', 'ccvm', 'value')),
    (277, 'item_lang', 'mdr', oils_i18n_gettext('277', 'Mandar', 'ccvm', 'value')),
    (278, 'item_lang', 'men', oils_i18n_gettext('278', 'Mende', 'ccvm', 'value')),
    (279, 'item_lang', 'mga', oils_i18n_gettext('279', 'Irish, Middle (ca. 1100-1550)', 'ccvm', 'value')),
    (280, 'item_lang', 'mic', oils_i18n_gettext('280', 'Micmac', 'ccvm', 'value')),
    (281, 'item_lang', 'min', oils_i18n_gettext('281', 'Minangkabau', 'ccvm', 'value')),
    (282, 'item_lang', 'mis', oils_i18n_gettext('282', 'Miscellaneous languages', 'ccvm', 'value')),
    (283, 'item_lang', 'mkh', oils_i18n_gettext('283', 'Mon-Khmer (Other)', 'ccvm', 'value')),
    (284, 'item_lang', '-mla', oils_i18n_gettext('284', 'Malagasy', 'ccvm', 'value')),
    (285, 'item_lang', 'mlg', oils_i18n_gettext('285', 'Malagasy', 'ccvm', 'value')),
    (286, 'item_lang', 'mlt', oils_i18n_gettext('286', 'Maltese', 'ccvm', 'value')),
    (287, 'item_lang', 'mnc', oils_i18n_gettext('287', 'Manchu', 'ccvm', 'value')),
    (288, 'item_lang', 'mni', oils_i18n_gettext('288', 'Manipuri', 'ccvm', 'value')),
    (289, 'item_lang', 'mno', oils_i18n_gettext('289', 'Manobo languages', 'ccvm', 'value')),
    (290, 'item_lang', 'moh', oils_i18n_gettext('290', 'Mohawk', 'ccvm', 'value')),
    (291, 'item_lang', 'mol', oils_i18n_gettext('291', 'Moldavian', 'ccvm', 'value')),
    (292, 'item_lang', 'mon', oils_i18n_gettext('292', 'Mongolian', 'ccvm', 'value')),
    (293, 'item_lang', 'mos', oils_i18n_gettext('293', 'Mooré', 'ccvm', 'value')),
    (294, 'item_lang', 'mul', oils_i18n_gettext('294', 'Multiple languages', 'ccvm', 'value')),
    (295, 'item_lang', 'mun', oils_i18n_gettext('295', 'Munda (Other)', 'ccvm', 'value')),
    (296, 'item_lang', 'mus', oils_i18n_gettext('296', 'Creek', 'ccvm', 'value')),
    (297, 'item_lang', 'mwr', oils_i18n_gettext('297', 'Marwari', 'ccvm', 'value')),
    (298, 'item_lang', 'myn', oils_i18n_gettext('298', 'Mayan languages', 'ccvm', 'value')),
    (299, 'item_lang', 'nah', oils_i18n_gettext('299', 'Nahuatl', 'ccvm', 'value')),
    (300, 'item_lang', 'nai', oils_i18n_gettext('300', 'North American Indian (Other)', 'ccvm', 'value')),
    (301, 'item_lang', 'nap', oils_i18n_gettext('301', 'Neapolitan Italian', 'ccvm', 'value')),
    (302, 'item_lang', 'nau', oils_i18n_gettext('302', 'Nauru', 'ccvm', 'value')),
    (303, 'item_lang', 'nav', oils_i18n_gettext('303', 'Navajo', 'ccvm', 'value')),
    (304, 'item_lang', 'nbl', oils_i18n_gettext('304', 'Ndebele (South Africa)', 'ccvm', 'value')),
    (305, 'item_lang', 'nde', oils_i18n_gettext('305', 'Ndebele (Zimbabwe)  ', 'ccvm', 'value')),
    (306, 'item_lang', 'ndo', oils_i18n_gettext('306', 'Ndonga', 'ccvm', 'value')),
    (307, 'item_lang', 'nds', oils_i18n_gettext('307', 'Low German', 'ccvm', 'value')),
    (308, 'item_lang', 'nep', oils_i18n_gettext('308', 'Nepali', 'ccvm', 'value')),
    (309, 'item_lang', 'new', oils_i18n_gettext('309', 'Newari', 'ccvm', 'value')),
    (310, 'item_lang', 'nia', oils_i18n_gettext('310', 'Nias', 'ccvm', 'value')),
    (311, 'item_lang', 'nic', oils_i18n_gettext('311', 'Niger-Kordofanian (Other)', 'ccvm', 'value')),
    (312, 'item_lang', 'niu', oils_i18n_gettext('312', 'Niuean', 'ccvm', 'value')),
    (313, 'item_lang', 'nno', oils_i18n_gettext('313', 'Norwegian (Nynorsk)', 'ccvm', 'value')),
    (314, 'item_lang', 'nob', oils_i18n_gettext('314', 'Norwegian (Bokmål)', 'ccvm', 'value')),
    (315, 'item_lang', 'nog', oils_i18n_gettext('315', 'Nogai', 'ccvm', 'value')),
    (316, 'item_lang', 'non', oils_i18n_gettext('316', 'Old Norse', 'ccvm', 'value')),
    (317, 'item_lang', 'nor', oils_i18n_gettext('317', 'Norwegian', 'ccvm', 'value')),
    (318, 'item_lang', 'nso', oils_i18n_gettext('318', 'Northern Sotho', 'ccvm', 'value')),
    (319, 'item_lang', 'nub', oils_i18n_gettext('319', 'Nubian languages', 'ccvm', 'value')),
    (320, 'item_lang', 'nya', oils_i18n_gettext('320', 'Nyanja', 'ccvm', 'value')),
    (321, 'item_lang', 'nym', oils_i18n_gettext('321', 'Nyamwezi', 'ccvm', 'value')),
    (322, 'item_lang', 'nyn', oils_i18n_gettext('322', 'Nyankole', 'ccvm', 'value')),
    (323, 'item_lang', 'nyo', oils_i18n_gettext('323', 'Nyoro', 'ccvm', 'value')),
    (324, 'item_lang', 'nzi', oils_i18n_gettext('324', 'Nzima', 'ccvm', 'value')),
    (325, 'item_lang', 'oci', oils_i18n_gettext('325', 'Occitan (post-1500)', 'ccvm', 'value')),
    (326, 'item_lang', 'oji', oils_i18n_gettext('326', 'Ojibwa', 'ccvm', 'value')),
    (327, 'item_lang', 'ori', oils_i18n_gettext('327', 'Oriya', 'ccvm', 'value')),
    (328, 'item_lang', 'orm', oils_i18n_gettext('328', 'Oromo', 'ccvm', 'value')),
    (329, 'item_lang', 'osa', oils_i18n_gettext('329', 'Osage', 'ccvm', 'value')),
    (330, 'item_lang', 'oss', oils_i18n_gettext('330', 'Ossetic', 'ccvm', 'value')),
    (331, 'item_lang', 'ota', oils_i18n_gettext('331', 'Turkish, Ottoman', 'ccvm', 'value')),
    (332, 'item_lang', 'oto', oils_i18n_gettext('332', 'Otomian languages', 'ccvm', 'value')),
    (333, 'item_lang', 'paa', oils_i18n_gettext('333', 'Papuan (Other)', 'ccvm', 'value')),
    (334, 'item_lang', 'pag', oils_i18n_gettext('334', 'Pangasinan', 'ccvm', 'value')),
    (335, 'item_lang', 'pal', oils_i18n_gettext('335', 'Pahlavi', 'ccvm', 'value')),
    (336, 'item_lang', 'pam', oils_i18n_gettext('336', 'Pampanga', 'ccvm', 'value')),
    (337, 'item_lang', 'pan', oils_i18n_gettext('337', 'Panjabi', 'ccvm', 'value')),
    (338, 'item_lang', 'pap', oils_i18n_gettext('338', 'Papiamento', 'ccvm', 'value')),
    (339, 'item_lang', 'pau', oils_i18n_gettext('339', 'Palauan', 'ccvm', 'value')),
    (340, 'item_lang', 'peo', oils_i18n_gettext('340', 'Old Persian (ca. 600-400 B.C.)', 'ccvm', 'value')),
    (341, 'item_lang', 'per', oils_i18n_gettext('341', 'Persian', 'ccvm', 'value')),
    (342, 'item_lang', 'phi', oils_i18n_gettext('342', 'Philippine (Other)', 'ccvm', 'value')),
    (343, 'item_lang', 'phn', oils_i18n_gettext('343', 'Phoenician', 'ccvm', 'value')),
    (344, 'item_lang', 'pli', oils_i18n_gettext('344', 'Pali', 'ccvm', 'value')),
    (345, 'item_lang', 'pol', oils_i18n_gettext('345', 'Polish', 'ccvm', 'value')),
    (346, 'item_lang', 'pon', oils_i18n_gettext('346', 'Ponape', 'ccvm', 'value')),
    (347, 'item_lang', 'por', oils_i18n_gettext('347', 'Portuguese', 'ccvm', 'value')),
    (348, 'item_lang', 'pra', oils_i18n_gettext('348', 'Prakrit languages', 'ccvm', 'value')),
    (349, 'item_lang', 'pro', oils_i18n_gettext('349', 'Provençal (to 1500)', 'ccvm', 'value')),
    (350, 'item_lang', 'pus', oils_i18n_gettext('350', 'Pushto', 'ccvm', 'value')),
    (351, 'item_lang', 'que', oils_i18n_gettext('351', 'Quechua', 'ccvm', 'value')),
    (352, 'item_lang', 'raj', oils_i18n_gettext('352', 'Rajasthani', 'ccvm', 'value')),
    (353, 'item_lang', 'rap', oils_i18n_gettext('353', 'Rapanui', 'ccvm', 'value')),
    (354, 'item_lang', 'rar', oils_i18n_gettext('354', 'Rarotongan', 'ccvm', 'value')),
    (355, 'item_lang', 'roa', oils_i18n_gettext('355', 'Romance (Other)', 'ccvm', 'value')),
    (356, 'item_lang', 'roh', oils_i18n_gettext('356', 'Raeto-Romance', 'ccvm', 'value')),
    (357, 'item_lang', 'rom', oils_i18n_gettext('357', 'Romani', 'ccvm', 'value')),
    (358, 'item_lang', 'rum', oils_i18n_gettext('358', 'Romanian', 'ccvm', 'value')),
    (359, 'item_lang', 'run', oils_i18n_gettext('359', 'Rundi', 'ccvm', 'value')),
    (360, 'item_lang', 'rus', oils_i18n_gettext('360', 'Russian', 'ccvm', 'value')),
    (361, 'item_lang', 'sad', oils_i18n_gettext('361', 'Sandawe', 'ccvm', 'value')),
    (362, 'item_lang', 'sag', oils_i18n_gettext('362', 'Sango (Ubangi Creole)', 'ccvm', 'value')),
    (363, 'item_lang', 'sah', oils_i18n_gettext('363', 'Yakut', 'ccvm', 'value')),
    (364, 'item_lang', 'sai', oils_i18n_gettext('364', 'South American Indian (Other)', 'ccvm', 'value')),
    (365, 'item_lang', 'sal', oils_i18n_gettext('365', 'Salishan languages', 'ccvm', 'value')),
    (366, 'item_lang', 'sam', oils_i18n_gettext('366', 'Samaritan Aramaic', 'ccvm', 'value')),
    (367, 'item_lang', 'san', oils_i18n_gettext('367', 'Sanskrit', 'ccvm', 'value')),
    (368, 'item_lang', '-sao', oils_i18n_gettext('368', 'Samoan', 'ccvm', 'value')),
    (369, 'item_lang', 'sas', oils_i18n_gettext('369', 'Sasak', 'ccvm', 'value')),
    (370, 'item_lang', 'sat', oils_i18n_gettext('370', 'Santali', 'ccvm', 'value')),
    (371, 'item_lang', 'scc', oils_i18n_gettext('371', 'Serbian', 'ccvm', 'value')),
    (372, 'item_lang', 'sco', oils_i18n_gettext('372', 'Scots', 'ccvm', 'value')),
    (373, 'item_lang', 'scr', oils_i18n_gettext('373', 'Croatian', 'ccvm', 'value')),
    (374, 'item_lang', 'sel', oils_i18n_gettext('374', 'Selkup', 'ccvm', 'value')),
    (375, 'item_lang', 'sem', oils_i18n_gettext('375', 'Semitic (Other)', 'ccvm', 'value')),
    (376, 'item_lang', 'sga', oils_i18n_gettext('376', 'Irish, Old (to 1100)', 'ccvm', 'value')),
    (377, 'item_lang', 'sgn', oils_i18n_gettext('377', 'Sign languages', 'ccvm', 'value')),
    (378, 'item_lang', 'shn', oils_i18n_gettext('378', 'Shan', 'ccvm', 'value')),
    (379, 'item_lang', '-sho', oils_i18n_gettext('379', 'Shona', 'ccvm', 'value')),
    (380, 'item_lang', 'sid', oils_i18n_gettext('380', 'Sidamo', 'ccvm', 'value')),
    (381, 'item_lang', 'sin', oils_i18n_gettext('381', 'Sinhalese', 'ccvm', 'value')),
    (382, 'item_lang', 'sio', oils_i18n_gettext('382', 'Siouan (Other)', 'ccvm', 'value')),
    (383, 'item_lang', 'sit', oils_i18n_gettext('383', 'Sino-Tibetan (Other)', 'ccvm', 'value')),
    (384, 'item_lang', 'sla', oils_i18n_gettext('384', 'Slavic (Other)', 'ccvm', 'value')),
    (385, 'item_lang', 'slo', oils_i18n_gettext('385', 'Slovak', 'ccvm', 'value')),
    (386, 'item_lang', 'slv', oils_i18n_gettext('386', 'Slovenian', 'ccvm', 'value')),
    (387, 'item_lang', 'sma', oils_i18n_gettext('387', 'Southern Sami', 'ccvm', 'value')),
    (388, 'item_lang', 'sme', oils_i18n_gettext('388', 'Northern Sami', 'ccvm', 'value')),
    (389, 'item_lang', 'smi', oils_i18n_gettext('389', 'Sami', 'ccvm', 'value')),
    (390, 'item_lang', 'smj', oils_i18n_gettext('390', 'Lule Sami', 'ccvm', 'value')),
    (391, 'item_lang', 'smn', oils_i18n_gettext('391', 'Inari Sami', 'ccvm', 'value')),
    (392, 'item_lang', 'smo', oils_i18n_gettext('392', 'Samoan', 'ccvm', 'value')),
    (393, 'item_lang', 'sms', oils_i18n_gettext('393', 'Skolt Sami', 'ccvm', 'value')),
    (394, 'item_lang', 'sna', oils_i18n_gettext('394', 'Shona', 'ccvm', 'value')),
    (395, 'item_lang', 'snd', oils_i18n_gettext('395', 'Sindhi', 'ccvm', 'value')),
    (396, 'item_lang', '-snh', oils_i18n_gettext('396', 'Sinhalese', 'ccvm', 'value')),
    (397, 'item_lang', 'snk', oils_i18n_gettext('397', 'Soninke', 'ccvm', 'value')),
    (398, 'item_lang', 'sog', oils_i18n_gettext('398', 'Sogdian', 'ccvm', 'value')),
    (399, 'item_lang', 'som', oils_i18n_gettext('399', 'Somali', 'ccvm', 'value')),
    (400, 'item_lang', 'son', oils_i18n_gettext('400', 'Songhai', 'ccvm', 'value')),
    (401, 'item_lang', 'sot', oils_i18n_gettext('401', 'Sotho', 'ccvm', 'value')),
    (402, 'item_lang', 'spa', oils_i18n_gettext('402', 'Spanish', 'ccvm', 'value')),
    (403, 'item_lang', 'srd', oils_i18n_gettext('403', 'Sardinian', 'ccvm', 'value')),
    (404, 'item_lang', 'srr', oils_i18n_gettext('404', 'Serer', 'ccvm', 'value')),
    (405, 'item_lang', 'ssa', oils_i18n_gettext('405', 'Nilo-Saharan (Other)', 'ccvm', 'value')),
    (406, 'item_lang', '-sso', oils_i18n_gettext('406', 'Sotho', 'ccvm', 'value')),
    (407, 'item_lang', 'ssw', oils_i18n_gettext('407', 'Swazi', 'ccvm', 'value')),
    (408, 'item_lang', 'suk', oils_i18n_gettext('408', 'Sukuma', 'ccvm', 'value')),
    (409, 'item_lang', 'sun', oils_i18n_gettext('409', 'Sundanese', 'ccvm', 'value')),
    (410, 'item_lang', 'sus', oils_i18n_gettext('410', 'Susu', 'ccvm', 'value')),
    (411, 'item_lang', 'sux', oils_i18n_gettext('411', 'Sumerian', 'ccvm', 'value')),
    (412, 'item_lang', 'swa', oils_i18n_gettext('412', 'Swahili', 'ccvm', 'value')),
    (413, 'item_lang', 'swe', oils_i18n_gettext('413', 'Swedish', 'ccvm', 'value')),
    (414, 'item_lang', '-swz', oils_i18n_gettext('414', 'Swazi', 'ccvm', 'value')),
    (415, 'item_lang', 'syr', oils_i18n_gettext('415', 'Syriac', 'ccvm', 'value')),
    (416, 'item_lang', '-tag', oils_i18n_gettext('416', 'Tagalog', 'ccvm', 'value')),
    (417, 'item_lang', 'tah', oils_i18n_gettext('417', 'Tahitian', 'ccvm', 'value')),
    (418, 'item_lang', 'tai', oils_i18n_gettext('418', 'Tai (Other)', 'ccvm', 'value')),
    (419, 'item_lang', '-taj', oils_i18n_gettext('419', 'Tajik', 'ccvm', 'value')),
    (420, 'item_lang', 'tam', oils_i18n_gettext('420', 'Tamil', 'ccvm', 'value')),
    (421, 'item_lang', '-tar', oils_i18n_gettext('421', 'Tatar', 'ccvm', 'value')),
    (422, 'item_lang', 'tat', oils_i18n_gettext('422', 'Tatar', 'ccvm', 'value')),
    (423, 'item_lang', 'tel', oils_i18n_gettext('423', 'Telugu', 'ccvm', 'value')),
    (424, 'item_lang', 'tem', oils_i18n_gettext('424', 'Temne', 'ccvm', 'value')),
    (425, 'item_lang', 'ter', oils_i18n_gettext('425', 'Terena', 'ccvm', 'value')),
    (426, 'item_lang', 'tet', oils_i18n_gettext('426', 'Tetum', 'ccvm', 'value')),
    (427, 'item_lang', 'tgk', oils_i18n_gettext('427', 'Tajik', 'ccvm', 'value')),
    (428, 'item_lang', 'tgl', oils_i18n_gettext('428', 'Tagalog', 'ccvm', 'value')),
    (429, 'item_lang', 'tha', oils_i18n_gettext('429', 'Thai', 'ccvm', 'value')),
    (430, 'item_lang', 'tib', oils_i18n_gettext('430', 'Tibetan', 'ccvm', 'value')),
    (431, 'item_lang', 'tig', oils_i18n_gettext('431', 'Tigré', 'ccvm', 'value')),
    (432, 'item_lang', 'tir', oils_i18n_gettext('432', 'Tigrinya', 'ccvm', 'value')),
    (433, 'item_lang', 'tiv', oils_i18n_gettext('433', 'Tiv', 'ccvm', 'value')),
    (434, 'item_lang', 'tkl', oils_i18n_gettext('434', 'Tokelauan', 'ccvm', 'value')),
    (435, 'item_lang', 'tli', oils_i18n_gettext('435', 'Tlingit', 'ccvm', 'value')),
    (436, 'item_lang', 'tmh', oils_i18n_gettext('436', 'Tamashek', 'ccvm', 'value')),
    (437, 'item_lang', 'tog', oils_i18n_gettext('437', 'Tonga (Nyasa)', 'ccvm', 'value')),
    (438, 'item_lang', 'ton', oils_i18n_gettext('438', 'Tongan', 'ccvm', 'value')),
    (439, 'item_lang', 'tpi', oils_i18n_gettext('439', 'Tok Pisin', 'ccvm', 'value')),
    (440, 'item_lang', '-tru', oils_i18n_gettext('440', 'Truk', 'ccvm', 'value')),
    (441, 'item_lang', 'tsi', oils_i18n_gettext('441', 'Tsimshian', 'ccvm', 'value')),
    (442, 'item_lang', 'tsn', oils_i18n_gettext('442', 'Tswana', 'ccvm', 'value')),
    (443, 'item_lang', 'tso', oils_i18n_gettext('443', 'Tsonga', 'ccvm', 'value')),
    (444, 'item_lang', '-tsw', oils_i18n_gettext('444', 'Tswana', 'ccvm', 'value')),
    (445, 'item_lang', 'tuk', oils_i18n_gettext('445', 'Turkmen', 'ccvm', 'value')),
    (446, 'item_lang', 'tum', oils_i18n_gettext('446', 'Tumbuka', 'ccvm', 'value')),
    (447, 'item_lang', 'tup', oils_i18n_gettext('447', 'Tupi languages', 'ccvm', 'value')),
    (448, 'item_lang', 'tur', oils_i18n_gettext('448', 'Turkish', 'ccvm', 'value')),
    (449, 'item_lang', 'tut', oils_i18n_gettext('449', 'Altaic (Other)', 'ccvm', 'value')),
    (450, 'item_lang', 'tvl', oils_i18n_gettext('450', 'Tuvaluan', 'ccvm', 'value')),
    (451, 'item_lang', 'twi', oils_i18n_gettext('451', 'Twi', 'ccvm', 'value')),
    (452, 'item_lang', 'tyv', oils_i18n_gettext('452', 'Tuvinian', 'ccvm', 'value')),
    (453, 'item_lang', 'udm', oils_i18n_gettext('453', 'Udmurt', 'ccvm', 'value')),
    (454, 'item_lang', 'uga', oils_i18n_gettext('454', 'Ugaritic', 'ccvm', 'value')),
    (455, 'item_lang', 'uig', oils_i18n_gettext('455', 'Uighur', 'ccvm', 'value')),
    (456, 'item_lang', 'ukr', oils_i18n_gettext('456', 'Ukrainian', 'ccvm', 'value')),
    (457, 'item_lang', 'umb', oils_i18n_gettext('457', 'Umbundu', 'ccvm', 'value')),
    (458, 'item_lang', 'und', oils_i18n_gettext('458', 'Undetermined', 'ccvm', 'value')),
    (459, 'item_lang', 'urd', oils_i18n_gettext('459', 'Urdu', 'ccvm', 'value')),
    (460, 'item_lang', 'uzb', oils_i18n_gettext('460', 'Uzbek', 'ccvm', 'value')),
    (461, 'item_lang', 'vai', oils_i18n_gettext('461', 'Vai', 'ccvm', 'value')),
    (462, 'item_lang', 'ven', oils_i18n_gettext('462', 'Venda', 'ccvm', 'value')),
    (463, 'item_lang', 'vie', oils_i18n_gettext('463', 'Vietnamese', 'ccvm', 'value')),
    (464, 'item_lang', 'vol', oils_i18n_gettext('464', 'Volapük', 'ccvm', 'value')),
    (465, 'item_lang', 'vot', oils_i18n_gettext('465', 'Votic', 'ccvm', 'value')),
    (466, 'item_lang', 'wak', oils_i18n_gettext('466', 'Wakashan languages', 'ccvm', 'value')),
    (467, 'item_lang', 'wal', oils_i18n_gettext('467', 'Walamo', 'ccvm', 'value')),
    (468, 'item_lang', 'war', oils_i18n_gettext('468', 'Waray', 'ccvm', 'value')),
    (469, 'item_lang', 'was', oils_i18n_gettext('469', 'Washo', 'ccvm', 'value')),
    (470, 'item_lang', 'wel', oils_i18n_gettext('470', 'Welsh', 'ccvm', 'value')),
    (471, 'item_lang', 'wen', oils_i18n_gettext('471', 'Sorbian languages', 'ccvm', 'value')),
    (472, 'item_lang', 'wln', oils_i18n_gettext('472', 'Walloon', 'ccvm', 'value')),
    (473, 'item_lang', 'wol', oils_i18n_gettext('473', 'Wolof', 'ccvm', 'value')),
    (474, 'item_lang', 'xal', oils_i18n_gettext('474', 'Kalmyk', 'ccvm', 'value')),
    (475, 'item_lang', 'xho', oils_i18n_gettext('475', 'Xhosa', 'ccvm', 'value')),
    (476, 'item_lang', 'yao', oils_i18n_gettext('476', 'Yao (Africa)', 'ccvm', 'value')),
    (477, 'item_lang', 'yap', oils_i18n_gettext('477', 'Yapese', 'ccvm', 'value')),
    (478, 'item_lang', 'yid', oils_i18n_gettext('478', 'Yiddish', 'ccvm', 'value')),
    (479, 'item_lang', 'yor', oils_i18n_gettext('479', 'Yoruba', 'ccvm', 'value')),
    (480, 'item_lang', 'ypk', oils_i18n_gettext('480', 'Yupik languages', 'ccvm', 'value')),
    (481, 'item_lang', 'zap', oils_i18n_gettext('481', 'Zapotec', 'ccvm', 'value')),
    (482, 'item_lang', 'zen', oils_i18n_gettext('482', 'Zenaga', 'ccvm', 'value')),
    (483, 'item_lang', 'zha', oils_i18n_gettext('483', 'Zhuang', 'ccvm', 'value')),
    (484, 'item_lang', 'znd', oils_i18n_gettext('484', 'Zande', 'ccvm', 'value')),
    (485, 'item_lang', 'zul', oils_i18n_gettext('485', 'Zulu', 'ccvm', 'value')),
    (486, 'item_lang', 'zun', oils_i18n_gettext('486', 'Zuni', 'ccvm', 'value'));

INSERT INTO config.coded_value_map (id, ctype, code, value, description) VALUES 
    (487,'audience', ' ', oils_i18n_gettext('487', 'Unknown or unspecified', 'ccvm', 'value'),  oils_i18n_gettext('487', 'The target audience for the item not known or not specified.', 'ccvm', 'description')),
    (488,'audience', 'a', oils_i18n_gettext('488', 'Preschool', 'ccvm', 'value'),               oils_i18n_gettext('488', 'The item is intended for children, approximate ages 0-5 years.', 'ccvm', 'description')),
    (489,'audience', 'b', oils_i18n_gettext('489', 'Primary', 'ccvm', 'value'),                 oils_i18n_gettext('489', 'The item is intended for children, approximate ages 6-8 years.', 'ccvm', 'description')),
    (490,'audience', 'c', oils_i18n_gettext('490', 'Pre-adolescent', 'ccvm', 'value'),          oils_i18n_gettext('490', 'The item is intended for young people, approximate ages 9-13 years.', 'ccvm', 'description')),
    (491,'audience', 'd', oils_i18n_gettext('491', 'Adolescent', 'ccvm', 'value'),              oils_i18n_gettext('491', 'The item is intended for young people, approximate ages 14-17 years.', 'ccvm', 'description')),
    (492,'audience', 'e', oils_i18n_gettext('492', 'Adult', 'ccvm', 'value'),                   oils_i18n_gettext('492', 'The item is intended for adults.', 'ccvm', 'description')),
    (493,'audience', 'f', oils_i18n_gettext('493', 'Specialized', 'ccvm', 'value'),             oils_i18n_gettext('493', 'The item is aimed at a particular audience and the nature of the presentation makes the item of little interest to another audience.', 'ccvm', 'description')),
    (494,'audience', 'g', oils_i18n_gettext('494', 'General', 'ccvm', 'value'),                 oils_i18n_gettext('494', 'The item is of general interest and not aimed at an audience of a particular intellectual level.', 'ccvm', 'description')),
    (495,'audience', 'j', oils_i18n_gettext('495', 'Juvenile', 'ccvm', 'value'),                oils_i18n_gettext('495', 'The item is intended for children and young people, approximate ages 0-15 years.', 'ccvm', 'description'));

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
    (496, 'item_type', 'a', oils_i18n_gettext('496', 'Language material', 'ccvm', 'value')),
    (497, 'item_type', 't', oils_i18n_gettext('497', 'Manuscript language material', 'ccvm', 'value')),
    (498, 'item_type', 'g', oils_i18n_gettext('498', 'Projected medium', 'ccvm', 'value')),
    (499, 'item_type', 'k', oils_i18n_gettext('499', 'Two-dimensional nonprojectable graphic', 'ccvm', 'value')),
    (500, 'item_type', 'r', oils_i18n_gettext('500', 'Three-dimensional artifact or naturally occurring object', 'ccvm', 'value')),
    (501, 'item_type', 'o', oils_i18n_gettext('501', 'Kit', 'ccvm', 'value')),
    (502, 'item_type', 'p', oils_i18n_gettext('502', 'Mixed materials', 'ccvm', 'value')),
    (503, 'item_type', 'e', oils_i18n_gettext('503', 'Cartographic material', 'ccvm', 'value')),
    (504, 'item_type', 'f', oils_i18n_gettext('504', 'Manuscript cartographic material', 'ccvm', 'value')),
    (505, 'item_type', 'c', oils_i18n_gettext('505', 'Notated music', 'ccvm', 'value')),
    (506, 'item_type', 'd', oils_i18n_gettext('506', 'Manuscript notated music', 'ccvm', 'value')),
    (507, 'item_type', 'i', oils_i18n_gettext('507', 'Nonmusical sound recording', 'ccvm', 'value')),
    (508, 'item_type', 'j', oils_i18n_gettext('508', 'Musical sound recording', 'ccvm', 'value')),
    (509, 'item_type', 'm', oils_i18n_gettext('509', 'Computer file', 'ccvm', 'value'));

INSERT INTO config.coded_value_map (id, ctype, code, value, description) VALUES 
    (510, 'lit_form', '0', oils_i18n_gettext('510', 'Not fiction (not further specified)', 'ccvm', 'value'), oils_i18n_gettext('510', 'The item is not a work of fiction and no further identification of the literary form is desired', 'ccvm', 'description')),
    (511, 'lit_form', '1', oils_i18n_gettext('511', 'Fiction (not further specified)', 'ccvm', 'value'),     oils_i18n_gettext('511', 'The item is a work of fiction and no further identification of the literary form is desired', 'ccvm', 'description')),
    (512, 'lit_form', 'c', oils_i18n_gettext('512', 'Comic strips', 'ccvm', 'value'), NULL),
    (513, 'lit_form', 'd', oils_i18n_gettext('513', 'Dramas', 'ccvm', 'value'), NULL),
    (514, 'lit_form', 'e', oils_i18n_gettext('514', 'Essays', 'ccvm', 'value'), NULL),
    (515, 'lit_form', 'f', oils_i18n_gettext('515', 'Novels', 'ccvm', 'value'), NULL),
    (516, 'lit_form', 'h', oils_i18n_gettext('516', 'Humor, satires, etc.', 'ccvm', 'value'),                oils_i18n_gettext('516', 'The item is a humorous work, satire or of similar literary form.', 'ccvm', 'description')),
    (517, 'lit_form', 'i', oils_i18n_gettext('517', 'Letters', 'ccvm', 'value'),                             oils_i18n_gettext('517', 'The item is a single letter or collection of correspondence.', 'ccvm', 'description')),
    (518, 'lit_form', 'j', oils_i18n_gettext('518', 'Short stories', 'ccvm', 'value'),                       oils_i18n_gettext('518', 'The item is a short story or collection of short stories.', 'ccvm', 'description')),
    (519, 'lit_form', 'm', oils_i18n_gettext('519', 'Mixed forms', 'ccvm', 'value'),                         oils_i18n_gettext('519', 'The item is a variety of literary forms (e.g., poetry and short stories).', 'ccvm', 'description')),
    (520, 'lit_form', 'p', oils_i18n_gettext('520', 'Poetry', 'ccvm', 'value'),                              oils_i18n_gettext('520', 'The item is a poem or collection of poems.', 'ccvm', 'description')),
    (521, 'lit_form', 's', oils_i18n_gettext('521', 'Speeches', 'ccvm', 'value'),                            oils_i18n_gettext('521', 'The item is a speech or collection of speeches.', 'ccvm', 'description')),
    (522, 'lit_form', 'u', oils_i18n_gettext('522', 'Unknown', 'ccvm', 'value'),                             oils_i18n_gettext('522', 'The literary form of the item is unknown.', 'ccvm', 'description'));


INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
    (523, 'item_form', 'a', oils_i18n_gettext('523', 'Microfilm', 'ccvm', 'value')),
    (524, 'item_form', 'b', oils_i18n_gettext('524', 'Microfiche', 'ccvm', 'value')),
    (525, 'item_form', 'c', oils_i18n_gettext('525', 'Microopaque', 'ccvm', 'value')),
    (526, 'item_form', 'd', oils_i18n_gettext('526', 'Large print', 'ccvm', 'value')),
    (527, 'item_form', 'f', oils_i18n_gettext('527', 'Braille', 'ccvm', 'value')),
    (528, 'item_form', 'r', oils_i18n_gettext('528', 'Regular print reproduction', 'ccvm', 'value')),
    (529, 'item_form', 's', oils_i18n_gettext('529', 'Electronic', 'ccvm', 'value'));
    -- see below for more item_form entries

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
    (530, 'bib_level', 'a', oils_i18n_gettext('530', 'Monographic component part', 'ccvm', 'value')),
    (531, 'bib_level', 'b', oils_i18n_gettext('531', 'Serial component part', 'ccvm', 'value')),
    (532, 'bib_level', 'c', oils_i18n_gettext('532', 'Collection', 'ccvm', 'value')),
    (533, 'bib_level', 'd', oils_i18n_gettext('533', 'Subunit', 'ccvm', 'value')),
    (534, 'bib_level', 'i', oils_i18n_gettext('534', 'Integrating resource', 'ccvm', 'value')),
    (535, 'bib_level', 'm', oils_i18n_gettext('535', 'Monograph/Item', 'ccvm', 'value')),
    (536, 'bib_level', 's', oils_i18n_gettext('536', 'Serial', 'ccvm', 'value'));

INSERT INTO config.coded_value_map(id, ctype, code, value) VALUES
    (537, 'vr_format', 'a', oils_i18n_gettext('537', 'Beta', 'ccvm', 'value')),
    (538, 'vr_format', 'b', oils_i18n_gettext('538', 'VHS', 'ccvm', 'value')),
    (539, 'vr_format', 'c', oils_i18n_gettext('539', 'U-matic', 'ccvm', 'value')),
    (540, 'vr_format', 'd', oils_i18n_gettext('540', 'EIAJ', 'ccvm', 'value')),
    (541, 'vr_format', 'e', oils_i18n_gettext('541', 'Type C', 'ccvm', 'value')),
    (542, 'vr_format', 'f', oils_i18n_gettext('542', 'Quadruplex', 'ccvm', 'value')),
    (543, 'vr_format', 'g', oils_i18n_gettext('543', 'Laserdisc', 'ccvm', 'value')),
    (544, 'vr_format', 'h', oils_i18n_gettext('544', 'CED videodisc', 'ccvm', 'value')),
    (545, 'vr_format', 'i', oils_i18n_gettext('545', 'Betacam', 'ccvm', 'value')),
    (546, 'vr_format', 'j', oils_i18n_gettext('546', 'Betacam SP', 'ccvm', 'value')),
    (547, 'vr_format', 'k', oils_i18n_gettext('547', 'Super-VHS', 'ccvm', 'value')),
    (548, 'vr_format', 'm', oils_i18n_gettext('548', 'M-II', 'ccvm', 'value')),
    (549, 'vr_format', 'o', oils_i18n_gettext('549', 'D-2', 'ccvm', 'value')),
    (550, 'vr_format', 'p', oils_i18n_gettext('550', '8 mm.', 'ccvm', 'value')),
    (551, 'vr_format', 'q', oils_i18n_gettext('551', 'Hi-8 mm.', 'ccvm', 'value')),
    (552, 'vr_format', 's', oils_i18n_gettext('552', 'Blu-ray disc', 'ccvm', 'value')),
    (553, 'vr_format', 'u', oils_i18n_gettext('553', 'Unknown', 'ccvm', 'value')),
    (554, 'vr_format', 'v', oils_i18n_gettext('554', 'DVD', 'ccvm', 'value')),
    (555, 'vr_format', 'z', oils_i18n_gettext('555', 'Other', 'ccvm', 'value')),
    (556, 'vr_format', ' ', oils_i18n_gettext('556', 'Unspecified', 'ccvm', 'value'));

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
    (557, 'sr_format', 'a', oils_i18n_gettext(557, '16 rpm', 'ccvm', 'value')),
    (558, 'sr_format', 'b', oils_i18n_gettext(558, '33 1/3 rpm', 'ccvm', 'value')),
    (559, 'sr_format', 'c', oils_i18n_gettext(559, '45 rpm', 'ccvm', 'value')),
    (560, 'sr_format', 'f', oils_i18n_gettext(560, '1.4 m. per second', 'ccvm', 'value')),
    (561, 'sr_format', 'd', oils_i18n_gettext(561, '78 rpm', 'ccvm', 'value')),
    (562, 'sr_format', 'e', oils_i18n_gettext(562, '8 rpm', 'ccvm', 'value')),
    (563, 'sr_format', 'l', oils_i18n_gettext(563, '1 7/8 ips', 'ccvm', 'value'));

INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(564, 'icon_format', 'book', 
    oils_i18n_gettext(564, 'Book', 'ccvm', 'value'),
    oils_i18n_gettext(564, 'Book', 'ccvm', 'search_label')),
(565, 'icon_format', 'braille', 
    oils_i18n_gettext(565, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(565, 'Braille', 'ccvm', 'search_label')),
(566, 'icon_format', 'software', 
    oils_i18n_gettext(566, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(566, 'Software and video games', 'ccvm', 'search_label')),
(567, 'icon_format', 'dvd', 
    oils_i18n_gettext(567, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(567, 'DVD', 'ccvm', 'search_label')),
(568, 'icon_format', 'ebook', 
    oils_i18n_gettext(568, 'E-book', 'ccvm', 'value'),
    oils_i18n_gettext(568, 'E-book', 'ccvm', 'search_label')),
(569, 'icon_format', 'eaudio', 
    oils_i18n_gettext(569, 'E-audio', 'ccvm', 'value'),
    oils_i18n_gettext(569, 'E-audio', 'ccvm', 'search_label')),
(570, 'icon_format', 'kit', 
    oils_i18n_gettext(570, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(570, 'Kit', 'ccvm', 'search_label')),
(571, 'icon_format', 'map', 
    oils_i18n_gettext(571, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(571, 'Map', 'ccvm', 'search_label')),
(572, 'icon_format', 'microform', 
    oils_i18n_gettext(572, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(572, 'Microform', 'ccvm', 'search_label')),
(573, 'icon_format', 'score', 
    oils_i18n_gettext(573, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(573, 'Music Score', 'ccvm', 'search_label')),
(574, 'icon_format', 'picture', 
    oils_i18n_gettext(574, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(574, 'Picture', 'ccvm', 'search_label')),
(575, 'icon_format', 'equip', 
    oils_i18n_gettext(575, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(575, 'Equipment, games, toys', 'ccvm', 'search_label')),
(576, 'icon_format', 'serial', 
    oils_i18n_gettext(576, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(576, 'Serials and magazines', 'ccvm', 'search_label')),
(577, 'icon_format', 'vhs', 
    oils_i18n_gettext(577, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(577, 'VHS', 'ccvm', 'search_label')),
(578, 'icon_format', 'evideo', 
    oils_i18n_gettext(578, 'E-video', 'ccvm', 'value'),
    oils_i18n_gettext(578, 'E-video', 'ccvm', 'search_label')),
(579, 'icon_format', 'cdaudiobook', 
    oils_i18n_gettext(579, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(579, 'CD Audiobook', 'ccvm', 'search_label')),
(580, 'icon_format', 'cdmusic', 
    oils_i18n_gettext(580, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(580, 'CD Music recording', 'ccvm', 'search_label')),
(581, 'icon_format', 'casaudiobook', 
    oils_i18n_gettext(581, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(581, 'Cassette audiobook', 'ccvm', 'search_label')),
(582, 'icon_format', 'casmusic',
    oils_i18n_gettext(582, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(582, 'Audiocassette music recording', 'ccvm', 'search_label')),
(583, 'icon_format', 'phonospoken', 
    oils_i18n_gettext(583, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(583, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(584, 'icon_format', 'phonomusic', 
    oils_i18n_gettext(584, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(584, 'Phonograph music recording', 'ccvm', 'search_label')),
(585, 'icon_format', 'lpbook', 
    oils_i18n_gettext(585, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(585, 'Large Print Book', 'ccvm', 'search_label')),
(1736,'icon_format','preloadedaudio',
        oils_i18n_gettext(1736, 'Preloaded Audio', 'ccvm', 'value'),
        oils_i18n_gettext(1736, 'Preloaded Audio', 'ccvm', 'search_label'));

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES 
(586, 'item_form', 'o', oils_i18n_gettext('586', 'Online', 'ccvm', 'value')),
(587, 'item_form', 'q', oils_i18n_gettext('587', 'Direct electronic', 'ccvm', 'value'));

-- these formats are a subset of the "icon_format" attribute,
-- modified to exclude electronic resources, which are not holdable
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(588, 'mr_hold_format', 'book', 
    oils_i18n_gettext(588, 'Book', 'ccvm', 'value'),
    oils_i18n_gettext(588, 'Book', 'ccvm', 'search_label')),
(589, 'mr_hold_format', 'braille', 
    oils_i18n_gettext(589, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(589, 'Braille', 'ccvm', 'search_label')),
(590, 'mr_hold_format', 'software', 
    oils_i18n_gettext(590, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(590, 'Software and video games', 'ccvm', 'search_label')),
(591, 'mr_hold_format', 'dvd', 
    oils_i18n_gettext(591, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(591, 'DVD', 'ccvm', 'search_label')),
(592, 'mr_hold_format', 'kit', 
    oils_i18n_gettext(592, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(592, 'Kit', 'ccvm', 'search_label')),
(593, 'mr_hold_format', 'map', 
    oils_i18n_gettext(593, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(593, 'Map', 'ccvm', 'search_label')),
(594, 'mr_hold_format', 'microform', 
    oils_i18n_gettext(594, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(594, 'Microform', 'ccvm', 'search_label')),
(595, 'mr_hold_format', 'score', 
    oils_i18n_gettext(595, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(595, 'Music Score', 'ccvm', 'search_label')),
(596, 'mr_hold_format', 'picture', 
    oils_i18n_gettext(596, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(596, 'Picture', 'ccvm', 'search_label')),
(597, 'mr_hold_format', 'equip', 
    oils_i18n_gettext(597, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(597, 'Equipment, games, toys', 'ccvm', 'search_label')),
(598, 'mr_hold_format', 'serial', 
    oils_i18n_gettext(598, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(598, 'Serials and magazines', 'ccvm', 'search_label')),
(599, 'mr_hold_format', 'vhs', 
    oils_i18n_gettext(599, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(599, 'VHS', 'ccvm', 'search_label')),
(600, 'mr_hold_format', 'cdaudiobook', 
    oils_i18n_gettext(600, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(600, 'CD Audiobook', 'ccvm', 'search_label')),
(601, 'mr_hold_format', 'cdmusic', 
    oils_i18n_gettext(601, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(601, 'CD Music recording', 'ccvm', 'search_label')),
(602, 'mr_hold_format', 'casaudiobook', 
    oils_i18n_gettext(602, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(602, 'Cassette audiobook', 'ccvm', 'search_label')),
(603, 'mr_hold_format', 'casmusic',
    oils_i18n_gettext(603, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(603, 'Audiocassette music recording', 'ccvm', 'search_label')),
(604, 'mr_hold_format', 'phonospoken', 
    oils_i18n_gettext(604, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(604, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(605, 'mr_hold_format', 'phonomusic', 
    oils_i18n_gettext(605, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(605, 'Phonograph music recording', 'ccvm', 'search_label')),
(606, 'mr_hold_format', 'lpbook', 
    oils_i18n_gettext(606, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(606, 'Large Print Book', 'ccvm', 'search_label')) ;

-- catch-all music of unkown format
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(607, 'icon_format', 'music', 
    oils_i18n_gettext(607, 'Musical Sound Recording (Unknown Format)', 'ccvm', 'value'),
    oils_i18n_gettext(607, 'Musical Sound Recording (Unknown Format)', 'ccvm', 'search_label'));

-- icon for blu-ray
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(608, 'icon_format', 'blu-ray', 
    oils_i18n_gettext(608, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(608, 'Blu-ray', 'ccvm', 'search_label'));

-- metarecord hold format for blu-ray
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(609, 'mr_hold_format', 'blu-ray', 
    oils_i18n_gettext(609, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(609, 'Blu-ray', 'ccvm', 'search_label'));

-- search format values
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(610, 'search_format', 'book', 
    oils_i18n_gettext(610, 'All Books', 'ccvm', 'value'),
    oils_i18n_gettext(610, 'All Books', 'ccvm', 'search_label')),
(611, 'search_format', 'braille', 
    oils_i18n_gettext(611, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(611, 'Braille', 'ccvm', 'search_label')),
(612, 'search_format', 'software', 
    oils_i18n_gettext(612, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(612, 'Software and video games', 'ccvm', 'search_label')),
(613, 'search_format', 'dvd', 
    oils_i18n_gettext(613, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(613, 'DVD', 'ccvm', 'search_label')),
(614, 'search_format', 'ebook', 
    oils_i18n_gettext(614, 'E-book', 'ccvm', 'value'),
    oils_i18n_gettext(614, 'E-book', 'ccvm', 'search_label')),
(615, 'search_format', 'eaudio', 
    oils_i18n_gettext(615, 'E-audio', 'ccvm', 'value'),
    oils_i18n_gettext(615, 'E-audio', 'ccvm', 'search_label')),
(616, 'search_format', 'kit', 
    oils_i18n_gettext(616, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(616, 'Kit', 'ccvm', 'search_label')),
(617, 'search_format', 'map', 
    oils_i18n_gettext(617, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(617, 'Map', 'ccvm', 'search_label')),
(618, 'search_format', 'microform', 
    oils_i18n_gettext(618, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(618, 'Microform', 'ccvm', 'search_label')),
(619, 'search_format', 'score', 
    oils_i18n_gettext(619, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(619, 'Music Score', 'ccvm', 'search_label')),
(620, 'search_format', 'picture', 
    oils_i18n_gettext(620, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(620, 'Picture', 'ccvm', 'search_label')),
(621, 'search_format', 'equip', 
    oils_i18n_gettext(621, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(621, 'Equipment, games, toys', 'ccvm', 'search_label')),
(622, 'search_format', 'serial', 
    oils_i18n_gettext(622, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(622, 'Serials and magazines', 'ccvm', 'search_label')),
(623, 'search_format', 'vhs', 
    oils_i18n_gettext(623, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(623, 'VHS', 'ccvm', 'search_label')),
(624, 'search_format', 'evideo', 
    oils_i18n_gettext(624, 'E-video', 'ccvm', 'value'),
    oils_i18n_gettext(624, 'E-video', 'ccvm', 'search_label')),
(625, 'search_format', 'cdaudiobook', 
    oils_i18n_gettext(625, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(625, 'CD Audiobook', 'ccvm', 'search_label')),
(626, 'search_format', 'cdmusic', 
    oils_i18n_gettext(626, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(626, 'CD Music recording', 'ccvm', 'search_label')),
(627, 'search_format', 'casaudiobook', 
    oils_i18n_gettext(627, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(627, 'Cassette audiobook', 'ccvm', 'search_label')),
(628, 'search_format', 'casmusic',
    oils_i18n_gettext(628, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(628, 'Audiocassette music recording', 'ccvm', 'search_label')),
(629, 'search_format', 'phonospoken', 
    oils_i18n_gettext(629, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(629, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(630, 'search_format', 'phonomusic', 
    oils_i18n_gettext(630, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(630, 'Phonograph music recording', 'ccvm', 'search_label')),
(631, 'search_format', 'lpbook', 
    oils_i18n_gettext(631, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(631, 'Large Print Book', 'ccvm', 'search_label')),
(632, 'search_format', 'music', 
    oils_i18n_gettext(632, 'All Music', 'ccvm', 'label'),
    oils_i18n_gettext(632, 'All Music', 'ccvm', 'search_label')),
(633, 'search_format', 'blu-ray', 
    oils_i18n_gettext(633, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(633, 'Blu-ray', 'ccvm', 'search_label')),
(1737,'search_format','preloadedaudio',
    oils_i18n_gettext(1737, 'Preloaded Audio', 'ccvm', 'value'),
    oils_i18n_gettext(1737, 'Preloaded Audio', 'ccvm', 'search_label')),
(1738,'search_format','video',
    oils_i18n_gettext(1738, 'All Videos', 'ccvm', 'value'),
    oils_i18n_gettext(1738, 'All Videos', 'ccvm', 'search_label'));

-- Electronic search format, not opac_visible
INSERT INTO config.coded_value_map
    (id, ctype, code, opac_visible, value, search_label) VALUES
(712, 'search_format', 'electronic', FALSE,
    oils_i18n_gettext(712, 'Electronic', 'ccvm', 'value'),
    oils_i18n_gettext(712, 'Electronic', 'ccvm', 'search_label'));

-- RDA content type, media type, and carrier type
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (634, 'content_type', 'two-dimensional moving image',
  oils_i18n_gettext(634, 'two-dimensional moving image', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1023');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (635, 'content_type', 'three-dimensional moving image',
  oils_i18n_gettext(635, 'three-dimensional moving image', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1022');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (636, 'content_type', 'three-dimensional form',
  oils_i18n_gettext(636, 'three-dimensional form', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1021');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (637, 'content_type', 'text',
  oils_i18n_gettext(637, 'text', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1020');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (638, 'content_type', 'tactile three-dimensional form',
  oils_i18n_gettext(638, 'tactile three-dimensional form', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1019');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (639, 'content_type', 'tactile text',
  oils_i18n_gettext(639, 'tactile text', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1018');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (640, 'content_type', 'tactile notated movement',
  oils_i18n_gettext(640, 'tactile notated movement', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1017');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (641, 'content_type', 'tactile notated music',
  oils_i18n_gettext(641, 'tactile notated music', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1016');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (642, 'content_type', 'tactile image',
  oils_i18n_gettext(642, 'tactile image', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1015');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (643, 'content_type', 'still image',
  oils_i18n_gettext(643, 'still image', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1014');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (644, 'content_type', 'spoken word',
  oils_i18n_gettext(644, 'spoken word', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1013');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (645, 'content_type', 'sounds',
  oils_i18n_gettext(645, 'sounds', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1012');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (646, 'content_type', 'performed music',
  oils_i18n_gettext(646, 'performed music', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1011');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (647, 'content_type', 'notated music',
  oils_i18n_gettext(647, 'notated music', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1010');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (648, 'content_type', 'notated movement',
  oils_i18n_gettext(648, 'notated movement', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1009');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (649, 'content_type', 'computer program',
  oils_i18n_gettext(649, 'computer program', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1008');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (650, 'content_type', 'computer dataset',
  oils_i18n_gettext(650, 'computer dataset', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1007');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (651, 'content_type', 'cartographic three-dimensional form',
  oils_i18n_gettext(651, 'cartographic three-dimensional form', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1006');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (652, 'content_type', 'cartographic tactile three-dimensional form',
  oils_i18n_gettext(652, 'cartographic tactile three-dimensional form', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1005');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (653, 'content_type', 'cartographic tactile image',
  oils_i18n_gettext(653, 'cartographic tactile image', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1004');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (654, 'content_type', 'cartographic moving image',
  oils_i18n_gettext(654, 'cartographic moving image', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1003');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (655, 'content_type', 'cartographic image',
  oils_i18n_gettext(655, 'cartographic image', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1002');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (656, 'content_type', 'cartographic dataset',
  oils_i18n_gettext(656, 'cartographic dataset', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAContentType/1001');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (657, 'media_type', 'video',
  oils_i18n_gettext(657, 'video', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1008');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (658, 'media_type', 'unmediated',
  oils_i18n_gettext(658, 'unmediated', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1007');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (659, 'media_type', 'stereographic',
  oils_i18n_gettext(659, 'stereographic', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1006');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (660, 'media_type', 'projected',
  oils_i18n_gettext(660, 'projected', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1005');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (661, 'media_type', 'microscopic',
  oils_i18n_gettext(661, 'microscopic', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1004');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (662, 'media_type', 'computer',
  oils_i18n_gettext(662, 'computer', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1003');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (663, 'media_type', 'microform',
  oils_i18n_gettext(663, 'microform', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1002');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (664, 'media_type', 'audio',
  oils_i18n_gettext(664, 'audio', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDAMediaType/1001');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (665, 'media_type', 'Published',
  oils_i18n_gettext(665, 'Published', 'ccvm', 'value'),
  'http://metadataregistry.org/uri/RegStatus/1001');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (666, 'carrier_type', 'film roll',
  oils_i18n_gettext(666, 'film roll', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1069');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (667, 'carrier_type', 'videodisc',
  oils_i18n_gettext(667, 'videodisc', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1060');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (668, 'carrier_type', 'object',
  oils_i18n_gettext(668, 'object', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1059');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (669, 'carrier_type', 'microfilm roll',
  oils_i18n_gettext(669, 'microfilm roll', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1056');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (670, 'carrier_type', 'videotape reel',
  oils_i18n_gettext(670, 'videotape reel', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1053');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (671, 'carrier_type', 'videocassette',
  oils_i18n_gettext(671, 'videocassette', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1052');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (672, 'carrier_type', 'video cartridge',
  oils_i18n_gettext(672, 'video cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1051');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (673, 'carrier_type', 'volume',
  oils_i18n_gettext(673, 'volume', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1049');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (674, 'carrier_type', 'sheet',
  oils_i18n_gettext(674, 'sheet', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1048');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (675, 'carrier_type', 'roll',
  oils_i18n_gettext(675, 'roll', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1047');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (676, 'carrier_type', 'flipchart',
  oils_i18n_gettext(676, 'flipchart', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1046');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (677, 'carrier_type', 'card',
  oils_i18n_gettext(677, 'card', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1045');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (678, 'carrier_type', 'stereograph disc',
  oils_i18n_gettext(678, 'stereograph disc', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1043');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (679, 'carrier_type', 'stereograph card',
  oils_i18n_gettext(679, 'stereograph card', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1042');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (680, 'carrier_type', 'slide',
  oils_i18n_gettext(680, 'slide', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1040');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (681, 'carrier_type', 'overhead transparency',
  oils_i18n_gettext(681, 'overhead transparency', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1039');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (682, 'carrier_type', 'filmstrip cartridge',
  oils_i18n_gettext(682, 'filmstrip cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1037');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (683, 'carrier_type', 'filmstrip',
  oils_i18n_gettext(683, 'filmstrip', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1036');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (684, 'carrier_type', 'filmslip',
  oils_i18n_gettext(684, 'filmslip', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1035');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (685, 'carrier_type', 'film reel',
  oils_i18n_gettext(685, 'film reel', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1034');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (686, 'carrier_type', 'film cassette',
  oils_i18n_gettext(686, 'film cassette', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1033');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (687, 'carrier_type', 'film cartridge',
  oils_i18n_gettext(687, 'film cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1032');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (688, 'carrier_type', 'microscope slide',
  oils_i18n_gettext(688, 'microscope slide', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1030');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (689, 'carrier_type', 'microopaque',
  oils_i18n_gettext(689, 'microopaque', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1028');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (690, 'carrier_type', 'microfilm slip',
  oils_i18n_gettext(690, 'microfilm slip', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1027');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (691, 'carrier_type', 'microfilm reel',
  oils_i18n_gettext(691, 'microfilm reel', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1026');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (692, 'carrier_type', 'microfilm cassette',
  oils_i18n_gettext(692, 'microfilm cassette', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1025');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (693, 'carrier_type', 'microfilm cartridge',
  oils_i18n_gettext(693, 'microfilm cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1024');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (694, 'carrier_type', 'microfiche cassette',
  oils_i18n_gettext(694, 'microfiche cassette', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1023');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (695, 'carrier_type', 'microfiche',
  oils_i18n_gettext(695, 'microfiche', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1022');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (696, 'carrier_type', 'aperture card',
  oils_i18n_gettext(696, 'aperture card', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1021');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (697, 'carrier_type', 'online resource',
  oils_i18n_gettext(697, 'online resource', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1018');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (698, 'carrier_type', 'computer tape reel',
  oils_i18n_gettext(698, 'computer tape reel', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1017');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (699, 'carrier_type', 'computer tape cassette',
  oils_i18n_gettext(699, 'computer tape cassette', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1016');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (700, 'carrier_type', 'computer tape cartridge',
  oils_i18n_gettext(700, 'computer tape cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1015');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (701, 'carrier_type', 'computer disc cartridge',
  oils_i18n_gettext(701, 'computer disc cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1014');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (702, 'carrier_type', 'computer disc',
  oils_i18n_gettext(702, 'computer disc', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1013');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (703, 'carrier_type', 'computer chip cartridge',
  oils_i18n_gettext(703, 'computer chip cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1012');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (704, 'carrier_type', 'computer card',
  oils_i18n_gettext(704, 'computer card', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1011');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (705, 'carrier_type', 'audiotape reel',
  oils_i18n_gettext(705, 'audiotape reel', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1008');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (706, 'carrier_type', 'audiocassette',
  oils_i18n_gettext(706, 'audiocassette', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1007');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (707, 'carrier_type', 'audio roll',
  oils_i18n_gettext(707, 'audio roll', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1006');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (708, 'carrier_type', 'sound-track reel',
  oils_i18n_gettext(708, 'sound-track reel', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1005');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (709, 'carrier_type', 'audio disc',
  oils_i18n_gettext(709, 'audio disc', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1004');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (710, 'carrier_type', 'audio cylinder',
  oils_i18n_gettext(710, 'audio cylinder', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1003');
INSERT INTO config.coded_value_map (id, ctype, code, value, concept_uri)
  VALUES (711, 'carrier_type', 'audio cartridge',
  oils_i18n_gettext(711, 'audio cartridge', 'ccvm', 'value'),
  'http://rdaregistry.info/termList/RDACarrierType/1002');

-- Accompanying Matter
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1735, 'accm', ' ', oils_i18n_gettext('1735', 'No accompanying matter', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (713, 'accm', 'a', oils_i18n_gettext('713', 'Discography', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (714, 'accm', 'b', oils_i18n_gettext('714', 'Bibliography', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (715, 'accm', 'c', oils_i18n_gettext('715', 'Thematic index', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (716, 'accm', 'd', oils_i18n_gettext('716', 'Libretto or text', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (717, 'accm', 'e', oils_i18n_gettext('717', 'Biography of composer or author', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (718, 'accm', 'f', oils_i18n_gettext('718', 'Biography or performer or history of ensemble', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (719, 'accm', 'g', oils_i18n_gettext('719', 'Technical and/or historical information on instruments', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (720, 'accm', 'h', oils_i18n_gettext('720', 'Technical information on music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (721, 'accm', 'i', oils_i18n_gettext('721', 'Historical information', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (722, 'accm', 'k', oils_i18n_gettext('722', 'Ethnological information', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (723, 'accm', 'r', oils_i18n_gettext('723', 'Instructional materials', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (724, 'accm', 's', oils_i18n_gettext('724', 'Music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (725, 'accm', 'z', oils_i18n_gettext('725', 'Other accompanying matter', 'ccvm', 'value'));

-- Form of Composition
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (726, 'comp', '  ', oils_i18n_gettext('726', 'No information supplied', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (727, 'comp', 'an', oils_i18n_gettext('727', 'Anthems', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (728, 'comp', 'bd', oils_i18n_gettext('728', 'Ballads', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (729, 'comp', 'bt', oils_i18n_gettext('729', 'Ballets', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (730, 'comp', 'bg', oils_i18n_gettext('730', 'Bluegrass music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (731, 'comp', 'bl', oils_i18n_gettext('731', 'Blues', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (732, 'comp', 'cn', oils_i18n_gettext('732', 'Canons and rounds', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (733, 'comp', 'ct', oils_i18n_gettext('733', 'Cantatas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (734, 'comp', 'cz', oils_i18n_gettext('734', 'Canzonas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (735, 'comp', 'cr', oils_i18n_gettext('735', 'Carols', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (736, 'comp', 'ca', oils_i18n_gettext('736', 'Chaconnes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (737, 'comp', 'cs', oils_i18n_gettext('737', 'Chance compositions', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (738, 'comp', 'cp', oils_i18n_gettext('738', 'Chansons, Polyphonic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (739, 'comp', 'cc', oils_i18n_gettext('739', 'Chant, Christian', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (740, 'comp', 'cb', oils_i18n_gettext('740', 'Chants, other', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (741, 'comp', 'cl', oils_i18n_gettext('741', 'Chorale preludes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (742, 'comp', 'ch', oils_i18n_gettext('742', 'Chorales', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (743, 'comp', 'cg', oils_i18n_gettext('743', 'Concerti grossi', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (744, 'comp', 'co', oils_i18n_gettext('744', 'Concertos', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (745, 'comp', 'cy', oils_i18n_gettext('745', 'Country music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (746, 'comp', 'df', oils_i18n_gettext('746', 'Dance forms', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (747, 'comp', 'dv', oils_i18n_gettext('747', 'Divertimentos, serenades, cassations, divertissements, and notturni', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (748, 'comp', 'ft', oils_i18n_gettext('748', 'Fantasias', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (749, 'comp', 'fl', oils_i18n_gettext('749', 'Flamenco', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (750, 'comp', 'fm', oils_i18n_gettext('750', 'Folk music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (751, 'comp', 'fg', oils_i18n_gettext('751', 'Fugues', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (752, 'comp', 'gm', oils_i18n_gettext('752', 'Gospel music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (753, 'comp', 'hy', oils_i18n_gettext('753', 'Hymns', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (754, 'comp', 'jz', oils_i18n_gettext('754', 'Jazz', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (755, 'comp', 'md', oils_i18n_gettext('755', 'Madrigals', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (756, 'comp', 'mr', oils_i18n_gettext('756', 'Marches', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (757, 'comp', 'ms', oils_i18n_gettext('757', 'Masses', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (758, 'comp', 'mz', oils_i18n_gettext('758', 'Mazurkas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (759, 'comp', 'mi', oils_i18n_gettext('759', 'Minuets', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (760, 'comp', 'mo', oils_i18n_gettext('760', 'Motets', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (761, 'comp', 'mp', oils_i18n_gettext('761', 'Motion picture music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (762, 'comp', 'mu', oils_i18n_gettext('762', 'Multiple forms', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (763, 'comp', 'mc', oils_i18n_gettext('763', 'Musical reviews and comedies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (764, 'comp', 'nc', oils_i18n_gettext('764', 'Nocturnes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (765, 'comp', 'nn', oils_i18n_gettext('765', 'Not applicable', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (766, 'comp', 'op', oils_i18n_gettext('766', 'Operas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (767, 'comp', 'or', oils_i18n_gettext('767', 'Oratorios', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (768, 'comp', 'ov', oils_i18n_gettext('768', 'Overtures', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (769, 'comp', 'pt', oils_i18n_gettext('769', 'Part-songs', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (770, 'comp', 'ps', oils_i18n_gettext('770', 'Passacaglias', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (771, 'comp', 'pm', oils_i18n_gettext('771', 'Passion music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (772, 'comp', 'pv', oils_i18n_gettext('772', 'Pavans', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (773, 'comp', 'po', oils_i18n_gettext('773', 'Polonaises', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (774, 'comp', 'pp', oils_i18n_gettext('774', 'Popular music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (775, 'comp', 'pr', oils_i18n_gettext('775', 'Preludes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (776, 'comp', 'pg', oils_i18n_gettext('776', 'Program music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (777, 'comp', 'rg', oils_i18n_gettext('777', 'Ragtime music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (778, 'comp', 'rq', oils_i18n_gettext('778', 'Requiems', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (779, 'comp', 'rp', oils_i18n_gettext('779', 'Rhapsodies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (780, 'comp', 'ri', oils_i18n_gettext('780', 'Ricercars', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (781, 'comp', 'rc', oils_i18n_gettext('781', 'Rock music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (782, 'comp', 'rd', oils_i18n_gettext('782', 'Rondos', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (783, 'comp', 'sn', oils_i18n_gettext('783', 'Sonatas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (784, 'comp', 'sg', oils_i18n_gettext('784', 'Songs', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (785, 'comp', 'sd', oils_i18n_gettext('785', 'Square dance music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (786, 'comp', 'st', oils_i18n_gettext('786', 'Studies and exercises', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (787, 'comp', 'su', oils_i18n_gettext('787', 'Suites', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (788, 'comp', 'sp', oils_i18n_gettext('788', 'Symphonic poems', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (789, 'comp', 'sy', oils_i18n_gettext('789', 'Symphonies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (790, 'comp', 'tl', oils_i18n_gettext('790', 'Teatro lirico', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (791, 'comp', 'tc', oils_i18n_gettext('791', 'Toccatas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (792, 'comp', 'ts', oils_i18n_gettext('792', 'Trio-sonatas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (793, 'comp', 'uu', oils_i18n_gettext('793', 'Unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (794, 'comp', 'vi', oils_i18n_gettext('794', 'Villancicos', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (795, 'comp', 'vr', oils_i18n_gettext('795', 'Variations', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (796, 'comp', 'wz', oils_i18n_gettext('796', 'Waltzes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (797, 'comp', 'za', oils_i18n_gettext('797', 'Zarzuelas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (798, 'comp', 'zz', oils_i18n_gettext('798', 'Other forms', 'ccvm', 'value'));

-- Type of Cartographic Material
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (799, 'crtp', 'a', oils_i18n_gettext('799', 'Single map', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (800, 'crtp', 'b', oils_i18n_gettext('800', 'Map series', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (801, 'crtp', 'c', oils_i18n_gettext('801', 'Map serial', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (802, 'crtp', 'd', oils_i18n_gettext('802', 'Globe', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (803, 'crtp', 'e', oils_i18n_gettext('803', 'Atlas', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (804, 'crtp', 'f', oils_i18n_gettext('804', 'Separate supplement to another work', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (805, 'crtp', 'g', oils_i18n_gettext('805', 'Bound as part of another work', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (806, 'crtp', 'u', oils_i18n_gettext('806', 'Unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (807, 'crtp', 'z', oils_i18n_gettext('807', 'Other', 'ccvm', 'value'));

-- Nature of Entire Work
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (808, 'entw', ' ', oils_i18n_gettext('808', 'Not specified', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (809, 'entw', 'a', oils_i18n_gettext('809', 'Abstracts/summaries', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (810, 'entw', 'b', oils_i18n_gettext('810', 'Bibliographies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (811, 'entw', 'c', oils_i18n_gettext('811', 'Catalogs', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (812, 'entw', 'd', oils_i18n_gettext('812', 'Dictionaries', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (813, 'entw', 'e', oils_i18n_gettext('813', 'Encyclopedias', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (814, 'entw', 'f', oils_i18n_gettext('814', 'Handbooks', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (815, 'entw', 'g', oils_i18n_gettext('815', 'Legal articles', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (816, 'entw', 'h', oils_i18n_gettext('816', 'Biography', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (817, 'entw', 'i', oils_i18n_gettext('817', 'Indexes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (818, 'entw', 'k', oils_i18n_gettext('818', 'Discographies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (819, 'entw', 'l', oils_i18n_gettext('819', 'Legislation', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (820, 'entw', 'm', oils_i18n_gettext('820', 'Theses', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (821, 'entw', 'n', oils_i18n_gettext('821', 'Surveys of the literature in a subject area', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (822, 'entw', 'o', oils_i18n_gettext('822', 'Reviews', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (823, 'entw', 'p', oils_i18n_gettext('823', 'Programmed texts', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (824, 'entw', 'q', oils_i18n_gettext('824', 'Filmographies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (825, 'entw', 'r', oils_i18n_gettext('825', 'Directories', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (826, 'entw', 's', oils_i18n_gettext('826', 'Statistics', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (827, 'entw', 't', oils_i18n_gettext('827', 'Technical reports', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (828, 'entw', 'u', oils_i18n_gettext('828', 'Standards/specifications', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (829, 'entw', 'v', oils_i18n_gettext('829', 'Legal cases and case notes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (830, 'entw', 'w', oils_i18n_gettext('830', 'Law reports and digests', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (831, 'entw', 'y', oils_i18n_gettext('831', 'Yearbooks', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (832, 'entw', 'z', oils_i18n_gettext('832', 'Treaties', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (833, 'entw', '5', oils_i18n_gettext('833', 'Calendars', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (834, 'entw', '6', oils_i18n_gettext('834', 'Comics/graphic novels', 'ccvm', 'value'));

-- Nature of Contents
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (835, 'cont', ' ', oils_i18n_gettext('835', 'Not specified', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (836, 'cont', 'a', oils_i18n_gettext('836', 'Abstracts/summaries', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (837, 'cont', 'b', oils_i18n_gettext('837', 'Bibliographies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (838, 'cont', 'c', oils_i18n_gettext('838', 'Catalogs', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (839, 'cont', 'd', oils_i18n_gettext('839', 'Dictionaries', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (840, 'cont', 'e', oils_i18n_gettext('840', 'Encyclopedias', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (841, 'cont', 'f', oils_i18n_gettext('841', 'Handbooks', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (842, 'cont', 'g', oils_i18n_gettext('842', 'Legal articles', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (843, 'cont', 'h', oils_i18n_gettext('843', 'Biography', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (844, 'cont', 'i', oils_i18n_gettext('844', 'Indexes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (845, 'cont', 'j', oils_i18n_gettext('845', 'Patent document', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (846, 'cont', 'k', oils_i18n_gettext('846', 'Discographies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (847, 'cont', 'l', oils_i18n_gettext('847', 'Legislation', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (848, 'cont', 'm', oils_i18n_gettext('848', 'Theses', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (849, 'cont', 'n', oils_i18n_gettext('849', 'Surveys of the literature in a subject area', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (850, 'cont', 'o', oils_i18n_gettext('850', 'Reviews', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (851, 'cont', 'p', oils_i18n_gettext('851', 'Programmed texts', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (852, 'cont', 'q', oils_i18n_gettext('852', 'Filmographies', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (853, 'cont', 'r', oils_i18n_gettext('853', 'Directories', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (854, 'cont', 's', oils_i18n_gettext('854', 'Statistics', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (855, 'cont', 't', oils_i18n_gettext('855', 'Technical reports', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (856, 'cont', 'u', oils_i18n_gettext('856', 'Standards/specifications', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (857, 'cont', 'v', oils_i18n_gettext('857', 'Legal cases and case notes', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (858, 'cont', 'w', oils_i18n_gettext('858', 'Law reports and digests', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (859, 'cont', 'x', oils_i18n_gettext('859', 'Other reports', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (860, 'cont', 'y', oils_i18n_gettext('860', 'Yearbooks', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (861, 'cont', 'z', oils_i18n_gettext('861', 'Treaties', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (862, 'cont', '2', oils_i18n_gettext('862', 'Offprints', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (863, 'cont', '5', oils_i18n_gettext('863', 'Calendars', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (864, 'cont', '6', oils_i18n_gettext('864', 'Comics/graphic novels', 'ccvm', 'value'));

-- Format of Music
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (865, 'fmus', ' ', oils_i18n_gettext('865', 'Information not supplied', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (866, 'fmus', 'a', oils_i18n_gettext('866', 'Full score', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (867, 'fmus', 'b', oils_i18n_gettext('867', 'Full score, miniature or study size', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (868, 'fmus', 'c', oils_i18n_gettext('868', 'Accompaniment reduced for keyboard', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (869, 'fmus', 'd', oils_i18n_gettext('869', 'Voice score with accompaniment omitted', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (870, 'fmus', 'e', oils_i18n_gettext('870', 'Condensed score or piano-conductor score', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (871, 'fmus', 'g', oils_i18n_gettext('871', 'Close score', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (872, 'fmus', 'h', oils_i18n_gettext('872', 'Chorus score', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (873, 'fmus', 'i', oils_i18n_gettext('873', 'Condensed score', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (874, 'fmus', 'j', oils_i18n_gettext('874', 'Performer-conductor part', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (875, 'fmus', 'k', oils_i18n_gettext('875', 'Vocal score', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (876, 'fmus', 'l', oils_i18n_gettext('876', 'Score', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (877, 'fmus', 'm', oils_i18n_gettext('877', 'Multiple score formats', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (878, 'fmus', 'n', oils_i18n_gettext('878', 'Not applicable', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (879, 'fmus', 'u', oils_i18n_gettext('879', 'Unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (880, 'fmus', 'z', oils_i18n_gettext('880', 'Other', 'ccvm', 'value'));

-- Literary Text for Sound Recordings
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (881, 'ltxt', ' ', oils_i18n_gettext('881', 'Item is a music sound recording', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (882, 'ltxt', 'a', oils_i18n_gettext('882', 'Autobiography', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (883, 'ltxt', 'b', oils_i18n_gettext('883', 'Biography', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (884, 'ltxt', 'c', oils_i18n_gettext('884', 'Conference proceedings', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (885, 'ltxt', 'd', oils_i18n_gettext('885', 'Drama', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (886, 'ltxt', 'e', oils_i18n_gettext('886', 'Essays', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (887, 'ltxt', 'f', oils_i18n_gettext('887', 'Fiction', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (888, 'ltxt', 'g', oils_i18n_gettext('888', 'Reporting', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (889, 'ltxt', 'h', oils_i18n_gettext('889', 'History', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (890, 'ltxt', 'i', oils_i18n_gettext('890', 'Instruction', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (891, 'ltxt', 'j', oils_i18n_gettext('891', 'Language instruction', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (892, 'ltxt', 'k', oils_i18n_gettext('892', 'Comedy', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (893, 'ltxt', 'l', oils_i18n_gettext('893', 'Lectures, speeches', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (894, 'ltxt', 'm', oils_i18n_gettext('894', 'Memoirs', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (895, 'ltxt', 'n', oils_i18n_gettext('895', 'Not applicable', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (896, 'ltxt', 'o', oils_i18n_gettext('896', 'Folktales', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (897, 'ltxt', 'p', oils_i18n_gettext('897', 'Poetry', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (898, 'ltxt', 'r', oils_i18n_gettext('898', 'Rehearsals', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (899, 'ltxt', 's', oils_i18n_gettext('899', 'Sounds', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (900, 'ltxt', 't', oils_i18n_gettext('900', 'Interviews', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (901, 'ltxt', 'z', oils_i18n_gettext('901', 'Other', 'ccvm', 'value'));

-- Form of Original Item
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (902, 'orig', ' ', oils_i18n_gettext('902', 'None of the following', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (903, 'orig', 'a', oils_i18n_gettext('903', 'Microfilm', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (904, 'orig', 'b', oils_i18n_gettext('904', 'Microfiche', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (905, 'orig', 'c', oils_i18n_gettext('905', 'Microopaque', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (906, 'orig', 'd', oils_i18n_gettext('906', 'Large print', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (907, 'orig', 'e', oils_i18n_gettext('907', 'Newspaper format', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (908, 'orig', 'f', oils_i18n_gettext('908', 'Braille', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (909, 'orig', 'o', oils_i18n_gettext('909', 'Online', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (910, 'orig', 'q', oils_i18n_gettext('910', 'Direct electronic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (911, 'orig', 's', oils_i18n_gettext('911', 'Electronic', 'ccvm', 'value'));

-- Music Parts
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (912, 'part', ' ', oils_i18n_gettext('912', 'No parts in hand or not specified', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (913, 'part', 'd', oils_i18n_gettext('913', 'Instrumental and vocal parts', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (914, 'part', 'e', oils_i18n_gettext('914', 'Instrumental parts', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (915, 'part', 'f', oils_i18n_gettext('915', 'Vocal parts', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (916, 'part', 'n', oils_i18n_gettext('916', 'Not Applicable', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (917, 'part', 'u', oils_i18n_gettext('917', 'Unknown', 'ccvm', 'value'));

-- Projection
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (918, 'proj', '  ', oils_i18n_gettext('918', 'Project not specified', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (919, 'proj', 'aa', oils_i18n_gettext('919', 'Aitoff', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (920, 'proj', 'ab', oils_i18n_gettext('920', 'Gnomic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (921, 'proj', 'ac', oils_i18n_gettext('921', 'Lambert''s azimuthal equal area', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (922, 'proj', 'ad', oils_i18n_gettext('922', 'Orthographic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (923, 'proj', 'ae', oils_i18n_gettext('923', 'Azimuthal equidistant', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (924, 'proj', 'af', oils_i18n_gettext('924', 'Stereographic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (925, 'proj', 'ag', oils_i18n_gettext('925', 'General vertical near-sided', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (926, 'proj', 'am', oils_i18n_gettext('926', 'Modified stereographic for Alaska', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (927, 'proj', 'an', oils_i18n_gettext('927', 'Chamberlin trimetric', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (928, 'proj', 'ap', oils_i18n_gettext('928', 'Polar stereographic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (929, 'proj', 'au', oils_i18n_gettext('929', 'Azimuthal, specific type unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (930, 'proj', 'az', oils_i18n_gettext('930', 'Azimuthal, other', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (931, 'proj', 'ba', oils_i18n_gettext('931', 'Gall', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (932, 'proj', 'bb', oils_i18n_gettext('932', 'Goode''s homolographic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (933, 'proj', 'bc', oils_i18n_gettext('933', 'Lambert''s cylindrical equal area', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (934, 'proj', 'bd', oils_i18n_gettext('934', 'Mercator', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (935, 'proj', 'be', oils_i18n_gettext('935', 'Miller', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (936, 'proj', 'bf', oils_i18n_gettext('936', 'Mollweide', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (937, 'proj', 'bg', oils_i18n_gettext('937', 'Sinusoidal', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (938, 'proj', 'bh', oils_i18n_gettext('938', 'Transverse Mercator', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (939, 'proj', 'bi', oils_i18n_gettext('939', 'Gauss-Kruger', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (940, 'proj', 'bj', oils_i18n_gettext('940', 'Equirectangular', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (941, 'proj', 'bk', oils_i18n_gettext('941', 'Krovak', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (942, 'proj', 'bl', oils_i18n_gettext('942', 'Cassini-Soldner', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (943, 'proj', 'bo', oils_i18n_gettext('943', 'Oblique Mercator', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (944, 'proj', 'br', oils_i18n_gettext('944', 'Robinson', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (945, 'proj', 'bs', oils_i18n_gettext('945', 'Space oblique Mercator', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (946, 'proj', 'bu', oils_i18n_gettext('946', 'Cylindrical, specific type unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (947, 'proj', 'bz', oils_i18n_gettext('947', 'Cylindrical, other', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (948, 'proj', 'ca', oils_i18n_gettext('948', 'Alber''s equal area', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (949, 'proj', 'cb', oils_i18n_gettext('949', 'Bonne', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (950, 'proj', 'cc', oils_i18n_gettext('950', 'Lambert''s conformal conic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (951, 'proj', 'ce', oils_i18n_gettext('951', 'Equidistant conic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (952, 'proj', 'cp', oils_i18n_gettext('952', 'Polyconic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (953, 'proj', 'cu', oils_i18n_gettext('953', 'Conic, specific type unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (954, 'proj', 'cz', oils_i18n_gettext('954', 'Conic, other', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (955, 'proj', 'da', oils_i18n_gettext('955', 'Armadillo', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (956, 'proj', 'db', oils_i18n_gettext('956', 'Butterfly', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (957, 'proj', 'dc', oils_i18n_gettext('957', 'Eckert', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (958, 'proj', 'dd', oils_i18n_gettext('958', 'Goode''s homolosine', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (959, 'proj', 'de', oils_i18n_gettext('959', 'Miller''s bipolar oblique conformal conic', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (960, 'proj', 'df', oils_i18n_gettext('960', 'Van Der Grinten', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (961, 'proj', 'dg', oils_i18n_gettext('961', 'Dymaxion', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (962, 'proj', 'dh', oils_i18n_gettext('962', 'Cordiform', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (963, 'proj', 'dl', oils_i18n_gettext('963', 'Lambert conformal', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (964, 'proj', 'zz', oils_i18n_gettext('964', 'Other', 'ccvm', 'value'));

-- Relief
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (965, 'relf', ' ', oils_i18n_gettext('965', 'No relief shown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (966, 'relf', 'a', oils_i18n_gettext('966', 'Contours', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (967, 'relf', 'b', oils_i18n_gettext('967', 'Shading', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (968, 'relf', 'c', oils_i18n_gettext('968', 'Gradient and bathymetric tints', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (969, 'relf', 'd', oils_i18n_gettext('969', 'Hachures', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (970, 'relf', 'e', oils_i18n_gettext('970', 'Bathymetry, soundings', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (971, 'relf', 'f', oils_i18n_gettext('971', 'Form lines', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (972, 'relf', 'g', oils_i18n_gettext('972', 'Spot heights', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (973, 'relf', 'i', oils_i18n_gettext('973', 'Pictorially', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (974, 'relf', 'j', oils_i18n_gettext('974', 'Land forms', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (975, 'relf', 'k', oils_i18n_gettext('975', 'Bathymetry, isolines', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (976, 'relf', 'm', oils_i18n_gettext('976', 'Rock drawings', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (977, 'relf', 'z', oils_i18n_gettext('977', 'Other', 'ccvm', 'value'));

-- Special Format Characteristics
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (978, 'spfm', ' ', oils_i18n_gettext('978', 'No specified special format characteristics', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (979, 'spfm', 'e', oils_i18n_gettext('979', 'Manuscript', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (980, 'spfm', 'j', oils_i18n_gettext('980', 'Picture card, post card', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (981, 'spfm', 'k', oils_i18n_gettext('981', 'Calendar', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (982, 'spfm', 'l', oils_i18n_gettext('982', 'Puzzle', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (983, 'spfm', 'n', oils_i18n_gettext('983', 'Game', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (984, 'spfm', 'o', oils_i18n_gettext('984', 'Wall map', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (985, 'spfm', 'p', oils_i18n_gettext('985', 'Playing cards', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (986, 'spfm', 'r', oils_i18n_gettext('986', 'Loose-leaf', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (987, 'spfm', 'z', oils_i18n_gettext('987', 'Other', 'ccvm', 'value'));

-- Type of Continuing Resource
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (988, 'srtp', ' ', oils_i18n_gettext('988', 'None of the following', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (989, 'srtp', 'd', oils_i18n_gettext('989', 'Updating database', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (990, 'srtp', 'l', oils_i18n_gettext('990', 'Updating loose-leaf', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (991, 'srtp', 'm', oils_i18n_gettext('991', 'Monographic series', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (992, 'srtp', 'n', oils_i18n_gettext('992', 'Newspaper', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (993, 'srtp', 'p', oils_i18n_gettext('993', 'Periodical', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (994, 'srtp', 'w', oils_i18n_gettext('994', 'Updating Web site', 'ccvm', 'value'));

-- Technique
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (995, 'tech', 'a', oils_i18n_gettext('995', 'Animation', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (996, 'tech', 'c', oils_i18n_gettext('996', 'Animation and live action', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (997, 'tech', 'l', oils_i18n_gettext('997', 'Live action', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (998, 'tech', 'n', oils_i18n_gettext('998', 'Not applicable', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (999, 'tech', 'u', oils_i18n_gettext('999', 'Unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1000, 'tech', 'z', oils_i18n_gettext('1000', 'Other', 'ccvm', 'value'));

-- Transposition and Arrangement
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1001, 'trar', ' ', oils_i18n_gettext('1001', 'Not arrangement or transposition or not specified', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1002, 'trar', 'a', oils_i18n_gettext('1002', 'Transposition', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1003, 'trar', 'b', oils_i18n_gettext('1003', 'Arrangement', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1004, 'trar', 'c', oils_i18n_gettext('1004', 'Both transposed and arranged', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1005, 'trar', 'n', oils_i18n_gettext('1005', 'Not applicable', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1006, 'trar', 'u', oils_i18n_gettext('1006', 'Unknown', 'ccvm', 'value'));

-- Country of Publication, etc.
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1007, 'ctry', 'aa ', oils_i18n_gettext('1007', 'Albania ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1008, 'ctry', 'abc', oils_i18n_gettext('1008', 'Alberta ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1009, 'ctry', 'aca', oils_i18n_gettext('1009', 'Australian Capital Territory ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1010, 'ctry', 'ae ', oils_i18n_gettext('1010', 'Algeria ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1011, 'ctry', 'af ', oils_i18n_gettext('1011', 'Afghanistan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1012, 'ctry', 'ag ', oils_i18n_gettext('1012', 'Argentina ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1013, 'ctry', 'ai ', oils_i18n_gettext('1013', 'Armenia (Republic) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1014, 'ctry', 'aj ', oils_i18n_gettext('1014', 'Azerbaijan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1015, 'ctry', 'aku', oils_i18n_gettext('1015', 'Alaska ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1016, 'ctry', 'alu', oils_i18n_gettext('1016', 'Alabama ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1017, 'ctry', 'am ', oils_i18n_gettext('1017', 'Anguilla ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1018, 'ctry', 'an ', oils_i18n_gettext('1018', 'Andorra ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1019, 'ctry', 'ao ', oils_i18n_gettext('1019', 'Angola ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1020, 'ctry', 'aq ', oils_i18n_gettext('1020', 'Antigua and Barbuda ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1021, 'ctry', 'aru', oils_i18n_gettext('1021', 'Arkansas ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1022, 'ctry', 'as ', oils_i18n_gettext('1022', 'American Samoa ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1023, 'ctry', 'at ', oils_i18n_gettext('1023', 'Australia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1024, 'ctry', 'au ', oils_i18n_gettext('1024', 'Austria ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1025, 'ctry', 'aw ', oils_i18n_gettext('1025', 'Aruba ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1026, 'ctry', 'ay ', oils_i18n_gettext('1026', 'Antarctica ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1027, 'ctry', 'azu', oils_i18n_gettext('1027', 'Arizona ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1028, 'ctry', 'ba ', oils_i18n_gettext('1028', 'Bahrain ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1029, 'ctry', 'bb ', oils_i18n_gettext('1029', 'Barbados ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1030, 'ctry', 'bcc', oils_i18n_gettext('1030', 'British Columbia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1031, 'ctry', 'bd ', oils_i18n_gettext('1031', 'Burundi ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1032, 'ctry', 'be ', oils_i18n_gettext('1032', 'Belgium ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1033, 'ctry', 'bf ', oils_i18n_gettext('1033', 'Bahamas ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1034, 'ctry', 'bg ', oils_i18n_gettext('1034', 'Bangladesh ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1035, 'ctry', 'bh ', oils_i18n_gettext('1035', 'Belize ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1036, 'ctry', 'bi ', oils_i18n_gettext('1036', 'British Indian Ocean Territory ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1037, 'ctry', 'bl ', oils_i18n_gettext('1037', 'Brazil ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1038, 'ctry', 'bm ', oils_i18n_gettext('1038', 'Bermuda Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1039, 'ctry', 'bn ', oils_i18n_gettext('1039', 'Bosnia and Herzegovina ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1040, 'ctry', 'bo ', oils_i18n_gettext('1040', 'Bolivia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1041, 'ctry', 'bp ', oils_i18n_gettext('1041', 'Solomon Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1042, 'ctry', 'br ', oils_i18n_gettext('1042', 'Burma ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1043, 'ctry', 'bs ', oils_i18n_gettext('1043', 'Botswana ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1044, 'ctry', 'bt ', oils_i18n_gettext('1044', 'Bhutan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1045, 'ctry', 'bu ', oils_i18n_gettext('1045', 'Bulgaria ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1046, 'ctry', 'bv ', oils_i18n_gettext('1046', 'Bouvet Island ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1047, 'ctry', 'bw ', oils_i18n_gettext('1047', 'Belarus ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1048, 'ctry', 'bx ', oils_i18n_gettext('1048', 'Brunei ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1049, 'ctry', 'ca ', oils_i18n_gettext('1049', 'Caribbean Netherlands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1050, 'ctry', 'cau', oils_i18n_gettext('1050', 'California ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1051, 'ctry', 'cb ', oils_i18n_gettext('1051', 'Cambodia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1052, 'ctry', 'cc ', oils_i18n_gettext('1052', 'China ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1053, 'ctry', 'cd ', oils_i18n_gettext('1053', 'Chad ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1054, 'ctry', 'ce ', oils_i18n_gettext('1054', 'Sri Lanka ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1055, 'ctry', 'cf ', oils_i18n_gettext('1055', 'Congo (Brazzaville) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1056, 'ctry', 'cg ', oils_i18n_gettext('1056', 'Congo (Democratic Republic) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1057, 'ctry', 'ch ', oils_i18n_gettext('1057', 'China (Republic : 1949', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1058, 'ctry', 'ci ', oils_i18n_gettext('1058', 'Croatia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1059, 'ctry', 'cj ', oils_i18n_gettext('1059', 'Cayman Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1060, 'ctry', 'ck ', oils_i18n_gettext('1060', 'Colombia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1061, 'ctry', 'cl ', oils_i18n_gettext('1061', 'Chile ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1062, 'ctry', 'cm ', oils_i18n_gettext('1062', 'Cameroon ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1063, 'ctry', 'co ', oils_i18n_gettext('1063', 'Curaçao ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1064, 'ctry', 'cou', oils_i18n_gettext('1064', 'Colorado ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1065, 'ctry', 'cq ', oils_i18n_gettext('1065', 'Comoros ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1066, 'ctry', 'cr ', oils_i18n_gettext('1066', 'Costa Rica ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1067, 'ctry', 'ctu', oils_i18n_gettext('1067', 'Connecticut ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1068, 'ctry', 'cu ', oils_i18n_gettext('1068', 'Cuba ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1069, 'ctry', 'cv ', oils_i18n_gettext('1069', 'Cabo Verde ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1070, 'ctry', 'cw ', oils_i18n_gettext('1070', 'Cook Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1071, 'ctry', 'cx ', oils_i18n_gettext('1071', 'Central African Republic ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1072, 'ctry', 'cy ', oils_i18n_gettext('1072', 'Cyprus ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1073, 'ctry', 'dcu', oils_i18n_gettext('1073', 'District of Columbia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1074, 'ctry', 'deu', oils_i18n_gettext('1074', 'Delaware ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1075, 'ctry', 'dk ', oils_i18n_gettext('1075', 'Denmark ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1076, 'ctry', 'dm ', oils_i18n_gettext('1076', 'Benin ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1077, 'ctry', 'dq ', oils_i18n_gettext('1077', 'Dominica ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1078, 'ctry', 'dr ', oils_i18n_gettext('1078', 'Dominican Republic ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1079, 'ctry', 'ea ', oils_i18n_gettext('1079', 'Eritrea ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1080, 'ctry', 'ec ', oils_i18n_gettext('1080', 'Ecuador ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1081, 'ctry', 'eg ', oils_i18n_gettext('1081', 'Equatorial Guinea ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1082, 'ctry', 'em ', oils_i18n_gettext('1082', 'Timor', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1083, 'ctry', 'enk', oils_i18n_gettext('1083', 'England ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1084, 'ctry', 'er ', oils_i18n_gettext('1084', 'Estonia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1085, 'ctry', 'es ', oils_i18n_gettext('1085', 'El Salvador ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1086, 'ctry', 'et ', oils_i18n_gettext('1086', 'Ethiopia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1087, 'ctry', 'fa ', oils_i18n_gettext('1087', 'Faroe Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1088, 'ctry', 'fg ', oils_i18n_gettext('1088', 'French Guiana ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1089, 'ctry', 'fi ', oils_i18n_gettext('1089', 'Finland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1090, 'ctry', 'fj ', oils_i18n_gettext('1090', 'Fiji ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1091, 'ctry', 'fk ', oils_i18n_gettext('1091', 'Falkland Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1092, 'ctry', 'flu', oils_i18n_gettext('1092', 'Florida ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1093, 'ctry', 'fm ', oils_i18n_gettext('1093', 'Micronesia (Federated States) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1094, 'ctry', 'fp ', oils_i18n_gettext('1094', 'French Polynesia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1095, 'ctry', 'fr ', oils_i18n_gettext('1095', 'France ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1096, 'ctry', 'fs ', oils_i18n_gettext('1096', 'Terres australes et antarctiques françaises ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1097, 'ctry', 'ft ', oils_i18n_gettext('1097', 'Djibouti ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1098, 'ctry', 'gau', oils_i18n_gettext('1098', 'Georgia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1099, 'ctry', 'gb ', oils_i18n_gettext('1099', 'Kiribati ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1100, 'ctry', 'gd ', oils_i18n_gettext('1100', 'Grenada ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1101, 'ctry', 'gh ', oils_i18n_gettext('1101', 'Ghana ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1102, 'ctry', 'gi ', oils_i18n_gettext('1102', 'Gibraltar ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1103, 'ctry', 'gl ', oils_i18n_gettext('1103', 'Greenland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1104, 'ctry', 'gm ', oils_i18n_gettext('1104', 'Gambia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1105, 'ctry', 'go ', oils_i18n_gettext('1105', 'Gabon ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1106, 'ctry', 'gp ', oils_i18n_gettext('1106', 'Guadeloupe ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1107, 'ctry', 'gr ', oils_i18n_gettext('1107', 'Greece ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1108, 'ctry', 'gs ', oils_i18n_gettext('1108', 'Georgia (Republic) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1109, 'ctry', 'gt ', oils_i18n_gettext('1109', 'Guatemala ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1110, 'ctry', 'gu ', oils_i18n_gettext('1110', 'Guam ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1111, 'ctry', 'gv ', oils_i18n_gettext('1111', 'Guinea ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1112, 'ctry', 'gw ', oils_i18n_gettext('1112', 'Germany ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1113, 'ctry', 'gy ', oils_i18n_gettext('1113', 'Guyana ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1114, 'ctry', 'gz ', oils_i18n_gettext('1114', 'Gaza Strip ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1115, 'ctry', 'hiu', oils_i18n_gettext('1115', 'Hawaii ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1116, 'ctry', 'hm ', oils_i18n_gettext('1116', 'Heard and McDonald Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1117, 'ctry', 'ho ', oils_i18n_gettext('1117', 'Honduras ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1118, 'ctry', 'ht ', oils_i18n_gettext('1118', 'Haiti ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1119, 'ctry', 'hu ', oils_i18n_gettext('1119', 'Hungary ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1120, 'ctry', 'iau', oils_i18n_gettext('1120', 'Iowa ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1121, 'ctry', 'ic ', oils_i18n_gettext('1121', 'Iceland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1122, 'ctry', 'idu', oils_i18n_gettext('1122', 'Idaho ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1123, 'ctry', 'ie ', oils_i18n_gettext('1123', 'Ireland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1124, 'ctry', 'ii ', oils_i18n_gettext('1124', 'India ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1125, 'ctry', 'ilu', oils_i18n_gettext('1125', 'Illinois ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1126, 'ctry', 'inu', oils_i18n_gettext('1126', 'Indiana ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1127, 'ctry', 'io ', oils_i18n_gettext('1127', 'Indonesia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1128, 'ctry', 'iq ', oils_i18n_gettext('1128', 'Iraq ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1129, 'ctry', 'ir ', oils_i18n_gettext('1129', 'Iran ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1130, 'ctry', 'is ', oils_i18n_gettext('1130', 'Israel ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1131, 'ctry', 'it ', oils_i18n_gettext('1131', 'Italy ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1132, 'ctry', 'iv ', oils_i18n_gettext('1132', 'Côte d''Ivoire ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1133, 'ctry', 'iy ', oils_i18n_gettext('1133', 'Iraq', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1134, 'ctry', 'ja ', oils_i18n_gettext('1134', 'Japan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1135, 'ctry', 'ji ', oils_i18n_gettext('1135', 'Johnston Atoll ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1136, 'ctry', 'jm ', oils_i18n_gettext('1136', 'Jamaica ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1137, 'ctry', 'jo ', oils_i18n_gettext('1137', 'Jordan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1138, 'ctry', 'ke ', oils_i18n_gettext('1138', 'Kenya ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1139, 'ctry', 'kg ', oils_i18n_gettext('1139', 'Kyrgyzstan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1140, 'ctry', 'kn ', oils_i18n_gettext('1140', 'Korea (North) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1141, 'ctry', 'ko ', oils_i18n_gettext('1141', 'Korea (South) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1142, 'ctry', 'ksu', oils_i18n_gettext('1142', 'Kansas ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1143, 'ctry', 'ku ', oils_i18n_gettext('1143', 'Kuwait ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1144, 'ctry', 'kv ', oils_i18n_gettext('1144', 'Kosovo ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1145, 'ctry', 'kyu', oils_i18n_gettext('1145', 'Kentucky ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1146, 'ctry', 'kz ', oils_i18n_gettext('1146', 'Kazakhstan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1147, 'ctry', 'lau', oils_i18n_gettext('1147', 'Louisiana ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1148, 'ctry', 'lb ', oils_i18n_gettext('1148', 'Liberia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1149, 'ctry', 'le ', oils_i18n_gettext('1149', 'Lebanon ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1150, 'ctry', 'lh ', oils_i18n_gettext('1150', 'Liechtenstein ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1151, 'ctry', 'li ', oils_i18n_gettext('1151', 'Lithuania ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1152, 'ctry', 'lo ', oils_i18n_gettext('1152', 'Lesotho ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1153, 'ctry', 'ls ', oils_i18n_gettext('1153', 'Laos ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1154, 'ctry', 'lu ', oils_i18n_gettext('1154', 'Luxembourg ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1155, 'ctry', 'lv ', oils_i18n_gettext('1155', 'Latvia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1156, 'ctry', 'ly ', oils_i18n_gettext('1156', 'Libya ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1157, 'ctry', 'mau', oils_i18n_gettext('1157', 'Massachusetts ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1158, 'ctry', 'mbc', oils_i18n_gettext('1158', 'Manitoba ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1159, 'ctry', 'mc ', oils_i18n_gettext('1159', 'Monaco ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1160, 'ctry', 'mdu', oils_i18n_gettext('1160', 'Maryland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1161, 'ctry', 'meu', oils_i18n_gettext('1161', 'Maine ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1162, 'ctry', 'mf ', oils_i18n_gettext('1162', 'Mauritius ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1163, 'ctry', 'mg ', oils_i18n_gettext('1163', 'Madagascar ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1164, 'ctry', 'miu', oils_i18n_gettext('1164', 'Michigan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1165, 'ctry', 'mj ', oils_i18n_gettext('1165', 'Montserrat ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1166, 'ctry', 'mk ', oils_i18n_gettext('1166', 'Oman ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1167, 'ctry', 'ml ', oils_i18n_gettext('1167', 'Mali ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1168, 'ctry', 'mm ', oils_i18n_gettext('1168', 'Malta ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1169, 'ctry', 'mnu', oils_i18n_gettext('1169', 'Minnesota ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1170, 'ctry', 'mo ', oils_i18n_gettext('1170', 'Montenegro ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1171, 'ctry', 'mou', oils_i18n_gettext('1171', 'Missouri ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1172, 'ctry', 'mp ', oils_i18n_gettext('1172', 'Mongolia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1173, 'ctry', 'mq ', oils_i18n_gettext('1173', 'Martinique ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1174, 'ctry', 'mr ', oils_i18n_gettext('1174', 'Morocco ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1175, 'ctry', 'msu', oils_i18n_gettext('1175', 'Mississippi ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1176, 'ctry', 'mtu', oils_i18n_gettext('1176', 'Montana ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1177, 'ctry', 'mu ', oils_i18n_gettext('1177', 'Mauritania ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1178, 'ctry', 'mv ', oils_i18n_gettext('1178', 'Moldova ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1179, 'ctry', 'mw ', oils_i18n_gettext('1179', 'Malawi ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1180, 'ctry', 'mx ', oils_i18n_gettext('1180', 'Mexico ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1181, 'ctry', 'my ', oils_i18n_gettext('1181', 'Malaysia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1182, 'ctry', 'mz ', oils_i18n_gettext('1182', 'Mozambique ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1183, 'ctry', 'nbu', oils_i18n_gettext('1183', 'Nebraska ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1184, 'ctry', 'ncu', oils_i18n_gettext('1184', 'North Carolina ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1185, 'ctry', 'ndu', oils_i18n_gettext('1185', 'North Dakota ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1186, 'ctry', 'ne ', oils_i18n_gettext('1186', 'Netherlands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1187, 'ctry', 'nfc', oils_i18n_gettext('1187', 'Newfoundland and Labrador ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1188, 'ctry', 'ng ', oils_i18n_gettext('1188', 'Niger ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1189, 'ctry', 'nhu', oils_i18n_gettext('1189', 'New Hampshire ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1190, 'ctry', 'nik', oils_i18n_gettext('1190', 'Northern Ireland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1191, 'ctry', 'nju', oils_i18n_gettext('1191', 'New Jersey ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1192, 'ctry', 'nkc', oils_i18n_gettext('1192', 'New Brunswick ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1193, 'ctry', 'nl ', oils_i18n_gettext('1193', 'New Caledonia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1194, 'ctry', 'nmu', oils_i18n_gettext('1194', 'New Mexico ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1195, 'ctry', 'nn ', oils_i18n_gettext('1195', 'Vanuatu ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1196, 'ctry', 'no ', oils_i18n_gettext('1196', 'Norway ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1197, 'ctry', 'np ', oils_i18n_gettext('1197', 'Nepal ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1198, 'ctry', 'nq ', oils_i18n_gettext('1198', 'Nicaragua ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1199, 'ctry', 'nr ', oils_i18n_gettext('1199', 'Nigeria ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1200, 'ctry', 'nsc', oils_i18n_gettext('1200', 'Nova Scotia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1201, 'ctry', 'ntc', oils_i18n_gettext('1201', 'Northwest Territories ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1202, 'ctry', 'nu ', oils_i18n_gettext('1202', 'Nauru ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1203, 'ctry', 'nuc', oils_i18n_gettext('1203', 'Nunavut ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1204, 'ctry', 'nvu', oils_i18n_gettext('1204', 'Nevada ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1205, 'ctry', 'nw ', oils_i18n_gettext('1205', 'Northern Mariana Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1206, 'ctry', 'nx ', oils_i18n_gettext('1206', 'Norfolk Island ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1207, 'ctry', 'nyu', oils_i18n_gettext('1207', 'New York (State) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1208, 'ctry', 'nz ', oils_i18n_gettext('1208', 'New Zealand ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1209, 'ctry', 'ohu', oils_i18n_gettext('1209', 'Ohio ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1210, 'ctry', 'oku', oils_i18n_gettext('1210', 'Oklahoma ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1211, 'ctry', 'onc', oils_i18n_gettext('1211', 'Ontario ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1212, 'ctry', 'oru', oils_i18n_gettext('1212', 'Oregon ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1213, 'ctry', 'ot ', oils_i18n_gettext('1213', 'Mayotte ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1214, 'ctry', 'pau', oils_i18n_gettext('1214', 'Pennsylvania ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1215, 'ctry', 'pc ', oils_i18n_gettext('1215', 'Pitcairn Island ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1216, 'ctry', 'pe ', oils_i18n_gettext('1216', 'Peru ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1217, 'ctry', 'pf ', oils_i18n_gettext('1217', 'Paracel Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1218, 'ctry', 'pg ', oils_i18n_gettext('1218', 'Guinea', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1219, 'ctry', 'ph ', oils_i18n_gettext('1219', 'Philippines ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1220, 'ctry', 'pic', oils_i18n_gettext('1220', 'Prince Edward Island ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1221, 'ctry', 'pk ', oils_i18n_gettext('1221', 'Pakistan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1222, 'ctry', 'pl ', oils_i18n_gettext('1222', 'Poland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1223, 'ctry', 'pn ', oils_i18n_gettext('1223', 'Panama ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1224, 'ctry', 'po ', oils_i18n_gettext('1224', 'Portugal ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1225, 'ctry', 'pp ', oils_i18n_gettext('1225', 'Papua New Guinea ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1226, 'ctry', 'pr ', oils_i18n_gettext('1226', 'Puerto Rico ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1227, 'ctry', 'pw ', oils_i18n_gettext('1227', 'Palau ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1228, 'ctry', 'py ', oils_i18n_gettext('1228', 'Paraguay ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1229, 'ctry', 'qa ', oils_i18n_gettext('1229', 'Qatar ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1230, 'ctry', 'qea', oils_i18n_gettext('1230', 'Queensland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1231, 'ctry', 'quc', oils_i18n_gettext('1231', 'Québec (Province) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1232, 'ctry', 'rb ', oils_i18n_gettext('1232', 'Serbia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1233, 'ctry', 're ', oils_i18n_gettext('1233', 'Réunion ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1234, 'ctry', 'rh ', oils_i18n_gettext('1234', 'Zimbabwe ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1235, 'ctry', 'riu', oils_i18n_gettext('1235', 'Rhode Island ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1236, 'ctry', 'rm ', oils_i18n_gettext('1236', 'Romania ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1237, 'ctry', 'ru ', oils_i18n_gettext('1237', 'Russia (Federation) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1238, 'ctry', 'rw ', oils_i18n_gettext('1238', 'Rwanda ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1239, 'ctry', 'sa ', oils_i18n_gettext('1239', 'South Africa ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1240, 'ctry', 'sc ', oils_i18n_gettext('1240', 'Saint', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1241, 'ctry', 'scu', oils_i18n_gettext('1241', 'South Carolina ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1242, 'ctry', 'sd ', oils_i18n_gettext('1242', 'South Sudan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1243, 'ctry', 'sdu', oils_i18n_gettext('1243', 'South Dakota ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1244, 'ctry', 'se ', oils_i18n_gettext('1244', 'Seychelles ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1245, 'ctry', 'sf ', oils_i18n_gettext('1245', 'Sao Tome and Principe ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1246, 'ctry', 'sg ', oils_i18n_gettext('1246', 'Senegal ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1247, 'ctry', 'sh ', oils_i18n_gettext('1247', 'Spanish North Africa ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1248, 'ctry', 'si ', oils_i18n_gettext('1248', 'Singapore ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1249, 'ctry', 'sj ', oils_i18n_gettext('1249', 'Sudan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1250, 'ctry', 'sl ', oils_i18n_gettext('1250', 'Sierra Leone ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1251, 'ctry', 'sm ', oils_i18n_gettext('1251', 'San Marino ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1252, 'ctry', 'sn ', oils_i18n_gettext('1252', 'Sint Maarten ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1253, 'ctry', 'snc', oils_i18n_gettext('1253', 'Saskatchewan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1254, 'ctry', 'so ', oils_i18n_gettext('1254', 'Somalia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1255, 'ctry', 'sp ', oils_i18n_gettext('1255', 'Spain ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1256, 'ctry', 'sq ', oils_i18n_gettext('1256', 'Swaziland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1257, 'ctry', 'sr ', oils_i18n_gettext('1257', 'Surinam ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1258, 'ctry', 'ss ', oils_i18n_gettext('1258', 'Western Sahara ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1259, 'ctry', 'st ', oils_i18n_gettext('1259', 'Saint', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1260, 'ctry', 'stk', oils_i18n_gettext('1260', 'Scotland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1261, 'ctry', 'su ', oils_i18n_gettext('1261', 'Saudi Arabia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1262, 'ctry', 'sw ', oils_i18n_gettext('1262', 'Sweden ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1263, 'ctry', 'sx ', oils_i18n_gettext('1263', 'Namibia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1264, 'ctry', 'sy ', oils_i18n_gettext('1264', 'Syria ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1265, 'ctry', 'sz ', oils_i18n_gettext('1265', 'Switzerland ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1266, 'ctry', 'ta ', oils_i18n_gettext('1266', 'Tajikistan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1267, 'ctry', 'tc ', oils_i18n_gettext('1267', 'Turks and Caicos Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1268, 'ctry', 'tg ', oils_i18n_gettext('1268', 'Togo ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1269, 'ctry', 'th ', oils_i18n_gettext('1269', 'Thailand ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1270, 'ctry', 'ti ', oils_i18n_gettext('1270', 'Tunisia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1271, 'ctry', 'tk ', oils_i18n_gettext('1271', 'Turkmenistan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1272, 'ctry', 'tl ', oils_i18n_gettext('1272', 'Tokelau ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1273, 'ctry', 'tma', oils_i18n_gettext('1273', 'Tasmania ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1274, 'ctry', 'tnu', oils_i18n_gettext('1274', 'Tennessee ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1275, 'ctry', 'to ', oils_i18n_gettext('1275', 'Tonga ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1276, 'ctry', 'tr ', oils_i18n_gettext('1276', 'Trinidad and Tobago ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1277, 'ctry', 'ts ', oils_i18n_gettext('1277', 'United Arab Emirates ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1278, 'ctry', 'tu ', oils_i18n_gettext('1278', 'Turkey ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1279, 'ctry', 'tv ', oils_i18n_gettext('1279', 'Tuvalu ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1280, 'ctry', 'txu', oils_i18n_gettext('1280', 'Texas ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1281, 'ctry', 'tz ', oils_i18n_gettext('1281', 'Tanzania ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1282, 'ctry', 'ua ', oils_i18n_gettext('1282', 'Egypt ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1283, 'ctry', 'uc ', oils_i18n_gettext('1283', 'United States Misc. Caribbean Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1284, 'ctry', 'ug ', oils_i18n_gettext('1284', 'Uganda ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1285, 'ctry', 'uik', oils_i18n_gettext('1285', 'United Kingdom Misc. Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1286, 'ctry', 'un ', oils_i18n_gettext('1286', 'Ukraine ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1287, 'ctry', 'up ', oils_i18n_gettext('1287', 'United States Misc. Pacific Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1288, 'ctry', 'utu', oils_i18n_gettext('1288', 'Utah ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1289, 'ctry', 'uv ', oils_i18n_gettext('1289', 'Burkina Faso ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1290, 'ctry', 'uy ', oils_i18n_gettext('1290', 'Uruguay ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1291, 'ctry', 'uz ', oils_i18n_gettext('1291', 'Uzbekistan ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1292, 'ctry', 'vau', oils_i18n_gettext('1292', 'Virginia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1293, 'ctry', 'vb ', oils_i18n_gettext('1293', 'British Virgin Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1294, 'ctry', 'vc ', oils_i18n_gettext('1294', 'Vatican City ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1295, 'ctry', 've ', oils_i18n_gettext('1295', 'Venezuela ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1296, 'ctry', 'vi ', oils_i18n_gettext('1296', 'Virgin Islands of the United States ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1297, 'ctry', 'vm ', oils_i18n_gettext('1297', 'Vietnam ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1298, 'ctry', 'vp ', oils_i18n_gettext('1298', 'Various places ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1299, 'ctry', 'vra', oils_i18n_gettext('1299', 'Victoria ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1300, 'ctry', 'vtu', oils_i18n_gettext('1300', 'Vermont ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1301, 'ctry', 'wau', oils_i18n_gettext('1301', 'Washington (State) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1302, 'ctry', 'wea', oils_i18n_gettext('1302', 'Western Australia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1303, 'ctry', 'wf ', oils_i18n_gettext('1303', 'Wallis and Futuna ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1304, 'ctry', 'wiu', oils_i18n_gettext('1304', 'Wisconsin ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1305, 'ctry', 'wj ', oils_i18n_gettext('1305', 'West Bank of the Jordan River ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1306, 'ctry', 'wk ', oils_i18n_gettext('1306', 'Wake Island ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1307, 'ctry', 'wlk', oils_i18n_gettext('1307', 'Wales ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1308, 'ctry', 'ws ', oils_i18n_gettext('1308', 'Samoa ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1309, 'ctry', 'wvu', oils_i18n_gettext('1309', 'West Virginia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1310, 'ctry', 'wyu', oils_i18n_gettext('1310', 'Wyoming ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1311, 'ctry', 'xa ', oils_i18n_gettext('1311', 'Christmas Island (Indian Ocean) ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1312, 'ctry', 'xb ', oils_i18n_gettext('1312', 'Cocos (Keeling) Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1313, 'ctry', 'xc ', oils_i18n_gettext('1313', 'Maldives ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1314, 'ctry', 'xd ', oils_i18n_gettext('1314', 'Saint Kitts', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1315, 'ctry', 'xe ', oils_i18n_gettext('1315', 'Marshall Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1316, 'ctry', 'xf ', oils_i18n_gettext('1316', 'Midway Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1317, 'ctry', 'xga', oils_i18n_gettext('1317', 'Coral Sea Islands Territory ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1318, 'ctry', 'xh ', oils_i18n_gettext('1318', 'Niue ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1319, 'ctry', 'xj ', oils_i18n_gettext('1319', 'Saint Helena ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1320, 'ctry', 'xk ', oils_i18n_gettext('1320', 'Saint Lucia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1321, 'ctry', 'xl ', oils_i18n_gettext('1321', 'Saint Pierre and Miquelon ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1322, 'ctry', 'xm ', oils_i18n_gettext('1322', 'Saint Vincent and the Grenadines ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1323, 'ctry', 'xn ', oils_i18n_gettext('1323', 'Macedonia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1324, 'ctry', 'xna', oils_i18n_gettext('1324', 'New South Wales ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1325, 'ctry', 'xo ', oils_i18n_gettext('1325', 'Slovakia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1326, 'ctry', 'xoa', oils_i18n_gettext('1326', 'Northern Territory ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1327, 'ctry', 'xp ', oils_i18n_gettext('1327', 'Spratly Island ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1328, 'ctry', 'xr ', oils_i18n_gettext('1328', 'Czech Republic ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1329, 'ctry', 'xra', oils_i18n_gettext('1329', 'South Australia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1330, 'ctry', 'xs ', oils_i18n_gettext('1330', 'South Georgia and the South Sandwich Islands ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1331, 'ctry', 'xv ', oils_i18n_gettext('1331', 'Slovenia ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1332, 'ctry', 'xx ', oils_i18n_gettext('1332', 'No place, unknown, or undetermined ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1333, 'ctry', 'xxc', oils_i18n_gettext('1333', 'Canada ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1334, 'ctry', 'xxk', oils_i18n_gettext('1334', 'United Kingdom ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1335, 'ctry', 'xxu', oils_i18n_gettext('1335', 'United States ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1336, 'ctry', 'ye ', oils_i18n_gettext('1336', 'Yemen ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1337, 'ctry', 'ykc', oils_i18n_gettext('1337', 'Yukon Territory ', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1338, 'ctry', 'za ', oils_i18n_gettext('1338', 'Zambia ', 'ccvm', 'value'));

-- Type of Date/Publication Status
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1339, 'pub_status', 'b', oils_i18n_gettext('1339', 'No dates given; B.C. date involved', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1340, 'pub_status', 'c', oils_i18n_gettext('1340', 'Continuing resource currently published', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1341, 'pub_status', 'd', oils_i18n_gettext('1341', 'Continuing resource ceased publication', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1342, 'pub_status', 'e', oils_i18n_gettext('1342', 'Detailed date', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1343, 'pub_status', 'i', oils_i18n_gettext('1343', 'Inclusive dates of collection', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1344, 'pub_status', 'k', oils_i18n_gettext('1344', 'Range of years of bulk of collection', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1345, 'pub_status', 'm', oils_i18n_gettext('1345', 'Multiple dates', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1346, 'pub_status', 'n', oils_i18n_gettext('1346', 'Dates unknown', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1347, 'pub_status', 'p', oils_i18n_gettext('1347', 'Date of distribution/release/issue and production/recording session when different', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1348, 'pub_status', 'q', oils_i18n_gettext('1348', 'Questionable date', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1349, 'pub_status', 'r', oils_i18n_gettext('1349', 'Reprint/reissue date and original date', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1350, 'pub_status', 's', oils_i18n_gettext('1350', 'Single known date/probable date', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1351, 'pub_status', 't', oils_i18n_gettext('1351', 'Publication date and copyright date', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1352, 'pub_status', 'u', oils_i18n_gettext('1352', 'Continuing resource status unknown', 'ccvm', 'value'));


-- These are fixed fields that are made up of multiple single-character codes. These are the actual fields used for the individual positions,
-- the "unnumbered" version of these fields are used for the MARC editor and as composite attributes for use in the OPAC if desired.
-- i18n ids are left as-is because they are exactly the same value.
-- The ' ' codes only apply to the first position because if there's anything in pos 1 then additional spaces are just filler.
-- There's also no need for them to be opac visible because there are composite attributes that OR these numbered attributes together.
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1353, 'accm1', ' ', oils_i18n_gettext('1353', 'No accompanying matter', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1354, 'accm1', 'a', oils_i18n_gettext('1354', 'Discography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1355, 'accm1', 'b', oils_i18n_gettext('1355', 'Bibliography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1356, 'accm1', 'c', oils_i18n_gettext('1356', 'Thematic index', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1357, 'accm1', 'd', oils_i18n_gettext('1357', 'Libretto or text', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1358, 'accm1', 'e', oils_i18n_gettext('1358', 'Biography of composer or author', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1359, 'accm1', 'f', oils_i18n_gettext('1359', 'Biography or performer or history of ensemble', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1360, 'accm1', 'g', oils_i18n_gettext('1360', 'Technical and/or historical information on instruments', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1361, 'accm1', 'h', oils_i18n_gettext('1361', 'Technical information on music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1362, 'accm1', 'i', oils_i18n_gettext('1362', 'Historical information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1363, 'accm1', 'k', oils_i18n_gettext('1363', 'Ethnological information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1364, 'accm1', 'r', oils_i18n_gettext('1364', 'Instructional materials', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1365, 'accm1', 's', oils_i18n_gettext('1365', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1366, 'accm1', 'z', oils_i18n_gettext('1366', 'Other accompanying matter', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1367, 'accm2', 'a', oils_i18n_gettext('1367', 'Discography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1368, 'accm2', 'b', oils_i18n_gettext('1368', 'Bibliography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1369, 'accm2', 'c', oils_i18n_gettext('1369', 'Thematic index', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1370, 'accm2', 'd', oils_i18n_gettext('1370', 'Libretto or text', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1371, 'accm2', 'e', oils_i18n_gettext('1371', 'Biography of composer or author', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1372, 'accm2', 'f', oils_i18n_gettext('1372', 'Biography or performer or history of ensemble', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1373, 'accm2', 'g', oils_i18n_gettext('1373', 'Technical and/or historical information on instruments', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1374, 'accm2', 'h', oils_i18n_gettext('1374', 'Technical information on music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1375, 'accm2', 'i', oils_i18n_gettext('1375', 'Historical information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1376, 'accm2', 'k', oils_i18n_gettext('1376', 'Ethnological information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1377, 'accm2', 'r', oils_i18n_gettext('1377', 'Instructional materials', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1378, 'accm2', 's', oils_i18n_gettext('1378', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1379, 'accm2', 'z', oils_i18n_gettext('1379', 'Other accompanying matter', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1380, 'accm3', 'a', oils_i18n_gettext('1380', 'Discography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1381, 'accm3', 'b', oils_i18n_gettext('1381', 'Bibliography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1382, 'accm3', 'c', oils_i18n_gettext('1382', 'Thematic index', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1383, 'accm3', 'd', oils_i18n_gettext('1383', 'Libretto or text', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1384, 'accm3', 'e', oils_i18n_gettext('1384', 'Biography of composer or author', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1385, 'accm3', 'f', oils_i18n_gettext('1385', 'Biography or performer or history of ensemble', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1386, 'accm3', 'g', oils_i18n_gettext('1386', 'Technical and/or historical information on instruments', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1387, 'accm3', 'h', oils_i18n_gettext('1387', 'Technical information on music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1388, 'accm3', 'i', oils_i18n_gettext('1388', 'Historical information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1389, 'accm3', 'k', oils_i18n_gettext('1389', 'Ethnological information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1390, 'accm3', 'r', oils_i18n_gettext('1390', 'Instructional materials', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1391, 'accm3', 's', oils_i18n_gettext('1391', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1392, 'accm3', 'z', oils_i18n_gettext('1392', 'Other accompanying matter', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1393, 'accm4', 'a', oils_i18n_gettext('1393', 'Discography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1394, 'accm4', 'b', oils_i18n_gettext('1394', 'Bibliography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1395, 'accm4', 'c', oils_i18n_gettext('1395', 'Thematic index', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1396, 'accm4', 'd', oils_i18n_gettext('1396', 'Libretto or text', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1397, 'accm4', 'e', oils_i18n_gettext('1397', 'Biography of composer or author', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1398, 'accm4', 'f', oils_i18n_gettext('1398', 'Biography or performer or history of ensemble', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1399, 'accm4', 'g', oils_i18n_gettext('1399', 'Technical and/or historical information on instruments', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1400, 'accm4', 'h', oils_i18n_gettext('1400', 'Technical information on music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1401, 'accm4', 'i', oils_i18n_gettext('1401', 'Historical information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1402, 'accm4', 'k', oils_i18n_gettext('1402', 'Ethnological information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1403, 'accm4', 'r', oils_i18n_gettext('1403', 'Instructional materials', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1404, 'accm4', 's', oils_i18n_gettext('1404', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1405, 'accm4', 'z', oils_i18n_gettext('1405', 'Other accompanying matter', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1406, 'accm5', 'a', oils_i18n_gettext('1406', 'Discography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1407, 'accm5', 'b', oils_i18n_gettext('1407', 'Bibliography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1408, 'accm5', 'c', oils_i18n_gettext('1408', 'Thematic index', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1409, 'accm5', 'd', oils_i18n_gettext('1409', 'Libretto or text', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1410, 'accm5', 'e', oils_i18n_gettext('1410', 'Biography of composer or author', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1411, 'accm5', 'f', oils_i18n_gettext('1411', 'Biography or performer or history of ensemble', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1412, 'accm5', 'g', oils_i18n_gettext('1412', 'Technical and/or historical information on instruments', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1413, 'accm5', 'h', oils_i18n_gettext('1413', 'Technical information on music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1414, 'accm5', 'i', oils_i18n_gettext('1414', 'Historical information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1415, 'accm5', 'k', oils_i18n_gettext('1415', 'Ethnological information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1416, 'accm5', 'r', oils_i18n_gettext('1416', 'Instructional materials', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1417, 'accm5', 's', oils_i18n_gettext('1417', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1418, 'accm5', 'z', oils_i18n_gettext('1418', 'Other accompanying matter', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1419, 'accm6', 'a', oils_i18n_gettext('1419', 'Discography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1420, 'accm6', 'b', oils_i18n_gettext('1420', 'Bibliography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1421, 'accm6', 'c', oils_i18n_gettext('1421', 'Thematic index', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1422, 'accm6', 'd', oils_i18n_gettext('1422', 'Libretto or text', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1423, 'accm6', 'e', oils_i18n_gettext('1423', 'Biography of composer or author', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1424, 'accm6', 'f', oils_i18n_gettext('1424', 'Biography or performer or history of ensemble', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1425, 'accm6', 'g', oils_i18n_gettext('1425', 'Technical and/or historical information on instruments', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1426, 'accm6', 'h', oils_i18n_gettext('1426', 'Technical information on music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1427, 'accm6', 'i', oils_i18n_gettext('1427', 'Historical information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1428, 'accm6', 'k', oils_i18n_gettext('1428', 'Ethnological information', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1429, 'accm6', 'r', oils_i18n_gettext('1429', 'Instructional materials', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1430, 'accm6', 's', oils_i18n_gettext('1430', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1431, 'accm6', 'z', oils_i18n_gettext('1431', 'Other accompanying matter', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1432, 'cont1', ' ', oils_i18n_gettext('1432', 'Not specified', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1433, 'cont1', 'a', oils_i18n_gettext('1433', 'Abstracts/summaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1434, 'cont1', 'b', oils_i18n_gettext('1434', 'Bibliographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1435, 'cont1', 'c', oils_i18n_gettext('1435', 'Catalogs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1436, 'cont1', 'd', oils_i18n_gettext('1436', 'Dictionaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1437, 'cont1', 'e', oils_i18n_gettext('1437', 'Encyclopedias', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1438, 'cont1', 'f', oils_i18n_gettext('1438', 'Handbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1439, 'cont1', 'g', oils_i18n_gettext('1439', 'Legal articles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1440, 'cont1', 'h', oils_i18n_gettext('1440', 'Biography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1441, 'cont1', 'i', oils_i18n_gettext('1441', 'Indexes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1442, 'cont1', 'j', oils_i18n_gettext('1442', 'Patent document', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1443, 'cont1', 'k', oils_i18n_gettext('1443', 'Discographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1444, 'cont1', 'l', oils_i18n_gettext('1444', 'Legislation', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1445, 'cont1', 'm', oils_i18n_gettext('1445', 'Theses', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1446, 'cont1', 'n', oils_i18n_gettext('1446', 'Surveys of the literature in a subject area', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1447, 'cont1', 'o', oils_i18n_gettext('1447', 'Reviews', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1448, 'cont1', 'p', oils_i18n_gettext('1448', 'Programmed texts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1449, 'cont1', 'q', oils_i18n_gettext('1449', 'Filmographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1450, 'cont1', 'r', oils_i18n_gettext('1450', 'Directories', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1451, 'cont1', 's', oils_i18n_gettext('1451', 'Statistics', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1452, 'cont1', 't', oils_i18n_gettext('1452', 'Technical reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1453, 'cont1', 'u', oils_i18n_gettext('1453', 'Standards/specifications', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1454, 'cont1', 'v', oils_i18n_gettext('1454', 'Legal cases and case notes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1455, 'cont1', 'w', oils_i18n_gettext('1455', 'Law reports and digests', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1456, 'cont1', 'x', oils_i18n_gettext('1456', 'Other reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1457, 'cont1', 'y', oils_i18n_gettext('1457', 'Yearbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1458, 'cont1', 'z', oils_i18n_gettext('1458', 'Treaties', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1459, 'cont1', '2', oils_i18n_gettext('1459', 'Offprints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1460, 'cont1', '5', oils_i18n_gettext('1460', 'Calendars', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1461, 'cont1', '6', oils_i18n_gettext('1461', 'Comics/graphic novels', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1462, 'cont2', 'a', oils_i18n_gettext('1462', 'Abstracts/summaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1463, 'cont2', 'b', oils_i18n_gettext('1463', 'Bibliographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1464, 'cont2', 'c', oils_i18n_gettext('1464', 'Catalogs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1465, 'cont2', 'd', oils_i18n_gettext('1465', 'Dictionaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1466, 'cont2', 'e', oils_i18n_gettext('1466', 'Encyclopedias', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1467, 'cont2', 'f', oils_i18n_gettext('1467', 'Handbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1468, 'cont2', 'g', oils_i18n_gettext('1468', 'Legal articles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1469, 'cont2', 'h', oils_i18n_gettext('1469', 'Biography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1470, 'cont2', 'i', oils_i18n_gettext('1470', 'Indexes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1471, 'cont2', 'j', oils_i18n_gettext('1471', 'Patent document', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1472, 'cont2', 'k', oils_i18n_gettext('1472', 'Discographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1473, 'cont2', 'l', oils_i18n_gettext('1473', 'Legislation', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1474, 'cont2', 'm', oils_i18n_gettext('1474', 'Theses', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1475, 'cont2', 'n', oils_i18n_gettext('1475', 'Surveys of the literature in a subject area', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1476, 'cont2', 'o', oils_i18n_gettext('1476', 'Reviews', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1477, 'cont2', 'p', oils_i18n_gettext('1477', 'Programmed texts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1478, 'cont2', 'q', oils_i18n_gettext('1478', 'Filmographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1479, 'cont2', 'r', oils_i18n_gettext('1479', 'Directories', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1480, 'cont2', 's', oils_i18n_gettext('1480', 'Statistics', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1481, 'cont2', 't', oils_i18n_gettext('1481', 'Technical reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1482, 'cont2', 'u', oils_i18n_gettext('1482', 'Standards/specifications', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1483, 'cont2', 'v', oils_i18n_gettext('1483', 'Legal cases and case notes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1484, 'cont2', 'w', oils_i18n_gettext('1484', 'Law reports and digests', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1485, 'cont2', 'x', oils_i18n_gettext('1485', 'Other reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1486, 'cont2', 'y', oils_i18n_gettext('1486', 'Yearbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1487, 'cont2', 'z', oils_i18n_gettext('1487', 'Treaties', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1488, 'cont2', '2', oils_i18n_gettext('1488', 'Offprints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1489, 'cont2', '5', oils_i18n_gettext('1489', 'Calendars', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1490, 'cont2', '6', oils_i18n_gettext('1490', 'Comics/graphic novels', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1491, 'cont3', 'a', oils_i18n_gettext('1491', 'Abstracts/summaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1492, 'cont3', 'b', oils_i18n_gettext('1492', 'Bibliographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1493, 'cont3', 'c', oils_i18n_gettext('1493', 'Catalogs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1494, 'cont3', 'd', oils_i18n_gettext('1494', 'Dictionaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1495, 'cont3', 'e', oils_i18n_gettext('1495', 'Encyclopedias', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1496, 'cont3', 'f', oils_i18n_gettext('1496', 'Handbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1497, 'cont3', 'g', oils_i18n_gettext('1497', 'Legal articles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1498, 'cont3', 'h', oils_i18n_gettext('1498', 'Biography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1499, 'cont3', 'i', oils_i18n_gettext('1499', 'Indexes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1500, 'cont3', 'j', oils_i18n_gettext('1500', 'Patent document', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1501, 'cont3', 'k', oils_i18n_gettext('1501', 'Discographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1502, 'cont3', 'l', oils_i18n_gettext('1502', 'Legislation', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1503, 'cont3', 'm', oils_i18n_gettext('1503', 'Theses', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1504, 'cont3', 'n', oils_i18n_gettext('1504', 'Surveys of the literature in a subject area', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1505, 'cont3', 'o', oils_i18n_gettext('1505', 'Reviews', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1506, 'cont3', 'p', oils_i18n_gettext('1506', 'Programmed texts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1507, 'cont3', 'q', oils_i18n_gettext('1507', 'Filmographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1508, 'cont3', 'r', oils_i18n_gettext('1508', 'Directories', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1509, 'cont3', 's', oils_i18n_gettext('1509', 'Statistics', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1510, 'cont3', 't', oils_i18n_gettext('1510', 'Technical reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1511, 'cont3', 'u', oils_i18n_gettext('1511', 'Standards/specifications', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1512, 'cont3', 'v', oils_i18n_gettext('1512', 'Legal cases and case notes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1513, 'cont3', 'w', oils_i18n_gettext('1513', 'Law reports and digests', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1514, 'cont3', 'x', oils_i18n_gettext('1514', 'Other reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1515, 'cont3', 'y', oils_i18n_gettext('1515', 'Yearbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1516, 'cont3', 'z', oils_i18n_gettext('1516', 'Treaties', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1517, 'cont3', '2', oils_i18n_gettext('1517', 'Offprints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1518, 'cont3', '5', oils_i18n_gettext('1518', 'Calendars', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1519, 'cont3', '6', oils_i18n_gettext('1519', 'Comics/graphic novels', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1520, 'cont4', 'a', oils_i18n_gettext('1520', 'Abstracts/summaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1521, 'cont4', 'b', oils_i18n_gettext('1521', 'Bibliographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1522, 'cont4', 'c', oils_i18n_gettext('1522', 'Catalogs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1523, 'cont4', 'd', oils_i18n_gettext('1523', 'Dictionaries', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1524, 'cont4', 'e', oils_i18n_gettext('1524', 'Encyclopedias', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1525, 'cont4', 'f', oils_i18n_gettext('1525', 'Handbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1526, 'cont4', 'g', oils_i18n_gettext('1526', 'Legal articles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1527, 'cont4', 'h', oils_i18n_gettext('1527', 'Biography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1528, 'cont4', 'i', oils_i18n_gettext('1528', 'Indexes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1529, 'cont4', 'j', oils_i18n_gettext('1529', 'Patent document', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1530, 'cont4', 'k', oils_i18n_gettext('1530', 'Discographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1531, 'cont4', 'l', oils_i18n_gettext('1531', 'Legislation', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1532, 'cont4', 'm', oils_i18n_gettext('1532', 'Theses', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1533, 'cont4', 'n', oils_i18n_gettext('1533', 'Surveys of the literature in a subject area', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1534, 'cont4', 'o', oils_i18n_gettext('1534', 'Reviews', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1535, 'cont4', 'p', oils_i18n_gettext('1535', 'Programmed texts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1536, 'cont4', 'q', oils_i18n_gettext('1536', 'Filmographies', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1537, 'cont4', 'r', oils_i18n_gettext('1537', 'Directories', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1538, 'cont4', 's', oils_i18n_gettext('1538', 'Statistics', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1539, 'cont4', 't', oils_i18n_gettext('1539', 'Technical reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1540, 'cont4', 'u', oils_i18n_gettext('1540', 'Standards/specifications', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1541, 'cont4', 'v', oils_i18n_gettext('1541', 'Legal cases and case notes', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1542, 'cont4', 'w', oils_i18n_gettext('1542', 'Law reports and digests', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1543, 'cont4', 'x', oils_i18n_gettext('1543', 'Other reports', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1544, 'cont4', 'y', oils_i18n_gettext('1544', 'Yearbooks', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1545, 'cont4', 'z', oils_i18n_gettext('1545', 'Treaties', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1546, 'cont4', '2', oils_i18n_gettext('1546', 'Offprints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1547, 'cont4', '5', oils_i18n_gettext('1547', 'Calendars', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1548, 'cont4', '6', oils_i18n_gettext('1548', 'Comics/graphic novels', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1549, 'ltxt1', ' ', oils_i18n_gettext('1549', 'Item is a music sound recording', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1550, 'ltxt1', 'a', oils_i18n_gettext('1550', 'Autobiography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1551, 'ltxt1', 'b', oils_i18n_gettext('1551', 'Biography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1552, 'ltxt1', 'c', oils_i18n_gettext('1552', 'Conference proceedings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1553, 'ltxt1', 'd', oils_i18n_gettext('1553', 'Drama', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1554, 'ltxt1', 'e', oils_i18n_gettext('1554', 'Essays', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1555, 'ltxt1', 'f', oils_i18n_gettext('1555', 'Fiction', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1556, 'ltxt1', 'g', oils_i18n_gettext('1556', 'Reporting', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1557, 'ltxt1', 'h', oils_i18n_gettext('1557', 'History', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1558, 'ltxt1', 'i', oils_i18n_gettext('1558', 'Instruction', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1559, 'ltxt1', 'j', oils_i18n_gettext('1559', 'Language instruction', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1560, 'ltxt1', 'k', oils_i18n_gettext('1560', 'Comedy', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1561, 'ltxt1', 'l', oils_i18n_gettext('1561', 'Lectures, speeches', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1562, 'ltxt1', 'm', oils_i18n_gettext('1562', 'Memoirs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1563, 'ltxt1', 'n', oils_i18n_gettext('1563', 'Not applicable', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1564, 'ltxt1', 'o', oils_i18n_gettext('1564', 'Folktales', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1565, 'ltxt1', 'p', oils_i18n_gettext('1565', 'Poetry', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1566, 'ltxt1', 'r', oils_i18n_gettext('1566', 'Rehearsals', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1567, 'ltxt1', 's', oils_i18n_gettext('1567', 'Sounds', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1568, 'ltxt1', 't', oils_i18n_gettext('1568', 'Interviews', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1569, 'ltxt1', 'z', oils_i18n_gettext('1569', 'Other', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1570, 'ltxt2', 'a', oils_i18n_gettext('1570', 'Autobiography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1571, 'ltxt2', 'b', oils_i18n_gettext('1571', 'Biography', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1572, 'ltxt2', 'c', oils_i18n_gettext('1572', 'Conference proceedings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1573, 'ltxt2', 'd', oils_i18n_gettext('1573', 'Drama', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1574, 'ltxt2', 'e', oils_i18n_gettext('1574', 'Essays', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1575, 'ltxt2', 'f', oils_i18n_gettext('1575', 'Fiction', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1576, 'ltxt2', 'g', oils_i18n_gettext('1576', 'Reporting', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1577, 'ltxt2', 'h', oils_i18n_gettext('1577', 'History', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1578, 'ltxt2', 'i', oils_i18n_gettext('1578', 'Instruction', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1579, 'ltxt2', 'j', oils_i18n_gettext('1579', 'Language instruction', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1580, 'ltxt2', 'k', oils_i18n_gettext('1580', 'Comedy', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1581, 'ltxt2', 'l', oils_i18n_gettext('1581', 'Lectures, speeches', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1582, 'ltxt2', 'm', oils_i18n_gettext('1582', 'Memoirs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1583, 'ltxt2', 'n', oils_i18n_gettext('1583', 'Not applicable', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1584, 'ltxt2', 'o', oils_i18n_gettext('1584', 'Folktales', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1585, 'ltxt2', 'p', oils_i18n_gettext('1585', 'Poetry', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1586, 'ltxt2', 'r', oils_i18n_gettext('1586', 'Rehearsals', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1587, 'ltxt2', 's', oils_i18n_gettext('1587', 'Sounds', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1588, 'ltxt2', 't', oils_i18n_gettext('1588', 'Interviews', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1589, 'ltxt2', 'z', oils_i18n_gettext('1589', 'Other', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1590, 'relf1', ' ', oils_i18n_gettext('1590', 'No relief shown', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1591, 'relf1', 'a', oils_i18n_gettext('1591', 'Contours', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1592, 'relf1', 'b', oils_i18n_gettext('1592', 'Shading', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1593, 'relf1', 'c', oils_i18n_gettext('1593', 'Gradient and bathymetric tints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1594, 'relf1', 'd', oils_i18n_gettext('1594', 'Hachures', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1595, 'relf1', 'e', oils_i18n_gettext('1595', 'Bathymetry, soundings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1596, 'relf1', 'f', oils_i18n_gettext('1596', 'Form lines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1597, 'relf1', 'g', oils_i18n_gettext('1597', 'Spot heights', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1598, 'relf1', 'i', oils_i18n_gettext('1598', 'Pictorially', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1599, 'relf1', 'j', oils_i18n_gettext('1599', 'Land forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1600, 'relf1', 'k', oils_i18n_gettext('1600', 'Bathymetry, isolines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1601, 'relf1', 'm', oils_i18n_gettext('1601', 'Rock drawings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1602, 'relf1', 'z', oils_i18n_gettext('1602', 'Other', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1603, 'relf2', 'a', oils_i18n_gettext('1603', 'Contours', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1604, 'relf2', 'b', oils_i18n_gettext('1604', 'Shading', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1605, 'relf2', 'c', oils_i18n_gettext('1605', 'Gradient and bathymetric tints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1606, 'relf2', 'd', oils_i18n_gettext('1606', 'Hachures', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1607, 'relf2', 'e', oils_i18n_gettext('1607', 'Bathymetry, soundings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1608, 'relf2', 'f', oils_i18n_gettext('1608', 'Form lines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1609, 'relf2', 'g', oils_i18n_gettext('1609', 'Spot heights', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1610, 'relf2', 'i', oils_i18n_gettext('1610', 'Pictorially', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1611, 'relf2', 'j', oils_i18n_gettext('1611', 'Land forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1612, 'relf2', 'k', oils_i18n_gettext('1612', 'Bathymetry, isolines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1613, 'relf2', 'm', oils_i18n_gettext('1613', 'Rock drawings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1614, 'relf2', 'z', oils_i18n_gettext('1614', 'Other', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1615, 'relf3', 'a', oils_i18n_gettext('1615', 'Contours', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1616, 'relf3', 'b', oils_i18n_gettext('1616', 'Shading', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1617, 'relf3', 'c', oils_i18n_gettext('1617', 'Gradient and bathymetric tints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1618, 'relf3', 'd', oils_i18n_gettext('1618', 'Hachures', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1619, 'relf3', 'e', oils_i18n_gettext('1619', 'Bathymetry, soundings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1620, 'relf3', 'f', oils_i18n_gettext('1620', 'Form lines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1621, 'relf3', 'g', oils_i18n_gettext('1621', 'Spot heights', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1622, 'relf3', 'i', oils_i18n_gettext('1622', 'Pictorially', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1623, 'relf3', 'j', oils_i18n_gettext('1623', 'Land forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1624, 'relf3', 'k', oils_i18n_gettext('1624', 'Bathymetry, isolines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1625, 'relf3', 'm', oils_i18n_gettext('1625', 'Rock drawings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1626, 'relf3', 'z', oils_i18n_gettext('1626', 'Other', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1627, 'relf4', 'a', oils_i18n_gettext('1627', 'Contours', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1628, 'relf4', 'b', oils_i18n_gettext('1628', 'Shading', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1629, 'relf4', 'c', oils_i18n_gettext('1629', 'Gradient and bathymetric tints', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1630, 'relf4', 'd', oils_i18n_gettext('1630', 'Hachures', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1631, 'relf4', 'e', oils_i18n_gettext('1631', 'Bathymetry, soundings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1632, 'relf4', 'f', oils_i18n_gettext('1632', 'Form lines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1633, 'relf4', 'g', oils_i18n_gettext('1633', 'Spot heights', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1634, 'relf4', 'i', oils_i18n_gettext('1634', 'Pictorially', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1635, 'relf4', 'j', oils_i18n_gettext('1635', 'Land forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1636, 'relf4', 'k', oils_i18n_gettext('1636', 'Bathymetry, isolines', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1637, 'relf4', 'm', oils_i18n_gettext('1637', 'Rock drawings', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1638, 'relf4', 'z', oils_i18n_gettext('1638', 'Other', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1639, 'spfm1', ' ', oils_i18n_gettext('1639', 'No specified special format characteristics', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1640, 'spfm1', 'e', oils_i18n_gettext('1640', 'Manuscript', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1641, 'spfm1', 'j', oils_i18n_gettext('1641', 'Picture card, post card', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1642, 'spfm1', 'k', oils_i18n_gettext('1642', 'Calendar', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1643, 'spfm1', 'l', oils_i18n_gettext('1643', 'Puzzle', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1644, 'spfm1', 'n', oils_i18n_gettext('1644', 'Game', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1645, 'spfm1', 'o', oils_i18n_gettext('1645', 'Wall map', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1646, 'spfm1', 'p', oils_i18n_gettext('1646', 'Playing cards', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1647, 'spfm1', 'r', oils_i18n_gettext('1647', 'Loose-leaf', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1648, 'spfm1', 'z', oils_i18n_gettext('1648', 'Other', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1649, 'spfm2', 'e', oils_i18n_gettext('1649', 'Manuscript', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1650, 'spfm2', 'j', oils_i18n_gettext('1650', 'Picture card, post card', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1651, 'spfm2', 'k', oils_i18n_gettext('1651', 'Calendar', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1652, 'spfm2', 'l', oils_i18n_gettext('1652', 'Puzzle', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1653, 'spfm2', 'n', oils_i18n_gettext('1653', 'Game', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1654, 'spfm2', 'o', oils_i18n_gettext('1654', 'Wall map', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1655, 'spfm2', 'p', oils_i18n_gettext('1655', 'Playing cards', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1656, 'spfm2', 'r', oils_i18n_gettext('1656', 'Loose-leaf', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1657, 'spfm2', 'z', oils_i18n_gettext('1657', 'Other', 'ccvm', 'value'), FALSE);

-- Illustrations
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1658, 'ills', ' ', oils_i18n_gettext('1658', 'No Illustrations', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1659, 'ills', 'a', oils_i18n_gettext('1659', 'Illustrations', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1660, 'ills', 'b', oils_i18n_gettext('1660', 'Maps', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1661, 'ills', 'c', oils_i18n_gettext('1661', 'Portraits', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1662, 'ills', 'd', oils_i18n_gettext('1662', 'Charts', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1663, 'ills', 'e', oils_i18n_gettext('1663', 'Plans', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1664, 'ills', 'f', oils_i18n_gettext('1664', 'Plates', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1665, 'ills', 'g', oils_i18n_gettext('1665', 'Music', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1666, 'ills', 'h', oils_i18n_gettext('1666', 'Facsimiles', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1667, 'ills', 'i', oils_i18n_gettext('1667', 'Coats of arms', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1668, 'ills', 'j', oils_i18n_gettext('1668', 'Genealogical tables', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1669, 'ills', 'k', oils_i18n_gettext('1669', 'Forms', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1670, 'ills', 'l', oils_i18n_gettext('1670', 'Samples', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1671, 'ills', 'm', oils_i18n_gettext('1671', 'Phonodisc, phonowire, etc.', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1672, 'ills', 'o', oils_i18n_gettext('1672', 'Photographs', 'ccvm', 'value'));
INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES (1673, 'ills', 'p', oils_i18n_gettext('1673', 'Illuminations', 'ccvm', 'value'));
	
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1674, 'ills1', ' ', oils_i18n_gettext('1674', 'No Illustrations', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1675, 'ills1', 'a', oils_i18n_gettext('1675', 'Illustrations', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1676, 'ills1', 'b', oils_i18n_gettext('1676', 'Maps', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1677, 'ills1', 'c', oils_i18n_gettext('1677', 'Portraits', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1678, 'ills1', 'd', oils_i18n_gettext('1678', 'Charts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1679, 'ills1', 'e', oils_i18n_gettext('1679', 'Plans', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1680, 'ills1', 'f', oils_i18n_gettext('1680', 'Plates', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1681, 'ills1', 'g', oils_i18n_gettext('1681', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1682, 'ills1', 'h', oils_i18n_gettext('1682', 'Facsimiles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1683, 'ills1', 'i', oils_i18n_gettext('1683', 'Coats of arms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1684, 'ills1', 'j', oils_i18n_gettext('1684', 'Genealogical tables', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1685, 'ills1', 'k', oils_i18n_gettext('1685', 'Forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1686, 'ills1', 'l', oils_i18n_gettext('1686', 'Samples', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1687, 'ills1', 'm', oils_i18n_gettext('1687', 'Phonodisc, phonowire, etc.', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1688, 'ills1', 'o', oils_i18n_gettext('1688', 'Photographs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1689, 'ills1', 'p', oils_i18n_gettext('1689', 'Illuminations', 'ccvm', 'value'), FALSE);
	
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1690, 'ills2', 'a', oils_i18n_gettext('1690', 'Illustrations', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1691, 'ills2', 'b', oils_i18n_gettext('1691', 'Maps', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1692, 'ills2', 'c', oils_i18n_gettext('1692', 'Portraits', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1693, 'ills2', 'd', oils_i18n_gettext('1693', 'Charts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1694, 'ills2', 'e', oils_i18n_gettext('1694', 'Plans', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1695, 'ills2', 'f', oils_i18n_gettext('1695', 'Plates', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1696, 'ills2', 'g', oils_i18n_gettext('1696', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1697, 'ills2', 'h', oils_i18n_gettext('1697', 'Facsimiles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1698, 'ills2', 'i', oils_i18n_gettext('1698', 'Coats of arms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1699, 'ills2', 'j', oils_i18n_gettext('1699', 'Genealogical tables', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1700, 'ills2', 'k', oils_i18n_gettext('1700', 'Forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1701, 'ills2', 'l', oils_i18n_gettext('1701', 'Samples', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1702, 'ills2', 'm', oils_i18n_gettext('1702', 'Phonodisc, phonowire, etc.', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1703, 'ills2', 'o', oils_i18n_gettext('1703', 'Photographs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1704, 'ills2', 'p', oils_i18n_gettext('1704', 'Illuminations', 'ccvm', 'value'), FALSE);
	
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1705, 'ills3', 'a', oils_i18n_gettext('1705', 'Illustrations', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1706, 'ills3', 'b', oils_i18n_gettext('1706', 'Maps', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1707, 'ills3', 'c', oils_i18n_gettext('1707', 'Portraits', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1708, 'ills3', 'd', oils_i18n_gettext('1708', 'Charts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1709, 'ills3', 'e', oils_i18n_gettext('1709', 'Plans', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1710, 'ills3', 'f', oils_i18n_gettext('1710', 'Plates', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1711, 'ills3', 'g', oils_i18n_gettext('1711', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1712, 'ills3', 'h', oils_i18n_gettext('1712', 'Facsimiles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1713, 'ills3', 'i', oils_i18n_gettext('1713', 'Coats of arms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1714, 'ills3', 'j', oils_i18n_gettext('1714', 'Genealogical tables', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1715, 'ills3', 'k', oils_i18n_gettext('1715', 'Forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1716, 'ills3', 'l', oils_i18n_gettext('1716', 'Samples', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1717, 'ills3', 'm', oils_i18n_gettext('1717', 'Phonodisc, phonowire, etc.', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1718, 'ills3', 'o', oils_i18n_gettext('1718', 'Photographs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1719, 'ills3', 'p', oils_i18n_gettext('1719', 'Illuminations', 'ccvm', 'value'), FALSE);
	
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1720, 'ills4', 'a', oils_i18n_gettext('1720', 'Illustrations', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1721, 'ills4', 'b', oils_i18n_gettext('1721', 'Maps', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1722, 'ills4', 'c', oils_i18n_gettext('1722', 'Portraits', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1723, 'ills4', 'd', oils_i18n_gettext('1723', 'Charts', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1724, 'ills4', 'e', oils_i18n_gettext('1724', 'Plans', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1725, 'ills4', 'f', oils_i18n_gettext('1725', 'Plates', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1726, 'ills4', 'g', oils_i18n_gettext('1726', 'Music', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1727, 'ills4', 'h', oils_i18n_gettext('1727', 'Facsimiles', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1728, 'ills4', 'i', oils_i18n_gettext('1728', 'Coats of arms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1729, 'ills4', 'j', oils_i18n_gettext('1729', 'Genealogical tables', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1730, 'ills4', 'k', oils_i18n_gettext('1730', 'Forms', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1731, 'ills4', 'l', oils_i18n_gettext('1731', 'Samples', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1732, 'ills4', 'm', oils_i18n_gettext('1732', 'Phonodisc, phonowire, etc.', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1733, 'ills4', 'o', oils_i18n_gettext('1733', 'Photographs', 'ccvm', 'value'), FALSE);
INSERT INTO config.coded_value_map (id, ctype, code, value, opac_visible) VALUES (1734, 'ills4', 'p', oils_i18n_gettext('1734', 'Illuminations', 'ccvm', 'value'), FALSE);

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
(1750, 'srce', ' ', oils_i18n_gettext('1750', 'National bibliographic agency', 'ccvm', 'value')),
(1751, 'srce', 'c', oils_i18n_gettext('1751', 'Cooperative cataloging program', 'ccvm', 'value')),
(1752, 'srce', 'd', oils_i18n_gettext('1752', 'Other', 'ccvm', 'value'));

-- composite definitions for record attr "icon_format"

INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES
--book
(564, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_not":[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"},{"_attr":"item_form","_val":"d"},{"_attr":"item_form","_val":"f"},{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"r"},{"_attr":"item_form","_val":"s"}]},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'),

-- braille
(565, '{"0":{"_attr":"item_type","_val":"a"},"1":{"_attr":"item_form","_val":"f"}}'),

-- software
(566, '{"_attr":"item_type","_val":"m"}'),

-- dvd
(567, '{"_attr":"vr_format","_val":"v"}'),

-- ebook
(568, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"q"}],"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'),

-- eaudio
(569, '{"0":{"_attr":"item_type","_val":"i"},"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"s"}]}'),

-- kit
(570, '[{"_attr":"item_type","_val":"o"},{"_attr":"item_type","_val":"p"}]'),

-- map
(571, '[{"_attr":"item_type","_val":"e"},{"_attr":"item_type","_val":"f"}]'),

-- microform
(572, '[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"}]'),

-- score
(573, '[{"_attr":"item_type","_val":"c"},{"_attr":"item_type","_val":"d"}]'),

-- picture
(574, '{"_attr":"item_type","_val":"k"}'),

-- equip
(575, '{"_attr":"item_type","_val":"r"}'),

-- serial
(576, '[{"_attr":"bib_level","_val":"b"},{"_attr":"bib_level","_val":"s"}]'),

-- vhs
(577, '{"_attr":"vr_format","_val":"b"}'),

-- evideo
(578, '{"0":{"_attr":"item_type","_val":"g"},"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"q"}]}'),

-- cdaudiobook
(579, '{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"sr_format","_val":"f"}}'),

-- cdmusic
(580, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_attr":"sr_format","_val":"f"}}'),

-- casaudiobook
(581, '{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"sr_format","_val":"l"}}'),

-- casmusic
(582, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_attr":"sr_format","_val":"l"}}'),

-- phonospoken
(583, '{"0":{"_attr":"item_type","_val":"i"},"1":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"e"}]}'),

-- phonomusic
(584, '{"0":{"_attr":"item_type","_val":"j"},"1":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"e"}]}'),

-- lpbook
(585, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_attr":"item_form","_val":"d"},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}');

-- music (catch-all)
INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES
(607, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_not":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"f"},{"_attr":"sr_format","_val":"e"},{"_attr":"sr_format","_val":"l"}]}}');

-- blu-ray icon_format
INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES (608, '{"_attr":"vr_format","_val":"s"}');

-- electronic
INSERT INTO config.composite_attr_entry_definition
    (coded_value, definition) VALUES
(712, '[{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"o"}]');

--preloaded audio
INSERT INTO config.composite_attr_entry_definition
    (coded_value, definition) VALUES
(1736,'{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"item_form","_val":"q"}}');

--all videos
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES
    (1738, '{"_attr":"item_type","_val":"g"}');

-- use the definitions from the icon_format as the basis for the MR hold format definitions
DO $$
    DECLARE format TEXT;
BEGIN
    FOR format IN SELECT UNNEST(
        '{book,braille,software,dvd,kit,map,microform,score,picture,equip,serial,vhs,cdaudiobook,cdmusic,casaudiobook,casmusic,phonospoken,phonomusic,lpbook,blu-ray}'::text[])
    LOOP
        INSERT INTO config.composite_attr_entry_definition 
            (coded_value, definition) VALUES
            (
                -- get the ID from the new ccvm above
                (SELECT id FROM config.coded_value_map 
                    WHERE code = format AND ctype = 'mr_hold_format'),
                -- get the def of the matching ccvm attached to the icon_format attr
                (SELECT definition FROM config.composite_attr_entry_definition ccaed
                    JOIN config.coded_value_map ccvm ON (ccaed.coded_value = ccvm.id)
                    WHERE ccvm.ctype = 'icon_format' AND ccvm.code = format)
            );
    END LOOP; 
END $$;

-- copy the composite definition from icon_format into 
-- search_format for a baseline data set
DO $$
    DECLARE format config.coded_value_map%ROWTYPE;
BEGIN
    FOR format IN SELECT * 
        FROM config.coded_value_map WHERE ctype = 'icon_format'
    LOOP
        INSERT INTO config.composite_attr_entry_definition 
            (coded_value, definition) VALUES
            (
                -- get the ID from the new ccvm above
                (SELECT id FROM config.coded_value_map 
                    WHERE code = format.code AND ctype = 'search_format'),

                -- def of the matching icon_format attr
                (SELECT definition FROM config.composite_attr_entry_definition 
                    WHERE coded_value = format.id)
            );
    END LOOP; 
END $$;

-- modify the 'book' definition so that it includes large print
UPDATE config.composite_attr_entry_definition 
    SET definition = '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_not":[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"},{"_attr":"item_form","_val":"f"},{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"r"},{"_attr":"item_form","_val":"s"}]},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'
    WHERE coded_value = 610;

-- modify 'music' to include all recorded music, regardless of format
UPDATE config.composite_attr_entry_definition 
    SET definition = '{"_attr":"item_type","_val":"j"}'
    WHERE coded_value = 632;


-- Composite coded value maps for multi-position single-character fields that allow the "primary" fixed field to be used in advanced searches or other composite definitions without a ton of ORs and extra work.
-- Space is used as a filler for any position other than the first, so for something to actually have "No accompanying matter," for example, specifically accm1 must = ' '.
-- Any other value has the same meaning in any position.

-- Accompanying Matter
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1735, '{"_attr":"accm1","_val":" "}');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (713, '[{"_attr":"accm6","_val":"a"},{"_attr":"accm5","_val":"a"},{"_attr":"accm4","_val":"a"},{"_attr":"accm3","_val":"a"},{"_attr":"accm2","_val":"a"},{"_attr":"accm1","_val":"a"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (714, '[{"_attr":"accm6","_val":"b"},{"_attr":"accm5","_val":"b"},{"_attr":"accm4","_val":"b"},{"_attr":"accm3","_val":"b"},{"_attr":"accm2","_val":"b"},{"_attr":"accm1","_val":"b"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (715, '[{"_attr":"accm6","_val":"c"},{"_attr":"accm5","_val":"c"},{"_attr":"accm4","_val":"c"},{"_attr":"accm3","_val":"c"},{"_attr":"accm2","_val":"c"},{"_attr":"accm1","_val":"c"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (716, '[{"_attr":"accm6","_val":"d"},{"_attr":"accm5","_val":"d"},{"_attr":"accm4","_val":"d"},{"_attr":"accm3","_val":"d"},{"_attr":"accm2","_val":"d"},{"_attr":"accm1","_val":"d"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (717, '[{"_attr":"accm6","_val":"e"},{"_attr":"accm5","_val":"e"},{"_attr":"accm4","_val":"e"},{"_attr":"accm3","_val":"e"},{"_attr":"accm2","_val":"e"},{"_attr":"accm1","_val":"e"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (718, '[{"_attr":"accm6","_val":"f"},{"_attr":"accm5","_val":"f"},{"_attr":"accm4","_val":"f"},{"_attr":"accm3","_val":"f"},{"_attr":"accm2","_val":"f"},{"_attr":"accm1","_val":"f"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (719, '[{"_attr":"accm6","_val":"g"},{"_attr":"accm5","_val":"g"},{"_attr":"accm4","_val":"g"},{"_attr":"accm3","_val":"g"},{"_attr":"accm2","_val":"g"},{"_attr":"accm1","_val":"g"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (720, '[{"_attr":"accm6","_val":"h"},{"_attr":"accm5","_val":"h"},{"_attr":"accm4","_val":"h"},{"_attr":"accm3","_val":"h"},{"_attr":"accm2","_val":"h"},{"_attr":"accm1","_val":"h"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (721, '[{"_attr":"accm6","_val":"i"},{"_attr":"accm5","_val":"i"},{"_attr":"accm4","_val":"i"},{"_attr":"accm3","_val":"i"},{"_attr":"accm2","_val":"i"},{"_attr":"accm1","_val":"i"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (722, '[{"_attr":"accm6","_val":"k"},{"_attr":"accm5","_val":"k"},{"_attr":"accm4","_val":"k"},{"_attr":"accm3","_val":"k"},{"_attr":"accm2","_val":"k"},{"_attr":"accm1","_val":"k"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (723, '[{"_attr":"accm6","_val":"r"},{"_attr":"accm5","_val":"r"},{"_attr":"accm4","_val":"r"},{"_attr":"accm3","_val":"r"},{"_attr":"accm2","_val":"r"},{"_attr":"accm1","_val":"r"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (724, '[{"_attr":"accm6","_val":"s"},{"_attr":"accm5","_val":"s"},{"_attr":"accm4","_val":"s"},{"_attr":"accm3","_val":"s"},{"_attr":"accm2","_val":"s"},{"_attr":"accm1","_val":"s"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (725, '[{"_attr":"accm6","_val":"z"},{"_attr":"accm5","_val":"z"},{"_attr":"accm4","_val":"z"},{"_attr":"accm3","_val":"z"},{"_attr":"accm2","_val":"z"},{"_attr":"accm1","_val":"z"}]');

-- Nature of Contents
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (835, '{"_attr":"cont1","_val":" "}');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (836, '[{"_attr":"cont4","_val":"a"},{"_attr":"cont3","_val":"a"},{"_attr":"cont2","_val":"a"},{"_attr":"cont1","_val":"a"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (837, '[{"_attr":"cont4","_val":"b"},{"_attr":"cont3","_val":"b"},{"_attr":"cont2","_val":"b"},{"_attr":"cont1","_val":"b"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (838, '[{"_attr":"cont4","_val":"c"},{"_attr":"cont3","_val":"c"},{"_attr":"cont2","_val":"c"},{"_attr":"cont1","_val":"c"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (839, '[{"_attr":"cont4","_val":"d"},{"_attr":"cont3","_val":"d"},{"_attr":"cont2","_val":"d"},{"_attr":"cont1","_val":"d"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (840, '[{"_attr":"cont4","_val":"e"},{"_attr":"cont3","_val":"e"},{"_attr":"cont2","_val":"e"},{"_attr":"cont1","_val":"e"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (841, '[{"_attr":"cont4","_val":"f"},{"_attr":"cont3","_val":"f"},{"_attr":"cont2","_val":"f"},{"_attr":"cont1","_val":"f"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (842, '[{"_attr":"cont4","_val":"g"},{"_attr":"cont3","_val":"g"},{"_attr":"cont2","_val":"g"},{"_attr":"cont1","_val":"g"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (843, '[{"_attr":"cont4","_val":"h"},{"_attr":"cont3","_val":"h"},{"_attr":"cont2","_val":"h"},{"_attr":"cont1","_val":"h"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (844, '[{"_attr":"cont4","_val":"i"},{"_attr":"cont3","_val":"i"},{"_attr":"cont2","_val":"i"},{"_attr":"cont1","_val":"i"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (845, '[{"_attr":"cont4","_val":"j"},{"_attr":"cont3","_val":"j"},{"_attr":"cont2","_val":"j"},{"_attr":"cont1","_val":"j"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (846, '[{"_attr":"cont4","_val":"k"},{"_attr":"cont3","_val":"k"},{"_attr":"cont2","_val":"k"},{"_attr":"cont1","_val":"k"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (847, '[{"_attr":"cont4","_val":"l"},{"_attr":"cont3","_val":"l"},{"_attr":"cont2","_val":"l"},{"_attr":"cont1","_val":"l"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (848, '[{"_attr":"cont4","_val":"m"},{"_attr":"cont3","_val":"m"},{"_attr":"cont2","_val":"m"},{"_attr":"cont1","_val":"m"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (849, '[{"_attr":"cont4","_val":"n"},{"_attr":"cont3","_val":"n"},{"_attr":"cont2","_val":"n"},{"_attr":"cont1","_val":"n"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (850, '[{"_attr":"cont4","_val":"o"},{"_attr":"cont3","_val":"o"},{"_attr":"cont2","_val":"o"},{"_attr":"cont1","_val":"o"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (851, '[{"_attr":"cont4","_val":"p"},{"_attr":"cont3","_val":"p"},{"_attr":"cont2","_val":"p"},{"_attr":"cont1","_val":"p"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (852, '[{"_attr":"cont4","_val":"q"},{"_attr":"cont3","_val":"q"},{"_attr":"cont2","_val":"q"},{"_attr":"cont1","_val":"q"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (853, '[{"_attr":"cont4","_val":"r"},{"_attr":"cont3","_val":"r"},{"_attr":"cont2","_val":"r"},{"_attr":"cont1","_val":"r"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (854, '[{"_attr":"cont4","_val":"s"},{"_attr":"cont3","_val":"s"},{"_attr":"cont2","_val":"s"},{"_attr":"cont1","_val":"s"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (855, '[{"_attr":"cont4","_val":"t"},{"_attr":"cont3","_val":"t"},{"_attr":"cont2","_val":"t"},{"_attr":"cont1","_val":"t"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (856, '[{"_attr":"cont4","_val":"u"},{"_attr":"cont3","_val":"u"},{"_attr":"cont2","_val":"u"},{"_attr":"cont1","_val":"u"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (857, '[{"_attr":"cont4","_val":"v"},{"_attr":"cont3","_val":"v"},{"_attr":"cont2","_val":"v"},{"_attr":"cont1","_val":"v"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (858, '[{"_attr":"cont4","_val":"w"},{"_attr":"cont3","_val":"w"},{"_attr":"cont2","_val":"w"},{"_attr":"cont1","_val":"w"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (859, '[{"_attr":"cont4","_val":"x"},{"_attr":"cont3","_val":"x"},{"_attr":"cont2","_val":"x"},{"_attr":"cont1","_val":"x"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (860, '[{"_attr":"cont4","_val":"y"},{"_attr":"cont3","_val":"y"},{"_attr":"cont2","_val":"y"},{"_attr":"cont1","_val":"y"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (861, '[{"_attr":"cont4","_val":"z"},{"_attr":"cont3","_val":"z"},{"_attr":"cont2","_val":"z"},{"_attr":"cont1","_val":"z"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (862, '[{"_attr":"cont4","_val":"2"},{"_attr":"cont3","_val":"2"},{"_attr":"cont2","_val":"2"},{"_attr":"cont1","_val":"2"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (863, '[{"_attr":"cont4","_val":"5"},{"_attr":"cont3","_val":"5"},{"_attr":"cont2","_val":"5"},{"_attr":"cont1","_val":"5"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (864, '[{"_attr":"cont4","_val":"6"},{"_attr":"cont3","_val":"6"},{"_attr":"cont2","_val":"6"},{"_attr":"cont1","_val":"6"}]');

-- Literary Text for Sound Recordings
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (881, '{"_attr":"ltxt1","_val":" "}');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (882, '[{"_attr":"ltxt2","_val":"a"},{"_attr":"ltxt1","_val":"a"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (883, '[{"_attr":"ltxt2","_val":"b"},{"_attr":"ltxt1","_val":"b"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (884, '[{"_attr":"ltxt2","_val":"c"},{"_attr":"ltxt1","_val":"c"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (885, '[{"_attr":"ltxt2","_val":"d"},{"_attr":"ltxt1","_val":"d"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (886, '[{"_attr":"ltxt2","_val":"e"},{"_attr":"ltxt1","_val":"e"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (887, '[{"_attr":"ltxt2","_val":"f"},{"_attr":"ltxt1","_val":"f"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (888, '[{"_attr":"ltxt2","_val":"g"},{"_attr":"ltxt1","_val":"g"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (889, '[{"_attr":"ltxt2","_val":"h"},{"_attr":"ltxt1","_val":"h"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (890, '[{"_attr":"ltxt2","_val":"i"},{"_attr":"ltxt1","_val":"i"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (891, '[{"_attr":"ltxt2","_val":"j"},{"_attr":"ltxt1","_val":"j"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (892, '[{"_attr":"ltxt2","_val":"k"},{"_attr":"ltxt1","_val":"k"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (893, '[{"_attr":"ltxt2","_val":"l"},{"_attr":"ltxt1","_val":"l"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (894, '[{"_attr":"ltxt2","_val":"m"},{"_attr":"ltxt1","_val":"m"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (895, '[{"_attr":"ltxt2","_val":"n"},{"_attr":"ltxt1","_val":"n"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (896, '[{"_attr":"ltxt2","_val":"o"},{"_attr":"ltxt1","_val":"o"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (897, '[{"_attr":"ltxt2","_val":"p"},{"_attr":"ltxt1","_val":"p"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (898, '[{"_attr":"ltxt2","_val":"r"},{"_attr":"ltxt1","_val":"r"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (899, '[{"_attr":"ltxt2","_val":"s"},{"_attr":"ltxt1","_val":"s"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (900, '[{"_attr":"ltxt2","_val":"t"},{"_attr":"ltxt1","_val":"t"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (901, '[{"_attr":"ltxt2","_val":"z"},{"_attr":"ltxt1","_val":"z"}]');

-- Relief
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (965, '{"_attr":"relf1","_val":" "}');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (966, '[{"_attr":"relf4","_val":"a"},{"_attr":"relf3","_val":"a"},{"_attr":"relf2","_val":"a"},{"_attr":"relf1","_val":"a"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (967, '[{"_attr":"relf4","_val":"b"},{"_attr":"relf3","_val":"b"},{"_attr":"relf2","_val":"b"},{"_attr":"relf1","_val":"b"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (968, '[{"_attr":"relf4","_val":"c"},{"_attr":"relf3","_val":"c"},{"_attr":"relf2","_val":"c"},{"_attr":"relf1","_val":"c"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (969, '[{"_attr":"relf4","_val":"d"},{"_attr":"relf3","_val":"d"},{"_attr":"relf2","_val":"d"},{"_attr":"relf1","_val":"d"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (970, '[{"_attr":"relf4","_val":"e"},{"_attr":"relf3","_val":"e"},{"_attr":"relf2","_val":"e"},{"_attr":"relf1","_val":"e"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (971, '[{"_attr":"relf4","_val":"f"},{"_attr":"relf3","_val":"f"},{"_attr":"relf2","_val":"f"},{"_attr":"relf1","_val":"f"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (972, '[{"_attr":"relf4","_val":"g"},{"_attr":"relf3","_val":"g"},{"_attr":"relf2","_val":"g"},{"_attr":"relf1","_val":"g"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (973, '[{"_attr":"relf4","_val":"i"},{"_attr":"relf3","_val":"i"},{"_attr":"relf2","_val":"i"},{"_attr":"relf1","_val":"i"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (974, '[{"_attr":"relf4","_val":"j"},{"_attr":"relf3","_val":"j"},{"_attr":"relf2","_val":"j"},{"_attr":"relf1","_val":"j"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (975, '[{"_attr":"relf4","_val":"k"},{"_attr":"relf3","_val":"k"},{"_attr":"relf2","_val":"k"},{"_attr":"relf1","_val":"k"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (976, '[{"_attr":"relf4","_val":"m"},{"_attr":"relf3","_val":"m"},{"_attr":"relf2","_val":"m"},{"_attr":"relf1","_val":"m"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (977, '[{"_attr":"relf4","_val":"z"},{"_attr":"relf3","_val":"z"},{"_attr":"relf2","_val":"z"},{"_attr":"relf1","_val":"z"}]');

-- Special Format Characteristics
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (978, '{"_attr":"spfm1","_val":" "}');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (979, '[{"_attr":"spfm2","_val":"e"},{"_attr":"spfm1","_val":"e"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (980, '[{"_attr":"spfm2","_val":"j"},{"_attr":"spfm1","_val":"j"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (981, '[{"_attr":"spfm2","_val":"k"},{"_attr":"spfm1","_val":"k"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (982, '[{"_attr":"spfm2","_val":"l"},{"_attr":"spfm1","_val":"l"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (983, '[{"_attr":"spfm2","_val":"n"},{"_attr":"spfm1","_val":"n"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (984, '[{"_attr":"spfm2","_val":"o"},{"_attr":"spfm1","_val":"o"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (985, '[{"_attr":"spfm2","_val":"p"},{"_attr":"spfm1","_val":"p"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (986, '[{"_attr":"spfm2","_val":"r"},{"_attr":"spfm1","_val":"r"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (987, '[{"_attr":"spfm2","_val":"z"},{"_attr":"spfm1","_val":"z"}]');

-- Illustrations
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1658, '{"_attr":"ills1","_val":" "}');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1659, '[{"_attr":"ills4","_val":"a"},{"_attr":"ills3","_val":"a"},{"_attr":"ills2","_val":"a"},{"_attr":"ills1","_val":"a"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1660, '[{"_attr":"ills4","_val":"b"},{"_attr":"ills3","_val":"b"},{"_attr":"ills2","_val":"b"},{"_attr":"ills1","_val":"b"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1661, '[{"_attr":"ills4","_val":"c"},{"_attr":"ills3","_val":"c"},{"_attr":"ills2","_val":"c"},{"_attr":"ills1","_val":"c"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1662, '[{"_attr":"ills4","_val":"d"},{"_attr":"ills3","_val":"d"},{"_attr":"ills2","_val":"d"},{"_attr":"ills1","_val":"d"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1663, '[{"_attr":"ills4","_val":"e"},{"_attr":"ills3","_val":"e"},{"_attr":"ills2","_val":"e"},{"_attr":"ills1","_val":"e"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1664, '[{"_attr":"ills4","_val":"f"},{"_attr":"ills3","_val":"f"},{"_attr":"ills2","_val":"f"},{"_attr":"ills1","_val":"f"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1665, '[{"_attr":"ills4","_val":"g"},{"_attr":"ills3","_val":"g"},{"_attr":"ills2","_val":"g"},{"_attr":"ills1","_val":"g"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1666, '[{"_attr":"ills4","_val":"h"},{"_attr":"ills3","_val":"h"},{"_attr":"ills2","_val":"h"},{"_attr":"ills1","_val":"h"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1667, '[{"_attr":"ills4","_val":"i"},{"_attr":"ills3","_val":"i"},{"_attr":"ills2","_val":"i"},{"_attr":"ills1","_val":"i"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1668, '[{"_attr":"ills4","_val":"j"},{"_attr":"ills3","_val":"j"},{"_attr":"ills2","_val":"j"},{"_attr":"ills1","_val":"j"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1669, '[{"_attr":"ills4","_val":"k"},{"_attr":"ills3","_val":"k"},{"_attr":"ills2","_val":"k"},{"_attr":"ills1","_val":"k"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1670, '[{"_attr":"ills4","_val":"l"},{"_attr":"ills3","_val":"l"},{"_attr":"ills2","_val":"l"},{"_attr":"ills1","_val":"l"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1671, '[{"_attr":"ills4","_val":"m"},{"_attr":"ills3","_val":"m"},{"_attr":"ills2","_val":"m"},{"_attr":"ills1","_val":"m"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1672, '[{"_attr":"ills4","_val":"o"},{"_attr":"ills3","_val":"o"},{"_attr":"ills2","_val":"o"},{"_attr":"ills1","_val":"o"}]');
INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES (1673, '[{"_attr":"ills4","_val":"p"},{"_attr":"ills3","_val":"p"},{"_attr":"ills2","_val":"p"},{"_attr":"ills1","_val":"p"}]');

SELECT SETVAL('config.coded_value_map_id_seq', (SELECT MAX(id) FROM config.coded_value_map));


-- Additional ccvm changes from the 960 seed data

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_010_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_010_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_013_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_013_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_015_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_015_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_016_ind_1', '#', $$Library and Archives Canada$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_016_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_016_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_017_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_017_ind_2', '#', $$Copyright or legal deposit number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_017_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_018_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_018_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_020_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_020_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_022_ind_1', '#', $$No level specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_022_ind_1', '0', $$Continuing resource of international interest$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_022_ind_1', '1', $$Continuing resource not of international interest$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_022_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_1', '0', $$International Standard Recording Code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_1', '1', $$Universal Product Code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_1', '2', $$International Standard Music Number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_1', '3', $$International Article Number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_1', '4', $$Serial Item and Contribution Identifier$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_1', '8', $$Unspecified type of standard number or code$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_2', '0', $$No difference$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_024_ind_2', '1', $$Difference$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_025_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_025_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_026_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_026_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_027_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_027_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_1', '0', $$Issue number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_1', '1', $$Matrix number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_1', '2', $$Plate number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_1', '3', $$Other music number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_1', '4', $$Videorecording number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_1', '5', $$Other publisher number$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_2', '0', $$No note, no added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_2', '1', $$Note, added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_2', '2', $$Note, no added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_028_ind_2', '3', $$No note, added entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_030_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_030_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_031_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_031_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_032_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_032_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_1', '#', $$No date information$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_1', '0', $$Single date$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_1', '1', $$Multiple single dates$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_1', '2', $$Range of dates$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_2', '0', $$Capture$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_2', '1', $$Broadcast$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_033_ind_2', '2', $$Finding$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_034_ind_1', '0', $$Scale indeterminable/No scale recorded$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_034_ind_1', '1', $$Single scale$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_034_ind_1', '3', $$Range of scales$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_034_ind_2', '#', $$Not applicable$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_034_ind_2', '0', $$Outer ring$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_034_ind_2', '1', $$Exclusion ring$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_035_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_035_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_036_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_036_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_037_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_037_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_038_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_038_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_040_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_040_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_041_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_041_ind_1', '0', $$Item not a translation/does not include a translation$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_041_ind_1', '1', $$Item is or includes a translation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_041_ind_2', '#', $$MARC language code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_041_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_042_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_042_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_043_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_043_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_044_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_044_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_045_ind_1', '#', $$Subfield $b or $c not present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_045_ind_1', '0', $$Single date/time$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_045_ind_1', '1', $$Multiple single dates/times$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_045_ind_1', '2', $$Range of dates/times$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_045_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_046_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_046_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_047_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_047_ind_2', '#', $$MARC musical composition code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_047_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_048_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_048_ind_2', '#', $$MARC code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_048_ind_2', '7', $$Source specified in subfield ‡2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_050_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_050_ind_1', '0', $$Item is in LC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_050_ind_1', '1', $$Item is not in LC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_050_ind_2', '0', $$Assigned by LC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_050_ind_2', '4', $$Assigned by agency other than LC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_051_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_051_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_052_ind_1', '#', $$Library of Congress Classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_052_ind_1', '1', $$U.S. Dept. of Defense Classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_052_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_052_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_1', '#', $$Information not provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_1', '0', $$Work held by LAC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_1', '1', $$Work not held by LAC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '0', $$LC-based call number assigned by LAC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '1', $$Complete LC class number assigned by LAC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '2', $$Incomplete LC class number assigned by LAC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '3', $$LC-based call number assigned by the contributing library$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '4', $$Complete LC class number assigned by the contributing library$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '5', $$Incomplete LC class number assigned by the contributing library$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '6', $$Other call number assigned by LAC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '7', $$Other class number assigned by LAC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '8', $$Other call number assigned by the contributing library$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_055_ind_2', '9', $$Other class number assigned by the contributing library$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_060_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_060_ind_1', '0', $$Item is in NLM$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_060_ind_1', '1', $$Item is not in NLM$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_060_ind_2', '0', $$Assigned by NLM$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_060_ind_2', '4', $$Assigned by agency other than NLM$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_061_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_061_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_066_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_066_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_070_ind_1', '0', $$Item is in NAL$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_070_ind_1', '1', $$Item is not in NAL$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_070_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_071_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_071_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_072_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_072_ind_2', '0', $$NAL subject category code list$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_072_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_074_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_074_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_080_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_080_ind_1', '0', $$Full$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_080_ind_1', '1', $$Abridged$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_080_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_082_ind_1', '0', $$Full edition$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_082_ind_1', '1', $$Abridged edition$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_082_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_082_ind_2', '0', $$Assigned by LC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_082_ind_2', '4', $$Assigned by agency other than LC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_083_ind_1', '0', $$Full edition$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_083_ind_1', '1', $$Abridged edition$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_083_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_084_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_084_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_085_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_085_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_086_ind_1', '#', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_086_ind_1', '0', $$Superintendent of Documents Classification System$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_086_ind_1', '1', $$Government of Canada Publications: Outline of Classification$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_086_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_088_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_088_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_100_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_100_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_100_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_100_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_110_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_110_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_110_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_110_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_111_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_111_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_111_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_111_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_1', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_130_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_210_ind_1', '0', $$No added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_210_ind_1', '1', $$Added entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_210_ind_2', '#', $$Abbreviated key title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_210_ind_2', '0', $$Other abbreviated title$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_222_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_1', '0', $$Not printed or displayed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_1', '1', $$Printed or displayed$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_240_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_1', '0', $$No added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_1', '1', $$Added entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_242_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_1', '0', $$Not printed or displayed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_1', '1', $$Printed or displayed$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_243_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_1', '0', $$No added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_1', '1', $$Added entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_245_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_1', '0', $$Note, no added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_1', '1', $$Note, added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_1', '2', $$No note, no added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_1', '3', $$No note, added entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '#', $$No type specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '0', $$Portion of title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '1', $$Parallel title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '2', $$Distinctive title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '3', $$Other title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '4', $$Cover title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '5', $$Added title page title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '6', $$Caption title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '7', $$Running title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_246_ind_2', '8', $$Spine title$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_247_ind_1', '0', $$No added entry$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_247_ind_1', '1', $$Added entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_247_ind_2', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_247_ind_2', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_250_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_250_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_254_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_254_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_255_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_255_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_256_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_256_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_257_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_257_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_258_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_258_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_260_ind_1', '#', $$Not applicable/No information provided/Earliest available publisher$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_260_ind_1', '2', $$Intervening publisher$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_260_ind_1', '3', $$Current/latest publisher$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_260_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_263_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_263_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_1', '#', $$Not applicable/No information provided/Earliest$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_1', '2', $$Intervening$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_1', '3', $$Current/latest$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_2', '0', $$Production$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_2', '1', $$Publication$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_2', '2', $$Distribution$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_2', '3', $$Manufacture$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_264_ind_2', '4', $$Copyright notice date$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_270_ind_1', '#', $$No level specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_270_ind_1', '1', $$Primary$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_270_ind_1', '2', $$Secondary$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_270_ind_2', '#', $$No type specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_270_ind_2', '0', $$Mailing$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_270_ind_2', '7', $$Type specified in subfield $i$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_300_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_300_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_306_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_306_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_307_ind_1', '#', $$Hours$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_307_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_307_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_310_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_310_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_321_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_321_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_336_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_336_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_337_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_337_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_338_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_338_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_340_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_340_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_1', '0', $$Horizontal coordinate system$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_1', '1', $$Vertical coordinate system$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '0', $$Geographic$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '1', $$Map projection$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '2', $$Grid coordinate system$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '3', $$Local planar$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '4', $$Local$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '5', $$Geodetic model$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '6', $$Altitude$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '7', $$Method specified in $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_342_ind_2', '8', $$Depth$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_343_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_343_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_344_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_344_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_345_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_345_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_346_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_346_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_347_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_347_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_351_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_351_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_352_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_352_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_1', '0', $$Document$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_1', '1', $$Title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_1', '2', $$Abstract$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_1', '3', $$Contents note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_1', '4', $$Author$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_1', '5', $$Record$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_1', '8', $$None of the above$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_355_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_357_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_357_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_362_ind_1', '0', $$Formatted style$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_362_ind_1', '1', $$Unformatted note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_362_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_363_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_363_ind_1', '0', $$Starting information$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_363_ind_1', '1', $$Ending information$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_363_ind_2', '#', $$Not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_363_ind_2', '0', $$Closed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_363_ind_2', '1', $$Open$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_365_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_365_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_366_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_366_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_380_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_380_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_381_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_381_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_382_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_382_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_383_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_383_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_384_ind_1', '#', $$Relationship to original unknown$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_384_ind_1', '0', $$Original key$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_384_ind_1', '1', $$Transposed key$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_384_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_440_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_490_ind_1', '0', $$Series not traced$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_490_ind_1', '1', $$Series traced$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_490_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_500_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_500_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_501_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_501_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_502_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_502_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_504_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_504_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_505_ind_1', '0', $$Contents$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_505_ind_1', '1', $$Incomplete contents$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_505_ind_1', '2', $$Partial contents$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_505_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_505_ind_2', '#', $$Basic$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_505_ind_2', '0', $$Enhanced$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_506_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_506_ind_1', '0', $$No restrictions$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_506_ind_1', '1', $$Restrictions apply$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_506_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_507_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_507_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_508_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_508_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_510_ind_1', '0', $$Coverage unknown$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_510_ind_1', '1', $$Coverage complete$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_510_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_511_ind_1', '0', $$No display constant generated$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_511_ind_1', '1', $$Cast$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_511_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_513_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_513_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_514_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_514_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_515_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_515_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_516_ind_1', '#', $$Type of file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_516_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_516_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_518_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_518_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_1', '#', $$Summary$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_1', '0', $$Subject$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_1', '1', $$Review$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_1', '2', $$Scope and content$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_1', '3', $$Abstract$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_1', '4', $$Content advice$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_520_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_1', '#', $$Audience$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_1', '0', $$Reading grade level$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_1', '1', $$Interest age level$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_1', '2', $$Interest grade level$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_1', '3', $$Special audience characteristics$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_1', '4', $$Motivation/interest level$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_521_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_522_ind_1', '#', $$Geographic coverage$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_522_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_522_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_524_ind_1', '#', $$Cite as$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_524_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_524_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_525_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_525_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_526_ind_1', '0', $$Reading program$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_526_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_526_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_530_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_530_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_533_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_533_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_534_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_534_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_535_ind_1', '1', $$Holder of originals$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_535_ind_1', '2', $$Holder of duplicates$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_535_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_536_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_536_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_538_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_538_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_540_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_540_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_541_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_541_ind_1', '0', $$Private$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_541_ind_1', '1', $$Not private$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_541_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_542_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_542_ind_1', '0', $$Private$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_542_ind_1', '1', $$Not private$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_542_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_544_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_544_ind_1', '0', $$Associated materials$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_544_ind_1', '1', $$Related materials$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_544_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_545_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_545_ind_1', '0', $$Biographical sketch$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_545_ind_1', '1', $$Administrative history$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_545_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_546_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_546_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_547_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_547_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_550_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_550_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_552_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_552_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_555_ind_1', '#', $$Indexes$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_555_ind_1', '0', $$Finding aids$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_555_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_555_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_556_ind_1', '#', $$Documentation$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_556_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_556_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_561_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_561_ind_1', '0', $$Private$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_561_ind_1', '1', $$Not private$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_561_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_562_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_562_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_563_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_563_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_565_ind_1', '#', $$File size$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_565_ind_1', '0', $$Case file characteristics$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_565_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_565_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_567_ind_1', '#', $$Methodology$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_567_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_567_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_580_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_580_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_581_ind_1', '#', $$Publications$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_581_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_581_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_583_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_583_ind_1', '0', $$Private$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_583_ind_1', '1', $$Not private$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_583_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_584_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_584_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_585_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_585_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_586_ind_1', '#', $$Awards$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_586_ind_1', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_586_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_588_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_588_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_600_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_610_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_611_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_1', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_630_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_648_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_1', '0', $$No level specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_1', '1', $$Primary$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_1', '2', $$Secondary$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_650_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_651_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_1', '0', $$No level specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_1', '1', $$Primary$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_1', '2', $$Secondary$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '0', $$Topical term$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '1', $$Personal name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '2', $$Corporate name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '3', $$Meeting name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '4', $$Chronological term$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '5', $$Geographic name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_653_ind_2', '6', $$Genre/form term$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_654_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_654_ind_1', '0', $$No level specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_654_ind_1', '1', $$Primary$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_654_ind_1', '2', $$Secondary$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_654_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_1', '#', $$Basic$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_1', '0', $$Faceted$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_655_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_656_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_656_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_657_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_657_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_658_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_658_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_662_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_662_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_700_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_700_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_700_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_700_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_700_ind_2', '2', $$Analytical entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_710_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_710_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_710_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_710_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_710_ind_2', '2', $$Analytical entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_711_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_711_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_711_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_711_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_711_ind_2', '2', $$Analytical entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_720_ind_1', '#', $$Not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_720_ind_1', '1', $$Personal$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_720_ind_1', '2', $$Other$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_720_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_1', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_730_ind_2', '2', $$Analytical entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_1', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_740_ind_2', '2', $$Analytical entry$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_751_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_751_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_752_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_752_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_753_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_753_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_754_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_754_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_758_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_758_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_760_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_760_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_760_ind_2', '#', $$Main series$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_760_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_762_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_762_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_762_ind_2', '#', $$Has subseries$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_762_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_765_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_765_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_765_ind_2', '#', $$Translation of$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_765_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_767_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_767_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_767_ind_2', '#', $$Translated as$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_767_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_770_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_770_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_770_ind_2', '#', $$Has supplement$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_770_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_772_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_772_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_772_ind_2', '#', $$Supplement to$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_772_ind_2', '0', $$Parent$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_772_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_773_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_773_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_773_ind_2', '#', $$In$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_773_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_774_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_774_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_774_ind_2', '#', $$Constituent unit$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_774_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_775_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_775_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_775_ind_2', '#', $$Other edition available$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_775_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_776_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_776_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_776_ind_2', '#', $$Available in another form$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_776_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_777_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_777_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_777_ind_2', '#', $$Issued with$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_777_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '0', $$Continues$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '1', $$Continues in part$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '2', $$Supersedes$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '3', $$Supersedes in part$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '4', $$Formed by the union of ... and ...$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '5', $$Absorbed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '6', $$Absorbed in part$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_780_ind_2', '7', $$Separated from$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '0', $$Continued by$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '1', $$Continued in part by$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '2', $$Superseded by$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '3', $$Superseded in part by$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '4', $$Absorbed by$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '5', $$Absorbed in part by$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '6', $$Split into ... and ...$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '7', $$Merged with ... to form ...$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_785_ind_2', '8', $$Changed back to$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_786_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_786_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_786_ind_2', '#', $$Data source$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_786_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_787_ind_1', '0', $$Display note$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_787_ind_1', '1', $$Do not display note$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_787_ind_2', '#', $$Related item$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_787_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_800_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_800_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_800_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_800_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_810_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_810_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_810_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_810_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_811_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_811_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_811_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_811_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_830_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_841_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_841_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_842_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_842_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_843_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_843_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_844_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_844_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_845_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_845_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_850_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_850_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '0', $$Library of Congress classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '1', $$Dewey Decimal classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '2', $$National Library of Medicine classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '3', $$Superintendent of Documents classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '4', $$Shelving control number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '5', $$Title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '6', $$Shelved separately$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_1', '8', $$Other scheme$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_2', '0', $$Not enumeration$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_2', '1', $$Primary enumeration$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_852_ind_2', '2', $$Alternative enumeration$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_1', '0', $$Cannot compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_1', '1', $$Can compress but not expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_1', '2', $$Can compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_1', '3', $$Unknown$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_2', '0', $$Captions verified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_2', '1', $$Captions verified; all levels may not be present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_2', '2', $$Captions unverified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_853_ind_2', '3', $$Captions unverified; all levels may not be present$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_1', '0', $$Cannot compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_1', '1', $$Can compress but not expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_1', '2', $$Can compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_1', '3', $$Unknown$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_2', '0', $$Captions verified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_2', '1', $$Captions verified; all levels may not be present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_2', '2', $$Captions unverified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_854_ind_2', '3', $$Captions unverified; all levels may not be present$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_855_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_855_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_1', '0', $$Email$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_1', '1', $$FTP$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_1', '2', $$Remote login (Telnet)$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_1', '3', $$Dial-up$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_1', '4', $$HTTP$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_1', '7', $$Method specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_2', '0', $$Resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_2', '1', $$Version of resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_2', '2', $$Related resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_856_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_2', '0', $$Compressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_2', '1', $$Uncompressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_2', '2', $$Compressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_2', '3', $$Uncompressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_863_ind_2', '4', $$Item(s) not published$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_2', '0', $$Compressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_2', '1', $$Uncompressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_2', '2', $$Compressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_2', '3', $$Uncompressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_864_ind_2', '4', $$Item(s) not published$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_865_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_865_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_865_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_865_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_865_ind_2', '1', $$Uncompressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_865_ind_2', '3', $$Uncompressed, use textual display$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_2', '0', $$Non-standard$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_2', '1', $$ANSI/NISO Z39.71 or ISO 10324$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_2', '2', $$ANSI Z39.42$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_866_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_2', '0', $$Non-standard$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_2', '1', $$ANSI/NISO Z39.71 or ISO 10324$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_2', '2', $$ANSI Z39.42$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_867_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_2', '0', $$Non-standard$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_2', '1', $$ANSI/NISO Z39.71 or ISO 10324$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_2', '2', $$ANSI Z39.42$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_868_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_876_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_876_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_877_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_877_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_878_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_878_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_882_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_882_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_886_ind_1', '0', $$Leader$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_886_ind_1', '1', $$Variable control fields (002-009)$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_886_ind_1', '2', $$Variable data fields (010-999)$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_886_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_887_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_887_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_010_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_010_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_014_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_014_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_016_ind_1', '#', $$Library and Archives Canada$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_016_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_016_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_020_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_020_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_022_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_022_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_024_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_024_ind_1', '8', $$Unspecified type of standard number or code$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_024_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_031_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_031_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_034_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_034_ind_2', '#', $$Not applicable$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_034_ind_2', '0', $$Outer ring$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_034_ind_2', '1', $$Exclusion ring$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_035_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_035_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_040_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_040_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_042_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_042_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_043_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_043_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_045_ind_1', '#', $$Subfield $b or $c not present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_045_ind_1', '0', $$Single date/time$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_045_ind_1', '1', $$Multiple single dates/times$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_045_ind_1', '2', $$Range of dates/times$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_045_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_046_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_046_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_050_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_050_ind_2', '0', $$Assigned by LC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_050_ind_2', '4', $$Assigned by agency other than LC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_052_ind_1', '#', $$Library of Congress Classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_052_ind_1', '1', $$U.S. Dept. of Defense Classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_052_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_052_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_053_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_053_ind_2', '0', $$Assigned by LC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_053_ind_2', '4', $$Assigned by agency other than LC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_055_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_055_ind_2', '0', $$Assigned by LAC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_055_ind_2', '4', $$Assigned by agency other than LAC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_060_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_060_ind_2', '0', $$Assigned by NLM$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_060_ind_2', '4', $$Assigned by agency other than NLM$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_065_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_065_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_066_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_066_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_070_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_070_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_072_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_072_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_072_ind_2', '0', $$NAL subject category code list$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_072_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_073_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_073_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_080_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_080_ind_1', '0', $$Full$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_080_ind_1', '1', $$Abridged$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_080_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_082_ind_1', '0', $$Full$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_082_ind_1', '1', $$Abridged$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_082_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_082_ind_2', '0', $$Assigned by LC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_082_ind_2', '4', $$Assigned by agency other than LC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_083_ind_1', '0', $$Full$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_083_ind_1', '1', $$Abridged$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_083_ind_2', '0', $$Assigned by LC$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_083_ind_2', '4', $$Assigned by agency other than LC$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_086_ind_1', '#', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_086_ind_1', '0', $$Superintendent of Documents Classification System$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_086_ind_1', '1', $$Government of Canada Publications: Outline of Classification$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_086_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_087_ind_1', '#', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_087_ind_1', '0', $$Superintendent of Documents Classification System$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_087_ind_1', '1', $$Government of Canada Publications: Outline of Classification$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_087_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_100_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_100_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_100_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_100_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_110_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_110_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_110_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_110_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_111_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_111_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_111_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_111_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_130_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_148_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_148_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_150_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_150_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_151_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_151_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_155_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_155_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_180_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_180_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_181_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_181_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_182_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_182_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_185_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_185_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_260_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_260_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_336_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_336_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_360_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_360_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_370_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_370_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_371_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_371_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_372_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_372_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_373_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_373_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_374_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_374_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_375_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_375_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_376_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_376_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_377_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_377_ind_2', '#', $$MARC language code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_377_ind_2', '7', $$Source specified in $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_380_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_380_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_381_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_381_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_382_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_382_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_383_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_383_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_384_ind_1', '#', $$Relationship to original unknown$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_384_ind_1', '0', $$Original key$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_384_ind_1', '1', $$Transposed key$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_384_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_400_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_400_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_400_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_400_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_410_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_410_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_410_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_410_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_411_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_411_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_411_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_411_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_430_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_448_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_448_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_450_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_450_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_451_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_451_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_455_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_455_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_480_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_480_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_481_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_481_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_482_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_482_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_485_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_485_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_500_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_500_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_500_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_500_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_510_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_510_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_510_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_510_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_511_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_511_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_511_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_511_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '0', $$No nonfiling characters$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '1', $$Number of nonfiling characters - 1$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '2', $$Number of nonfiling characters - 2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '3', $$Number of nonfiling characters - 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '4', $$Number of nonfiling characters - 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '5', $$Number of nonfiling characters - 5$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '6', $$Number of nonfiling characters - 6$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '7', $$Number of nonfiling characters - 7$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '8', $$Number of nonfiling characters - 8$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_530_ind_2', '9', $$Number of nonfiling characters - 9$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_548_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_548_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_550_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_550_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_551_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_551_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_555_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_555_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_580_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_580_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_581_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_581_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_582_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_582_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_585_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_585_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_640_ind_1', '0', $$Formatted style$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_640_ind_1', '1', $$Unformatted style$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_640_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_641_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_641_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_642_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_642_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_643_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_643_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_644_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_644_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_645_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_645_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_646_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_646_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_663_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_663_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_664_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_664_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_665_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_665_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_666_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_666_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_667_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_667_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_670_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_670_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_675_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_675_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_678_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_678_ind_1', '0', $$Biographical sketch$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_678_ind_1', '1', $$Administrative history$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_678_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_680_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_680_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_681_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_681_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_682_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_682_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_688_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_688_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_1', '0', $$Forename$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_1', '1', $$Surname$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_1', '3', $$Family name$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_700_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_710_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_1', '0', $$Inverted name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_1', '1', $$Jurisdiction name$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_1', '2', $$Name in direct order$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_711_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_730_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_748_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_750_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_751_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_755_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_780_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_781_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_782_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_785_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '0', $$Library of Congress Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '1', $$LC subject headings for children's literature$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '2', $$Medical Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '3', $$National Agricultural Library subject authority file$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '4', $$Source not specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '5', $$Canadian Subject Headings$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '6', $$Répertoire de vedettes-matière$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_788_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_1', '0', $$Email$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_1', '1', $$FTP$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_1', '2', $$Remote login (Telnet)$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_1', '3', $$Dial-up$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_1', '4', $$HTTP$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_1', '7', $$Method specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_2', '0', $$Resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_2', '1', $$Version of resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_2', '2', $$Related resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_authority_856_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_010_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_010_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_014_ind_1', '0', $$Holdings record number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_014_ind_1', '1', $$Bibliographic record number$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_014_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_016_ind_1', '#', $$Library and Archives Canada$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_016_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_016_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_017_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_017_ind_2', '#', $$Copyright or legal deposit number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_017_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_020_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_020_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_022_ind_1', '#', $$No level specified$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_022_ind_1', '0', $$Continuing resource of international interest$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_022_ind_1', '1', $$Continuing resource not of international interest$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_022_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_1', '0', $$International Standard Recording Code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_1', '1', $$Universal Product Code$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_1', '2', $$International Standard Music Number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_1', '3', $$International Article Number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_1', '4', $$Serial Item and Contribution Identifier$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_1', '8', $$Unspecified type of standard number or code$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_2', '0', $$No difference$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_024_ind_2', '1', $$Difference$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_027_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_027_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_030_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_030_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_035_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_035_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_040_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_040_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_066_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_066_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_337_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_337_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_338_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_338_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_506_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_506_ind_1', '0', $$No restrictions$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_506_ind_1', '1', $$Restrictions apply$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_506_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_538_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_538_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_541_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_541_ind_1', '0', $$Private$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_541_ind_1', '1', $$Not private$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_541_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_561_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_561_ind_1', '0', $$Private$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_561_ind_1', '1', $$Not private$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_561_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_562_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_562_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_563_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_563_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_583_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_583_ind_1', '0', $$Private$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_583_ind_1', '1', $$Not private$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_583_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_841_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_841_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_842_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_842_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_843_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_843_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_844_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_844_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_845_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_845_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '0', $$Library of Congress classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '1', $$Dewey Decimal classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '2', $$National Library of Medicine classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '3', $$Superintendent of Documents classification$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '4', $$Shelving control number$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '5', $$Title$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '6', $$Shelved separately$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '7', $$Source specified in subfield $2$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_1', '8', $$Other scheme$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_2', '0', $$Not enumeration$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_2', '1', $$Primary enumeration$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_852_ind_2', '2', $$Alternative enumeration$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_1', '0', $$Cannot compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_1', '1', $$Can compress but not expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_1', '2', $$Can compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_1', '3', $$Unknown$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_2', '0', $$Captions verified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_2', '1', $$Captions verified; all levels may not be present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_2', '2', $$Captions unverified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_853_ind_2', '3', $$Captions unverified; all levels may not be present$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_1', '0', $$Cannot compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_1', '1', $$Can compress but not expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_1', '2', $$Can compress or expand$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_1', '3', $$Unknown$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_2', '0', $$Captions verified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_2', '1', $$Captions verified; all levels may not be present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_2', '2', $$Captions unverified; all levels present$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_854_ind_2', '3', $$Captions unverified; all levels may not be present$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_855_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_855_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_1', '0', $$Email$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_1', '1', $$FTP$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_1', '2', $$Remote login (Telnet)$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_1', '3', $$Dial-up$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_1', '4', $$HTTP$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_1', '7', $$Method specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_2', '0', $$Resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_2', '1', $$Version of resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_2', '2', $$Related resource$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_856_ind_2', '8', $$No display constant generated$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_2', '0', $$Compressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_2', '1', $$Uncompressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_2', '2', $$Compressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_2', '3', $$Uncompressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_863_ind_2', '4', $$Item(s) not published$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_2', '0', $$Compressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_2', '1', $$Uncompressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_2', '2', $$Compressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_2', '3', $$Uncompressed, use textual display$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_864_ind_2', '4', $$Item(s) not published$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_865_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_865_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_865_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_865_ind_2', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_865_ind_2', '1', $$Uncompressed$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_865_ind_2', '3', $$Uncompressed, use textual display$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_2', '0', $$Non-standard$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_2', '1', $$ANSI/NISO Z39.71 or ISO 10324$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_2', '2', $$ANSI Z39.42$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_866_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_2', '0', $$Non-standard$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_2', '1', $$ANSI/NISO Z39.71 or ISO 10324$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_2', '2', $$ANSI Z39.42$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_867_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_1', '#', $$No information provided$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_1', '3', $$Holdings level 3$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_1', '4', $$Holdings level 4$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_1', '5', $$Holdings level 4 with piece designation$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_2', '0', $$Non-standard$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_2', '1', $$ANSI/NISO Z39.71 or ISO 10324$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_2', '2', $$ANSI Z39.42$$, FALSE, TRUE);
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_868_ind_2', '7', $$Source specified in subfield $2$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_876_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_876_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_877_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_877_ind_2', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_878_ind_1', '#', $$Undefined$$, FALSE, TRUE);

INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_serial_878_ind_2', '#', $$Undefined$$, FALSE, TRUE);

COMMIT;


-- carve out a slot of 10k IDs for stock CCVMs
SELECT SETVAL('config.coded_value_map_id_seq'::TEXT, 10000);


