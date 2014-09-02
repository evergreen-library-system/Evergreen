/**
 * Simple directive for rending the HTML view of a bib record.
 *
 * <eg-record-html record-id="myRecordIdScopeVariable"></eg-record-id>
 *
 * The value of myRecordIdScopeVariable is watched internally and the 
 * record is updated to match.
 */
angular.module('egCoreMod')

.directive('egRecordHtml', function() {
    return {
        restrict : 'AE',
        scope : {recordId : '='},
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
                        $scope.recordId
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

                if ($scope.recordId) 
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
            record : '='
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
            }
        ]
    }
})
