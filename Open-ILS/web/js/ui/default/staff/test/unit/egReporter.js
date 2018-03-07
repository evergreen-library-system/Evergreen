'use strict';

describe('egReporterTest', function() {
    beforeEach(module('egCoreMod'));
    beforeEach(module('egReportMod'));
    beforeEach(module('egReporter'));

    var reportEditCtrl, reportEditScope;
    beforeEach(inject(function ($rootScope, $controller, $location, egIDL) {
        egIDL.parseIDL();
        reportEditScope = $rootScope.$new();
        reportEditCtrl = $controller('ReporterTemplateEdit', {$scope: reportEditScope});
    }));

    /** egReportTemplateSvc tests **/
    describe('egReportTemplateSvcTests', function() {

        it('egReportTemplateSvc should start with empty lists', inject(function(egReportTemplateSvc) {
            expect(egReportTemplateSvc.display_fields.length).toEqual(0);
            expect(egReportTemplateSvc.filter_fields.length).toEqual(0);
        }));

    });

    // test template
    var display_fields = [{
        "name": "family_name",
        "label": "Last Name",
        "datatype": "text",
        "index": 0,
        "path": [
            {
            "label": "ILS User",
            "id": "au",
            "jtype": "inner",
            "classname": "au",
            "struct": {
                "name": "au",
                "label": "ILS User",
                "table": "actor.usr",
                "core": true,
                "pkey": "id",
                "pkey_sequence": "actor.usr_id_seq",
                "core_label": "Core sources",
                "classname": "au"
            },
            "table": "actor.usr"
            }
        ],
        "path_label": "ILS User",
        "transform": {
            "transform": "Bare",
            "label": "Raw Data",
            "aggregate": false
        },
        "doc_text": ""
        }, {
        "name": "first_given_name",
        "label": "First Name",
        "datatype": "text",
        "index": 1,
        "path": [
            {
            "label": "ILS User",
            "id": "au",
            "jtype": "inner",
            "classname": "au",
            "struct": {
                "name": "au",
                "label": "ILS User",
                "table": "actor.usr",
                "core": true,
                "pkey": "id",
                "pkey_sequence": "actor.usr_id_seq",
                "core_label": "Core sources",
                "classname": "au"
            },
            "table": "actor.usr"
            }
        ],
        "path_label": "ILS User",
        "transform": {
            "transform": "Bare",
            "label": "Raw Data",
            "aggregate": false
        },
        "doc_text": ""
        }, {
        "name": "value",
        "label": "Note Content",
        "datatype": "text",
        "index": 2,
        "path": [
            {
            "label": "ILS User",
            "id": "au",
            "jtype": "inner",
            "classname": "au",
            "struct": {
                "name": "au",
                "label": "ILS User",
                "table": "actor.usr",
                "core": true,
                "pkey": "id",
                "pkey_sequence": "actor.usr_id_seq",
                "core_label": "Core sources",
                "classname": "au"
            },
            "table": "actor.usr"
            },
            {
            "label": "User Notes",
            "from": "au",
            "link": {
                "name": "notes",
                "label": "User Notes",
                "virtual": true,
                "type": "link",
                "key": "usr",
                "class": "aun",
                "reltype": "has_many",
                "datatype": "link"
            },
            "id": "au.aun",
            "jtype": "left",
            "uplink": {
                "name": "notes",
                "label": "User Notes",
                "virtual": true,
                "type": "link",
                "key": "usr",
                "class": "aun",
                "reltype": "has_many",
                "datatype": "link"
            },
            "classname": "aun",
            "struct": {
                "name": "aun",
                "label": "User Note",
                "table": "actor.usr_note",
                "pkey": "id",
                "pkey_sequence": "actor.usr_note_id_seq",
                "core_label": "Non-core sources",
                "classname": "aun"
            },
            "table": "actor.usr_note"
            }
        ],
        "path_label": "ILS User -> User Notes (left)",
        "transform": {
            "transform": "Bare",
            "label": "Raw Data",
            "aggregate": false
        },
        "doc_text": ""
    }];

    describe('egReporterTemplateEditTests', function() {
        it('initialize and set core source for ReporterTemplateEdit', inject(function(egIDL, egCore) {
            egIDL.parseIDL();

            // initialize
            expect(reportEditScope.class_tree.length).toEqual(0);
            expect(reportEditScope.coreSourceChosen).toEqual(false);

            // set core source
            reportEditScope.changeCoreSource('au');
            expect(reportEditScope.coreSourceChosen).toEqual(true);
            expect(reportEditScope.class_tree.length).toEqual(1);

        }));

        it('LP#1721807: construct join key correctly when using virtual field', function() {
            var tmpl = reportEditScope._mergePaths(display_fields);
            expect(tmpl).toBeDefined();
            expect(Object.keys(tmpl)).toContain('join');
            expect(Object.keys(tmpl.join).length).toEqual(1);
            var join_key = Object.keys(tmpl.join)[0];
            var lcol = join_key.split(/-/)[0];
            expect(lcol).toEqual('id');
        });

    });

});
