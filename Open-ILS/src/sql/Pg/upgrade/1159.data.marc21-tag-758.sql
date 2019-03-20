BEGIN;

SELECT evergreen.upgrade_deps_block_check('1159', :eg_version);

INSERT INTO config.marc_field(marc_format, marc_record_type, tag, name, description,
                              fixed_field, repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', $$Resource Identifier$$, $$An identifier for a resource that is either the resource described in the bibliographic record or a resource to which it is related. Resources thus identified may include, but are not limited to, FRBR works, expressions, manifestations, and items. The field does not prescribe a particular content standard or data model.$$,
FALSE, TRUE, FALSE, FALSE);
INSERT INTO config.record_attr_definition(name, label)
VALUES ('marc21_biblio_758_ind_1', 'MARC 21 biblio field 758 indicator position 1');
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_758_ind_1', '#', $$Undefined$$, FALSE, TRUE);
INSERT INTO config.record_attr_definition(name, label)
VALUES ('marc21_biblio_758_ind_2', 'MARC 21 biblio field 758 indicator position 2');
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_758_ind_2', '#', $$Undefined$$, FALSE, TRUE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', 'a', $$Label$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', 'i', $$Relationship information$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '0', $$Authority record control number or standard number$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '1', $$Real World Object URI$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '3', $$Materials specified$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '4', $$Relationship$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '5', $$Institution to which field applies$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '6', $$Linkage$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '8', $$Field link and sequence number$$,
TRUE, FALSE, FALSE);

COMMIT;
