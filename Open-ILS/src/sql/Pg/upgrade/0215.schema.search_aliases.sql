BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0215'); -- miker


CREATE TABLE config.metabib_search_alias (
    alias       TEXT    PRIMARY KEY,
    field_class TEXT    NOT NULL REFERENCES config.metabib_class (name),
    field       INT     REFERENCES config.metabib_field (id)
);


INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('kw','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.keyword','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.publisher','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.identifier','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.subjecttitle','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.genre','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.edition','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('srw.serverchoice','keyword');

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('au','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('name','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('creator','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.author','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.name','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.creator','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.contributor','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.name','author');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namepersonal','author',8);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namepersonalfamily','author',8);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namepersonalgiven','author',8);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namecorporate','author',7);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.nameconference','author',9);

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('ti','title');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.title','title');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.title','title');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titleabbreviated','title',2);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titleuniform','title',5);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titletranslated','title',3);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titlealternative','title',4);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.title','title',2);

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('su','subject');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.subject','subject');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.subject','subject');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.subjectplace','subject',11);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.subjectname','subject',12);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.subjectoccupation','subject',16);

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('se','series');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.series','series');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titleseries','series',1);

COMMIT;

