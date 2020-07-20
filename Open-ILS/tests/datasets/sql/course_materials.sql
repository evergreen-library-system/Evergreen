-- Create courses
INSERT INTO asset.course_module_course
(name, course_number, owning_lib) VALUES
('History of Indonesia', 'HST243', 1);


-- Associate materials with the courses
INSERT INTO asset.course_module_course_materials
(course, record, relationship) VALUES
(1, 200, 'Required'),
(1, 201, 'Optional');

