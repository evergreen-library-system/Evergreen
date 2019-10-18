BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE asset.course_module_course (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    course_number   TEXT NOT NULL,
    section_number  TEXT,
    owning_lib      INT REFERENCES actor.org_unit (id)
);

CREATE TABLE asset.course_module_course_users (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    usr             INT NOT NULL REFERENCES actor.usr (id),
    usr_role        TEXT
);

CREATE TABLE asset.course_module_course_materials (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    item            INT NOT NULL REFERENCES asset.copy (id),
    relationship    TEXT
);

CREATE TABLE asset.course_module_non_cat_course_materials (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    item            TEXT NOT NULL,
    url             TEXT,
    relationship    TEXT
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
    (grp, name, datatype, label, description)
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
    )
);

COMMIT;
