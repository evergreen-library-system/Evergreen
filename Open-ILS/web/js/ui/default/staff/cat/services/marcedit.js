/**
 *  A MARC editor...
 */

angular.module('egMarcMod', ['egCoreMod', 'ui.bootstrap'])

.directive("egContextMenuItem", function () {
    return {
        restrict: 'E',
        replace: false,
        template: '<li ng-click="setContent(item.value,item.action)">{{label}}</li>',
        scope: { item: '=' },
        controller: ['$scope','$element',
            function ($scope , $element) {
                if (!$scope.item.label) $scope.item.label = $scope.item.value;
                if ($scope.item.divider) {
                    $element.style.borderTop = 'solid 1px';
                }

                $scope.setContent = function (v, a) {
                    if (a) { v = a($scope,v); }
                    $scope.$apply("item.value=v");
                    $( $($scope.element).parent() ).parent().empty().remove();
                    $scope.$parent.$destroy();
                }
            }
        ]
    }
})

.directive("egMarcEditEditable", ['$document', function ($document) {
    function showContext(event) {
        event.preventDefault();
        var con = event.data.scope.contextitems;

        if (angular.isArray(con)) { // we have a list of values or transforms
            var tmpl = 
            '<div class="dropdown" dropdown is-open="true">'+
                '<ul class="dropdown-menu" role="menu">'+
                    '<eg-context-menu-item ng-repeat="item in contextitems" item="item"/>'+
                '</ul>'+
            '</div>';

            var el = $compile(tmpl)(event.data);
            el.css({
                postion: 'absolute',
                top: event.pageY,
                left: event.pageX
            });

            $document.append(el);
        }
    }

    return {
        restrict: 'E',
        replace: false,
        template: '<input style="font-family: \'Lucida Console\', Monaco, monospace;" ng-model="content" size="{{content.length * 1.1}}" maxlength="{{max}}" class="" type="text"/>',
        transclude: true,
        scope: {
            content: '=',
            //contextitems: '=',
            max: '@',
            type: '@'
        },
//        controller : ['$scope',
//            function ( $scope ) {
//                $scope.minsize = $scope.max || $scope.content.length;
//                if (!$scope.contextitems) $scope.contextitems = {};
//            }
//        ],
        link: function (scope, element, attrs) {

            element.bind('change', {}, function (e) { element.size = scope.max || scope.content.length * 1.1});

            if (scope.contextitems && angular.isArray(scope.contextitems)) {
                element.bind('context', { scope : scope, element : element }, showContext);
            }
        }
    }
}])

.directive("egMarcEditSubfield", function () {
    return {
        restrict: 'E',
        template: '<span>'+
                    '<span><eg-marc-edit-editable type="sfc" class="marcsfcode" content="subfield[0]" max="1"/></span>'+
                    '<span><eg-marc-edit-editable type="sfv" class="marcsfvalue" content="subfield[1]"/></span>'+
                  '</span>',
        scope: { field: "=", subfield: "=" },
        replace: false
    }
})

.directive("egMarcEditInd", function () {
    return {
        restrict: 'E',
        template: '<span><eg-marc-edit-editable type="ind" content="ind" max="1"/></span>',
        scope: { ind : '=' },
        replace: false,
    }
})

.directive("egMarcEditTag", function () {
    return {
        restrict: 'E',
        template: '<span><eg-marc-edit-editable type="tag" content="tag" max="3"/></span>',
        scope: { tag : '=' },
        replace: false
    }
})

.directive("egMarcEditDatafield", function () {
    return {
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag class="marctag" tag="field.tag"/></span>'+
                    '<span><eg-marc-edit-ind class="marcind" ind="field.ind1"/></span>'+
                    '<span><eg-marc-edit-ind class="marcind" ind="field.ind2"/></span>'+
                    '<span><eg-marc-edit-subfield ng-repeat="subfield in field.subfields" subfield="subfield" field="field"/></span>'+
                  '</div>',
        scope: { field: "=" }
    }
})

.directive("egMarcEditControlfield", function () {
    return {
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag class="marctag" tag="field.tag"/></span>'+
                    '<span><eg-marc-edit-editable type="cfld" class="marcdata" content="field.data"/></span>'+
                  '</div>',
        scope: { field: "=" }
    }
})

.directive("egMarcEditLeader", function () {
    return {
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-editable class="marctag" content="tag"/></span>'+
                    '<span><eg-marc-edit-editable class="marcdata" max="{{record.leader.length}}" content="record.leader"/></span>'+
                  '</div>',
        controller : ['$scope',
            function ( $scope ) {
                $scope.tag = 'LDR';
            }
        ],
        scope: { record: "=" }
    }
})

/// TODO: fixed field editor and such
.directive("egMarcEditRecord", function () {
    return {
        template: '<form ng-submit="saveRecord()">'+
                  '<div class="marcrecord">'+
                    '<div><eg-marc-edit-leader record="record"/></div>'+
                    '<div><eg-marc-edit-controlfield ng-repeat="field in controlfields" field="field"/></div>'+
                    '<div><eg-marc-edit-datafield ng-repeat="field in datafields" field="field"/></div>'+
                  '</div>'+
                  '<button class="btn btn-default" type="submit">Save</button>'+
                  '</form>'+
                  '<button class="btn btn-default" ng-click="seeBreaker()">Breaker</button>',
        restrict: 'E',
        replace: false,
        scope: { recordId : '=' },
        controller : ['$scope','egCore',
            function ( $scope , egCore ) {

                function loadRecord() {
                    return egCore.pcrud.retrieve(
                        'bre', $scope.recordId
                    ).then(function(rec) {
                        $scope.bre = rec;
                        $scope.record = new MARC.Record();
                        $scope.record.fromXmlString( $scope.bre.marc() );
                        $scope.controlfields = $scope.record.fields.filter(function(f){ return f.isControlfield() });
                        $scope.datafields = $scope.record.fields.filter(function(f){ return !f.isControlfield() });
                    });
                }

                $scope.saveRecord = function () {
                    $scope.bre.marc($scope.record.toXmlString());
                    return egCore.pcrud.update(
                        $scope.bre
                    ).then(loadRecord);
                };

                $scope.seeBreaker = function () {
                    alert($scope.record.toBreaker());
                };

                $scope.$watch('recordId',
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            loadRecord();
                        }
                    }
                );


                $scope.controlfields = [];
                $scope.datafields = [];

                if ($scope.recordId)
                    loadRecord();

            }
        ]          
    }
})

;
