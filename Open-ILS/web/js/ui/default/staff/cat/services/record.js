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
                   ['$scope','egCore',
            function($scope , egCore) {

                function loadRecord() {
                    egCore.pcrud.retrieve('bre', $scope.recordId, {
                        flesh : 1,
                        flesh_fields : {
                            bre : ['simple_record','creator','editor']
                        }
                    }).then(function(rec) {
                        rec.owner(egCore.org.get(rec.owner()));
                        $scope.record = rec;
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
