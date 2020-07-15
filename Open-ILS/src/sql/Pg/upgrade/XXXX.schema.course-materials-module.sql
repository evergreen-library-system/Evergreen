BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE asset.course_module_course (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    course_number   TEXT NOT NULL,
    section_number  TEXT,
    owning_lib      INT REFERENCES actor.org_unit (id),
    is_archived        BOOLEAN NOT NULL DEFAULT false;
);

CREATE TABLE asset.course_module_course_users (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    usr             INT NOT NULL REFERENCES actor.usr (id),
    usr_role        TEXT,
    is_public       BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE asset.course_module_course_materials (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    item            INT REFERENCES asset.copy (id),
    relationship    TEXT,
    record          INT REFERENCES biblio.record_entry (id),
    temporary_record         BOOLEAN,
    original_location        INT REFERENCES asset.copy_location,
    original_status          INT REFERENCES config.copy_status,
    original_circ_modifier   TEXT, --REFERENCES config.circ_modifier,
    original_callnumber      INT REFERENCES asset.call_number,
    unique (course, item, record)
);

INSERT INTO permission.perm_list(id, code, description)
    VALUES (
        624,
        'MANAGE_RESERVES',
        oils_i18n_gettext(
            624,
            'Allows user to manage Courses, Course Materials, and associate Users with Courses.',
            'ppl',
            'description'
        )
    );

INSERT INTO permission.grp_perm_map(perm, grp, depth) VALUES (624, 9, 0), (624, 11, 0), (624, 12, 0), (624, 13, 0);

INSERT INTO config.org_unit_setting_type 
    (grp, name, datatype, label, description, fm_class)
VALUES (
    'circ',
    'circ.course_materials_opt_in', 'bool',
    oils_i18n_gettext(
        'circ.course_materials_opt_in',
        'Opt Org Unit into the Course Materials Module',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.course_materials_opt_in',
        'If enabled, the Org Unit will utilize Course Material functionality.'
        'coust',
        'description'
    ), null
), (
    'circ',
    'circ.course_materials_browse_by_instructor', 'bool',
    oils_i18n_gettext(
        'circ.course_materials_browse_by_instructor',
        'Allow users to browse Courses by Instructor',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.course_materials_browse_by_instructor',
        'If enabled, the Org Unit will allow OPAC users to browse Courses by instructor name.'
        'coust',
        'description'
    ), null
), (
    'circ',
    'circ.course_materials_brief_record_bib_source', 'link',
    oils_i18n_gettext(
        'circ.course_materials_brief_record_bib_source',
        'Bib source for brief records created in the course materials module',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'circ.course_materials_brief_record_bib_source',
        'The course materials module will use this bib source for any new brief bibliographic records made inside that module. For best results, use a transcendant bib source.',
        'coust', 'description'
    ), 'cbs'

);

INSERT INTO config.bib_source (quality, source, transcendant) VALUES
    (1, oils_i18n_gettext(1, 'Course materials module', 'cbs', 'source'), TRUE);

INSERT INTO actor.org_unit_setting (org_unit, name, value)
    SELECT 1, 'circ.course_materials_brief_record_bib_source', id
    FROM config.bib_source
    WHERE source='Course materials module';

COMMIT;
