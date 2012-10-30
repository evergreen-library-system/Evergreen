-- Use MARC relator codes (710 subfield 4) to index corporate authors, along
-- with the existing relator text (710 subfield e)

UPDATE config.metabib_field
  SET xpath = $$//mods32:mods/mods32:name[@type='corporate'
    and (mods32:role/mods32:roleTerm[text()='creator']
      or mods32:role/mods32:roleTerm[text()='aut']
      or mods32:role/mods32:roleTerm[text()='cre']
    )]$$
  WHERE id = 7
;

SELECT metabib.reingest_metabib_field_entries(record, TRUE, TRUE, FALSE)
  FROM metabib.full_rec
  WHERE tag = '710'
    AND subfield = '4'
    AND value IN ('cre', 'aut')
;
