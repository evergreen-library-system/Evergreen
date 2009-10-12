BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0033'); -- miker


INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'NACO Normalize',
	'Apply NACO normalization rules to the extracted text.  See http://www.loc.gov/catdir/pcc/naco/normrule-2.html for details.',
	'naco_normalize',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Normalize date range',
	'Split date ranges in the form of "XXXX-YYYY" into "XXXX YYYY" for proper index.',
	'split_date_range',
	1
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'NACO Normalize -- retain first comma',
	'Apply NACO normalization rules to the extracted text, retaining the first comma.  See http://www.loc.gov/catdir/pcc/naco/normrule-2.html for details.',
	'naco_normalize_keep_comma',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Strip Diacritics',
	'Convert text to NFD form and remove non-spacing combining marks.',
	'remove_diacritics',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Up-case',
	'Convert text upper case.',
	'uppercase',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Down-case',
	'Convert text lower case.',
	'lowercase',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Extract Dewey-like number',
	'Extract a string of numeric characters ther resembles a DDC number.',
	'call_number_dewey',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Left truncation',
	'Discard the specified number of characters from the left side of the string.',
	'left_trunc',
	1
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Right truncation',
	'Include only the specified number of characters from the left side of the string.',
	'right_trunc',
	1
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'First word',
	'Include only the first space-separated word of a string.',
	'first_word',
	0
);


INSERT INTO config.metabib_field_index_norm_map (field,norm)
	SELECT	m.id,
		i.id
	  FROM	config.metabib_field m,
		config.index_normalizer i
	  WHERE	i.func IN ('naco_normalize','split_date_range');

COMMIT;

