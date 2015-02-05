/**
 *  A MARC editor...
 */

angular.module('egMarcMod', ['egCoreMod', 'ui.bootstrap'])

.directive("egContextMenuItem", ['$timeout',function ($timeout) {
    return {
        restrict: 'E',
        replace: true,
        template: '<li><a ng-click="setContent(item.value,item.action)">{{item.label}}</a></li>',
        scope: { item: '=', content: '=' },
        controller: ['$scope','$element',
            function ($scope , $element) {
                if (!$scope.item.label) $scope.item.label = $scope.item.value;
                if ($scope.item.divider) {
                    $element.style.borderTop = 'solid 1px';
                }

                $scope.setContent = function (v, a) {
                    var replace_with = v;
                    if (a) replace_with = a($scope,$element,$scope.item.value,$scope.$parent.$parent.content);
                    $timeout(function(){
                        $scope.$parent.$parent.$apply(function(){
                            $scope.$parent.$parent.content = replace_with
                        })
                    }, 0);
                    console.log('well, replaced it');
                    $($element).parent().css({display: 'none'});
                }
            }
        ]
    }
}])

.directive("egMarcEditEditable", ['$timeout', '$compile', '$document', function ($timeout, $compile, $document) {
    return {
        restrict: 'E',
        replace: false,
        transclude: true,
        template: '<input style="font-family: \'Lucida Console\', Monaco, monospace;" ng-model="content" size="{{content.length * 1.1}}" maxlength="{{max}}" class="" type="text"/>',
        scope: {
            field: '=',
            subfield: '=',
            content: '=',
            contextItemContainer: '@',
            max: '@',
            type: '@'
        },
        controller : ['$scope',
            function ( $scope ) {

/* XXX Example, for testing.  We'll get this from the tag-table services for realz
 *
                if (!$scope.contextItemContainer) {
                    $scope.contextItemContainer = "default_context";
                    $scope[$scope.contextItemContainer] = [
                        { value: 'a' },
                        { value: 'b' },
                        { value: 'c' },
                    ];
                }

 *
 */

                if ($scope.contextItemContainer)
                    $scope.item_container = $scope[$scope.contextItemContainer];

                $scope.showContext = function (event) {
                    if ($scope.context_menu_element) {
                        console.log('Reshowing context menu...');
                        $($scope.context_menu_element).css({ display: 'block', top: event.pageY, left: event.pageX });
                        return false;
                    }

                    if (angular.isArray($scope.item_container)) { // we have a list of values or transforms
                        console.log('Showing context menu...');

                        var tmpl = 
                            '<ul class="dropdown-menu" role="menu">'+
                                '<eg-context-menu-item ng-repeat="item in item_container" item="item" content="content"/>'+
                            '</ul>';
            
                        var tnode = angular.element(tmpl);
                        console.log('... got element ...');

                        $document.find('body').append(tnode);
                        console.log('... attached to DOM ...');

                        $(tnode).css({
                            display: 'block',
                            top: event.pageY,
                            left: event.pageX
                        });
                        console.log('... displayed ...');

                        $scope.context_menu_element = tnode;
                        console.log('... captured for later ...');

                        $timeout(function() {
                            var e = $compile(tnode)($scope);
                            console.log('... compiled: ' + e);
                        }, 0);

                        return false;
                    }
            
                    return true;
                }

            }
        ],
        link: function (scope, element, attrs) {

            element.bind('change', function (e) { element.size = scope.max || parseInt(scope.content.length * 1.1) });
            if (scope.contextItemContainer && angular.isArray(scope[scope.contextItemContainer]))
                element.bind('contextmenu', scope.showContext);
        }
    }
}])

.directive("egMarcEditSubfield", function () {
    return {
        restrict: 'E',
        template: '<span>'+
                    '<span><eg-marc-edit-editable type="sfc" class="marcsfcode" field="field" subfield="subfield" content="subfield[0]" max="1"/></span>'+
                    '<span><eg-marc-edit-editable type="sfv" class="marcsfvalue" field="field" subfield="subfield" content="subfield[1]"/></span>'+
                  '</span>',
        scope: { field: "=", subfield: "=" },
        replace: false
    }
})

.directive("egMarcEditInd", function () {
    return {
        restrict: 'E',
        template: '<span><eg-marc-edit-editable type="ind" field="field" content="ind" max="1"/></span>',
        scope: { ind : '=', field: '=' },
        replace: false,
    }
})

.directive("egMarcEditTag", function () {
    return {
        restrict: 'E',
        template: '<span><eg-marc-edit-editable type="tag" field="field" content="tag" max="3"/></span>',
        scope: { tag : '=', field: '=' },
        replace: false
    }
})

.directive("egMarcEditDatafield", function () {
    return {
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag class="marctag" field="field" tag="field.tag"/></span>'+
                    '<span><eg-marc-edit-ind class="marcind" field="field" ind="field.ind1"/></span>'+
                    '<span><eg-marc-edit-ind class="marcind" field="field" ind="field.ind2"/></span>'+
                    '<span><eg-marc-edit-subfield ng-repeat="subfield in field.subfields" subfield="subfield" field="field"/></span>'+
                  '</div>',
        scope: { field: "=" }
    }
})

.directive("egMarcEditControlfield", function () {
    return {
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag class="marctag" field="field" tag="field.tag"/></span>'+
                    '<span><eg-marc-edit-editable type="cfld" field="field" class="marcdata" content="field.data"/></span>'+
                  '</div>',
        scope: { field: "=" }
    }
})

.directive("egMarcEditLeader", function () {
    return {
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-editable class="marctag" content="tag"/></span>'+
                    '<span><eg-marc-edit-editable class="marcdata" type="ldr" max="{{record.leader.length}}" content="record.leader"/></span>'+
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
