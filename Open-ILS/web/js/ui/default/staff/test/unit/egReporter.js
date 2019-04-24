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

    /** template conversion tests **/
    var v4Templates = [
         '{"version":4,"doc_url":"","core_class":"bre","select":[{"alias":"Title Proper (normalized)","field_doc":"","column":{"colname":"title","transform":"Bare","transform_label":"Raw Data"},"path":"bre-simple_record-rmsr-title","relation":"938089c53626281c03f9f40622093fcc"}],"from":{"path":"bre-simple_record","table":"biblio.record_entry","alias":"a0a5898f5f47b01a3943462dbf1c45ad","join":{"id-mfr-record-a0a5898f5f47b01a3943462dbf1c45ad":{"key":"record","type":"left","path":"bre-full_record_entries-mfr","table":"metabib.full_rec","label":"Bibliographic Record :: Flattened MARC Fields ","alias":"6da08cb48d3b764920485d2d40a4145c","idlclass":"mfr","template_path":"bre-full_record_entries"},"id-rmsr-id-a0a5898f5f47b01a3943462dbf1c45ad":{"key":"id","type":"left","path":"bre-simple_record-rmsr","table":"reporter.materialized_simple_record","label":"Bibliographic Record :: Simple Record Extracts ","alias":"938089c53626281c03f9f40622093fcc","idlclass":"rmsr","template_path":"bre-simple_record"}}},"where":[{"alias":"Tag","field_doc":"","column":{"colname":"tag","transform":"Bare","transform_label":"Raw Data"},"path":"bre-full_record_entries-mfr-tag","relation":"6da08cb48d3b764920485d2d40a4145c","condition":{"ilike":"::P0"}},{"alias":"Subfield","field_doc":"","column":{"colname":"subfield","transform":"Bare","transform_label":"Raw Data"},"path":"bre-full_record_entries-mfr-subfield","relation":"6da08cb48d3b764920485d2d40a4145c","condition":{"ilike":"::P1"}},{"alias":"Normalized Value","field_doc":"","column":{"colname":"value","transform":"Bare","transform_label":"Raw Data"},"path":"bre-full_record_entries-mfr-value","relation":"6da08cb48d3b764920485d2d40a4145c","condition":{"ilike":"::P2"}}],"having":[],"order_by":[],"rel_cache":{"order_by":[{"relation":"938089c53626281c03f9f40622093fcc","field":"title"}],"6da08cb48d3b764920485d2d40a4145c":{"label":"Bibliographic Record :: Flattened MARC Fields ","alias":"6da08cb48d3b764920485d2d40a4145c","path":"bre-full_record_entries","join":"","reltype":"has_many","idlclass":"mfr","table":"metabib.full_rec","fields":{"dis_tab":{},"filter_tab":{"tag":{"colname":"tag","transform":"Bare","aggregate":null,"params":null,"transform_label":"Raw Data","alias":"Tag","field_doc":"","join":"","datatype":"text","op":"ilike","op_label":"Contains Matching substring (ignore case)","op_value":{}},"subfield":{"colname":"subfield","transform":"Bare","aggregate":null,"params":null,"transform_label":"Raw Data","alias":"Subfield","field_doc":"","join":"","datatype":"text","op":"ilike","op_label":"Contains Matching substring (ignore case)","op_value":{}},"value":{"colname":"value","transform":"Bare","aggregate":null,"params":null,"transform_label":"Raw Data","alias":"Normalized Value","field_doc":"","join":"","datatype":"text","op":"ilike","op_label":"Contains Matching substring (ignore case)","op_value":{}}},"aggfilter_tab":{}}},"938089c53626281c03f9f40622093fcc":{"label":"Bibliographic Record :: Simple Record Extracts ","alias":"938089c53626281c03f9f40622093fcc","path":"bre-simple_record","join":"","reltype":"might_have","idlclass":"rmsr","table":"reporter.materialized_simple_record","fields":{"dis_tab":{"title":{"colname":"title","transform":"Bare","aggregate":null,"params":null,"transform_label":"Raw Data","alias":"Title Proper (normalized)","field_doc":"","join":"","datatype":"text","op":"=","op_label":"Equals","op_value":{}}},"filter_tab":{},"aggfilter_tab":{}}}}}'
    ];

    describe('egReporterTemplateConversionTests', function() {
        it('initialize for template conversion tests', inject(function(egIDL, egCore) {
            egIDL.parseIDL();
        }));
        it('test template conversion does not crash', inject(function(egIDL) {
            angular.forEach(v4Templates, function(tmpl, i) {
                var rt = new egIDL.rt();
                rt.data(tmpl);
                rt.name('Test template #' + i);
                rt.data = angular.fromJson(rt.data());
                expect(rt.data.version).toBeLessThan(5);
                reportEditScope.changeCoreSource(rt.data.core_class);
                reportEditScope.upgradeTemplate(rt);
                expect(rt.data.version).toEqual(5);
            });
        }));
    });


});
