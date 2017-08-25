/**
 * Simple directive for rending the HTML view of a MARC record.
 *
 * <eg-record-html record-id="myRecordIdScopeVariable"></eg-record-id>
 * OR
 * <eg-record-html marc-xml="myMarcXmlVariable"></eg-record-html>
 *
 * The value of myRecordIdScopeVariable is watched internally and the 
 * record is updated to match.
 */
angular.module('egCoreMod')

.directive('egRecordHtml', function() {
    return {
        restrict : 'AE',
        scope : {
            recordId : '=',
            marcXml  : '@',
        },
        link : function(scope, element, attrs) {
            scope.element = angular.element(element);

            // kill refs to destroyed DOM elements
            element.bind("$destroy", function() {
                delete scope.element;
            });
        },
        controller : 
                   ['$scope','egCore',
            function($scope , egCore) {

                function loadRecordHtml() {
                    egCore.net.request(
                        'open-ils.search',
                        'open-ils.search.biblio.record.html',
                        $scope.recordId,
                        false,
                        $scope.marcXml
                    ).then(function(html) {
                        if (!html) return;

                        // Remove those pesky non-i8n labels / actions.
                        // Note: for printing, use the browser print page
                        // option.  The end result is the same.
                        html = html.replace(
                            /<button onclick="window.print(.*?)<\/button>/,'');
                        html = html.replace(/<title>(.*?)<\/title>/,'');

                        // remove reference to nonexistant CSS file
                        html = html.replace(/<link(.*?)\/>/,'');

                        $scope.element.html(html);
                    });
                }

                $scope.$watch('recordId', 
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            loadRecordHtml();
                        }
                    }
                );
                $scope.$watch('marcXml', 
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            loadRecordHtml();
                        }
                    }
                );

                if ($scope.recordId || $scope.marcXml) 
                    loadRecordHtml();
            }
        ]
    }
})

.directive('egRecordBreaker', function() {
    return {
        restrict : 'AE',
        template : '<pre>{{breaker}}</pre>',
        scope : {
            recordId : '=',
            marcXml  : '=',
        },
        link : function(scope, element, attrs) {
            scope.element = angular.element(element);

            // kill refs to destroyed DOM elements
            element.bind("$destroy", function() {
                delete scope.element;
            });
        },
        controller : 
                   ['$scope','egCore',
            function($scope , egCore) {

                function loadRecordBreaker() {
                    var xml;
                    if ($scope.marcXml) {
                        $scope.breaker = new MARC21.Record({ marcxml : $scope.marcXml }).toBreaker();
                    } else {
                        egCore.pcrud.retrieve('bre', $scope.recordId)
                        .then(function(rec) {
                            $scope.breaker = new MARC21.Record({ marcxml : rec.marc() }).toBreaker();
                        });
                    }
                }

                $scope.$watch('recordId', 
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            loadRecordBreaker();
                        }
                    }
                );
                $scope.$watch('marcXml', 
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            loadRecordBreaker();
                        }
                    }
                );

                if ($scope.recordId || $scope.marcXml) 
                    loadRecordBreaker();
            }
        ]
    }
})

/*
 * A record='foo' attribute is required as a storage location of the 
 * retrieved record
 */
.directive('egRecordSummary', function() {
    return {
        restrict : 'AE',
        scope : {
            recordId : '=',
            record : '=',
            noMarcLink : '@'
        },
        templateUrl : './cat/share/t_record_summary',
        controller : 
                   ['$scope','egCore','$sce',
            function($scope , egCore , $sce) {

                function loadRecord() {
                    egCore.pcrud.retrieve('bre', $scope.recordId, {
                        flesh : 1,
                        flesh_fields : {
                            bre : ['creator','editor']
                        }
                    }).then(function(rec) {
                        rec.owner(egCore.org.get(rec.owner()));
                        $scope.record = rec;
                    });
                    egCore.net.request(
                        'open-ils.search',
                        'open-ils.search.biblio.record.mods_slim.retrieve.authoritative',
                        $scope.recordId
                    ).then(function(mvr) {
                        $scope.mvr = mvr;
                    });
                    $scope.bib_cn = null;
                    $scope.bib_cn_tooltip = '';
                    var label_class = 1;
                    if (egCore.env.aous) 
                        label_class = egCore.env.aous['cat.default_classification_scheme'] || 1;
                    egCore.net.request(
                        'open-ils.cat',
                        'open-ils.cat.biblio.record.marc_cn.retrieve',
                        $scope.recordId,
                        label_class
                    ).then(function(cn_array) {
                        var tooltip = '';
                        if (cn_array.length > 0) {
                            for (var field in cn_array[0]) {
                                $scope.bib_cn = cn_array[0][field];
                            }
                            for (var i in cn_array) {
                                for (var field in cn_array[i]) {
                                    tooltip += 
                                        field + ' : ' + cn_array[i][field] + '<br>';
                                }
                            }
                            $scope.bib_cn_tooltip = $sce.trustAsHtml(tooltip);
                        }
                    });
                }

                $scope.$watch('recordId', 
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            loadRecord();
                        }
                    }
                );


                if ($scope.recordId) 
                    loadRecord();

                $scope.toggle_expand_summary = function() {
                    if ($scope.collapseRecordSummary) {
                        $scope.collapseRecordSummary = false;
                        egCore.hatch.removeItem('eg.cat.record.summary.collapse');
                    } else {
                        $scope.collapseRecordSummary = true;
                        egCore.hatch.setItem('eg.cat.record.summary.collapse', true);
                    }
                }
            
                $scope.collapse_summary = function() {
                    return $scope.collapseRecordSummary;
                }
            
                egCore.hatch.getItem('eg.cat.record.summary.collapse')
                .then(function(val) {$scope.collapseRecordSummary = Boolean(val)});

            }
        ]
    }
})

/**
 * Utility functions for translating bib record display fields into
 * various formats / structures.
 *
 * Note that 'mwde' objects (which are proper IDL objects) only contain
 * the prescribed fields from the IDL (and database view), while the
 * 'mfde' hash-based objects contain all configured display fields,
 * including local/custom fields.
 *
 * Example:
 *
 *  --
 *  // Display well-known fields
 *
 *  $scope.record = copy.call_number().record();
 *
 *  // translate wide display entry values inline
 *  egBibDisplay.mwdeJSONToJS($scope.record.wide_display_entry());
 *
 *  <div>Title:</div>
 *  <div>{{record.wide_display_entry().title()}}</div>
 *
 *  ---
 *  //  Display any field using known keys
 *
 *  $scope.all_display_fields = 
 *      egBibDisplay.mfdeToHash(record.flat_display_entries());
 *
 *  <div>Title:</div>
 *  <div>{{all_display_fields.title}}</div>
 *
 *  ---
 *  // Display all fields dynamically, using confgured labels
 *
 *  $scope.all_display_fields_with_meta = 
 *      egBibDisplay.mfdeToMetaHash(record.flat_display_entries());
 *
 *  <div ng-repeat="(key, content) in all_display_fields_with_meta">
 *    <div>Field Label</div><div>{{content.label}}</div>
 *    <div ng-if="content.multi == 't'">
 *      <div ng-repeat="val in content.value">
 *        <div>Field Value</div><div>{{val}}</div>
 *      </div>
 *    </div>
 *    <div ng-if="content.multi == 'f'">
 *      <div>Field Value</div><div>{{content.value}}</div>
 *    </div>
 *  </div>
 *
 */
.factory('egBibDisplay', ['$q', 'egCore', function($q, egCore) {
    var service = {};

    /**
     * Converts JSON-encoded values within a mwde object to Javascript
     * native strings, numbers, and arrays.
     */
    service.mwdeJSONToJS = function(entry) {
        angular.forEach(egCore.idl.classes.mwde.fields, function(f) {
            if (f.virtual) return;
            entry[f.name](JSON.parse(entry[f.name]()));
        });
    }

    /**
     * Converts a list of 'mfde' entry objects to a simple key=>value hash.
     * Non-multi values are strings or numbers.
     * Multi values are arrays of strings or numbers.
     */
    service.mfdeToHash = function(entries) {
        var hash = service.mfdeToMetaHash(entries);
        angular.forEach(hash, 
            function(sub_hash, name) { hash[name] = sub_hash.value });
        return hash;
    }

    /**
     * Converts a list of 'mfde' entry objects to a nested hash like so:
     * {name => field_name, label => field_label, value => scalar_or_array}
     * The scalar_or_array value is a string/number or an array of
     * string/numbers
     */
    service.mfdeToMetaHash = function(entries) {
        var hash = {};
        angular.forEach(entries, function(entry) {

            if (!hash[entry.name()]) {
                hash[entry.name()] = {
                    name : entry.name(),
                    label : entry.label(),
                    multi : entry.multi() == 't',
                    value : entry.multi() == 't' ? [] : null
                }
            }

            if (entry.multi() == 't') {
                hash[entry.name()].value.push(entry.value());
            } else {
                hash[entry.name()].value = entry.value();
            }
        });

        return hash;
    }

    return service;
}])
