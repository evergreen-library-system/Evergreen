BEGIN;

SELECT evergreen.upgrade_deps_block_check('0938', :eg_version);

INSERT INTO config.record_attr_definition (name, label, format, xpath, vocabulary) VALUES (
    'content_type', oils_i18n_gettext('content_type', 'Content Type', 'ccvm', 'label'),
    'marcxml',
    $$//marc:datafield[@tag='336']/marc:subfield[@code='a']$$,
    'http://rdaregistry.info/termList/RDAContentType'
);
INSERT INTO config.record_attr_definition (name, label, format, xpath, vocabulary) VALUES (
    'media_type', oils_i18n_gettext('media_type', 'Media Type', 'ccvm', 'label'),
    'marcxml',
    $$//marc:datafield[@tag='337']/marc:subfield[@code='a']$$,
    'http://rdaregistry.info/termList/RDAMediaType'
);
INSERT INTO config.record_attr_definition (name, label, format, xpath, vocabulary) VALUES (
    'carrier_type', oils_i18n_gettext('carrier_type', 'Carrier Type', 'ccvm', 'label'),
    'marcxml',
    $$//marc:datafield[@tag='338']/marc:subfield[@code='a']$$,
    'http://rdaregistry.info/termList/RDACarrierType'
);

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

UPDATE config.marc_subfield set value_ctype = 'content_type'
WHERE  tag = '336' AND code = 'a' AND marc_record_type = 'biblio';
UPDATE config.marc_subfield set value_ctype = 'media_type'
WHERE  tag = '337' AND code = 'a' AND marc_record_type = 'biblio';
UPDATE config.marc_subfield set value_ctype = 'carrier_type'
WHERE  tag = '338' AND code = 'a' AND marc_record_type = 'biblio';

COMMIT;
