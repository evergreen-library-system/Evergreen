-- serials schema tweaks

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0403'); -- dbwells via miker

------- caption_and_pattern changes
ALTER TABLE serial.caption_and_pattern
ADD COLUMN start_date	TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE serial.caption_and_pattern
ADD COLUMN end_date	TIMESTAMP WITH TIME ZONE;


------- *_summary changes
ALTER TABLE serial.basic_summary
ADD COLUMN show_generated	BOOL	NOT NULL DEFAULT TRUE;

ALTER TABLE serial.supplement_summary
ADD COLUMN show_generated	BOOL	NOT NULL DEFAULT TRUE;

ALTER TABLE serial.index_summary
ADD COLUMN show_generated	BOOL	NOT NULL DEFAULT TRUE;


------- distribution changes
ALTER TABLE serial.distribution

ADD COLUMN summary_method	TEXT	CONSTRAINT summary_method_check CHECK (
					summary_method IS NULL
					OR summary_method IN ( 'add_to_sre',
					'merge_with_sre', 'use_sre_only',
					'use_sdist_only'));

COMMIT;
