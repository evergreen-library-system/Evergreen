-- Create courses
INSERT INTO asset.course_module_course
(name, course_number, owning_lib) VALUES
('History of Indonesia', 'HST243', 4),
('Graphic Design II', 'AA222', 6),
('Typographical Design I', 'AA224', 6),
('Typographical Design II', 'AA226', 6),
('Equine Diseases and Parasites', 'AT155', 6);


-- Associate materials with the courses
INSERT INTO asset.course_module_course_materials
(course, record, relationship) VALUES
(1, 200, 'Required'),
(1, 201, 'Optional');

INSERT INTO asset.course_module_course_materials
(course, record)
SELECT acmc.id, bre.id
FROM asset.course_module_course acmc
INNER JOIN biblio.record_entry bre ON
course_number=last_xact_id;