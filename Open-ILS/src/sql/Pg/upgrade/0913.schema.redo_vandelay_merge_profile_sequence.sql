BEGIN;

SELECT evergreen.upgrade_deps_block_check('0913', :eg_version);

--stock evergreen comes with 2 merge profiles; move any custom profiles
UPDATE vandelay.merge_profile SET id = id + 100 WHERE id > 2;

--update the same ids in org unit settings, stored in double quotes
UPDATE actor.org_unit_setting
    SET value = '"' || merge_profile_id+100 || '"'
	FROM (
		SELECT id, (regexp_matches(value, '"(\d+)"'))[1]::int as merge_profile_id FROM actor.org_unit_setting
		WHERE name IN (
			'acq.upload.default.vandelay.low_quality_fall_thru_profile',
			'acq.upload.default.vandelay.merge_profile'
		)
	) as foo
	WHERE actor.org_unit_setting.id = foo.id
	AND foo.merge_profile_id > 2;

--set sequence's next value to 100, or more if necessary
SELECT SETVAL('vandelay.merge_profile_id_seq', GREATEST(100, (SELECT MAX(id) FROM vandelay.merge_profile)));

COMMIT;
