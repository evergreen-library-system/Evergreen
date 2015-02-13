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
                    $($element).parent().css({display: 'none'});
                }
            }
        ]
    }
}])

.directive("egMarcEditEditable", ['$timeout', '$compile', '$document', function ($timeout, $compile, $document) {
    return {
        restrict: 'E',
        replace: true,
        template: '<input '+
                      'style="font-family: \'Lucida Console\', Monaco, monospace;" '+
                      'ng-model="content" '+
                      'size="{{content.length * 1.1}}" '+
                      'maxlength="{{max}}" '+
                      'class="" '+
                      'type="text" '+
                  '/>',
        scope: {
            field: '=',
            onKeydown: '=',
            subfield: '=',
            content: '=',
            contextItemContainer: '@',
            max: '@',
            itype: '@'
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
                        $('body').on('click.context_menu',function() {
                            $($scope.context_menu_element).css('display','none');
                            $('body').off('click.context_menu');
                        });
                        return false;
                    }

                    if (angular.isArray($scope.item_container)) { // we have a list of values or transforms
                        console.log('Showing context menu...');

                        var tmpl = 
                            '<ul class="dropdown-menu" role="menu">'+
                                '<eg-context-menu-item ng-repeat="item in item_container" item="item" content="content"/>'+
                            '</ul>';
            
                        var tnode = angular.element(tmpl);
                        $document.find('body').append(tnode);

                        $(tnode).css({
                            display: 'block',
                            top: event.pageY,
                            left: event.pageX
                        });

                        $scope.context_menu_element = tnode;

                        $timeout(function() {
                            var e = $compile(tnode)($scope);
                        }, 0);


                        $('body').on('click.context_menu',function() {
                            $(tnode).css('display','none');
                            $('body').off('click.context_menu');
                        });

                        return false;
                    }
            
                    return true;
                }

            }
        ],
        link: function (scope, element, attrs) {

            if (scope.onKeydown) element.bind('keydown', scope.onKeydown);

            element.bind('change', function (e) { element.size = scope.max || parseInt(scope.content.length * 1.1) });

            if (scope.contextItemContainer && angular.isArray(scope[scope.contextItemContainer]))
                element.bind('contextmenu', scope.showContext);
        }
    }
}])

.directive("egMarcEditSubfield", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<span>'+
                    '<span><eg-marc-edit-editable '+
                        'itype="sfc" '+
                        'class="marcsfcode" '+
                        'field="field" '+
                        'subfield="subfield" '+
                        'content="subfield[0]" '+
                        'max="1" '+
                        'on-keydown="onKeydown" '+
                        'id="r{{field.record.subfield(\'901\',\'c\')[1]}}f{{field.position}}s{{subfield[2]}}code" '+
                    '/></span>'+
                    '<span><eg-marc-edit-editable '+
                        'itype="sfv" '+
                        'class="marcsfvalue" '+
                        'field="field" '+
                        'subfield="subfield" '+
                        'content="subfield[1]" '+
                        'on-keydown="onKeydown" '+
                        'id="r{{field.record.subfield(\'901\',\'c\')[1]}}f{{field.position}}s{{subfield[2]}}value" '+
                    '/></span>'+
                  '</span>',
        scope: { field: "=", subfield: "=", onKeydown: '=' },
        replace: false
    }
})

.directive("egMarcEditInd", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<span><eg-marc-edit-editable '+
                      'itype="ind" '+
                      'field="field" '+
                      'content="ind" '+
                      'max="1" '+
                      'on-keydown="onKeydown" '+
                      'id="r{{field.record.subfield(\'901\',\'c\')[1]}}f{{field.position}}i{{indNumber}}"'+
                      '/></span>',
        scope: { ind : '=', field: '=', onKeydown: '=', indNumber: '@' },
        replace: false,
    }
})

.directive("egMarcEditTag", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<span><eg-marc-edit-editable '+
                      'itype="tag" '+
                      'field="field" '+
                      'content="tag" '+
                      'max="3" '+
                      'on-keydown="onKeydown" '+
                      'id="r{{field.record.subfield(\'901\',\'c\')[1]}}f{{field.position}}tag"'+
                      '/></span>',
        scope: { tag : '=', field: '=', onKeydown: '=' },
        replace: false
    }
})

.directive("egMarcEditDatafield", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag class="marctag" field="field" tag="field.tag" on-keydown="onKeydown"/></span>'+
                    '<span><eg-marc-edit-ind class="marcind" field="field" ind="field.ind1" on-keydown="onKeydown" ind-number="1"/></span>'+
                    '<span><eg-marc-edit-ind class="marcind" field="field" ind="field.ind2" on-keydown="onKeydown" ind-number="2"/></span>'+
                    '<span><eg-marc-edit-subfield ng-repeat="subfield in field.subfields" subfield="subfield" field="field" on-keydown="onKeydown"/></span>'+
                  '</div>',
        scope: { field: "=", onKeydown: '=' }
    }
})

.directive("egMarcEditControlfield", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag class="marctag" field="field" tag="field.tag" on-keydown="onKeydown"/></span>'+
                    '<span><eg-marc-edit-editable '+
                      'itype="cfld" '+
                      'field="field" '+
                      'class="marcdata" '+
                      'content="field.data" '+
                      'on-keydown="onKeydown" '+
                      'id="r{{field.record.subfield(\'901\',\'c\')[1]}}f{{field.position}}data"'+
                      '/></span>'+
                  '</div>',
        scope: { field: "=", onKeydown: '=' }
    }
})

.directive("egMarcEditLeader", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-editable '+
                      'class="marctag" '+
                      'content="tag" '+
                      'on-keydown="onKeydown" '+
                      'id="leadertag" '+
                      'disabled="disabled"'+
                      '/></span>'+
                    '<span><eg-marc-edit-editable '+
                      'class="marcdata" '+
                      'itype="ldr" '+
                      'max="{{record.leader.length}}" '+
                      'content="record.leader" '+
                      'id="r{{record.subfield(\'901\',\'c\')[1]}}leaderdata" '+
                      'on-keydown="onKeydown"'+
                      '/></span>'+
                  '</div>',
        controller : ['$scope',
            function ( $scope ) {
                $scope.tag = 'LDR';
            }
        ],
        scope: { record: "=", onKeydown: '=' }
    }
})

/// TODO: fixed field editor and such
.directive("egMarcEditRecord", function () {
    return {
        template: '<form ng-submit="saveRecord()">'+
                  '<div class="marcrecord">'+
                    '<div><eg-marc-edit-leader record="record" on-keydown="onKeydown"/></div>'+
                    '<div><eg-marc-edit-controlfield ng-repeat="field in controlfields" field="field" on-keydown="onKeydown"/></div>'+
                    '<div><eg-marc-edit-datafield ng-repeat="field in datafields" field="field" on-keydown="onKeydown"/></div>'+
                  '</div>'+
                  '<button class="btn btn-default" type="submit">Save</button>'+
                  '</form>'+
                  '<button class="btn btn-default" ng-click="seeBreaker()">Breaker</button>',
        restrict: 'E',
        replace: false,
        scope: { recordId : '=', maxUndo : '@' },
        controller : ['$timeout','$scope','egCore',
            function ( $timeout , $scope , egCore ) {

                $scope.max_undo = $scope.maxUndo || 100;
                $scope.record_undo_stack = [];
                $scope.record_redo_stack = [];
                $scope.in_undo = false;
                $scope.in_redo = false;
                $scope.record = new MARC.Record();
                $scope.save_stack_depth = 0;
                $scope.controlfields = [];
                $scope.datafields = [];

                $scope.onKeydown = function (event) {
                    var event_return = true;

                    if (event.which == 89 && event.ctrlKey) { // ctrl+y, redo
                        event_return = $scope.processRedo();
                    } else if (event.which == 90 && event.ctrlKey) { // ctrl+z, undo
                        event_return = $scope.processUndo();
                    } else { // Assumes only marc editor elements have IDs that can trigger this event handler.
                        $scope.current_event_target = $(event.target).attr('id');
                        if ($scope.current_event_target) {
                            $scope.current_event_target_cursor_pos =
                                event.target.selectionDirection=='backward' ?
                                    event.target.selectionStart :
                                    event.target.selectionEnd;
                        }
                    }

                    return event_return;
                };

                function setCaret() {
                    if ($scope.current_event_target) {
                        var element = $('#'+$scope.current_event_target).get(0);
                        element.focus();
                        element.setSelectionRange(
                            $scope.current_event_target_cursor_pos,
                            $scope.current_event_target_cursor_pos
                        );
                        $scope.current_event_target = null;
                    }
                }

                function loadRecord() {
                    return egCore.pcrud.retrieve(
                        'bre', $scope.recordId
                    ).then(function(rec) {
                        $scope.in_redo = true;
                        $scope.bre = rec;
                        $scope.record = new MARC.Record({ marcxml : $scope.bre.marc() });
                        $scope.controlfields = $scope.record.fields.filter(function(f){ return f.isControlfield() });
                        $scope.datafields = $scope.record.fields.filter(function(f){ return !f.isControlfield() });
                        $scope.save_stack_depth = $scope.record_undo_stack.length;
                    }).then(setCaret);
                }

                $scope.$watch('record.toBreaker()', function (newVal, oldVal) {
                    if (!$scope.in_undo && !$scope.in_redo && oldVal != newVal) {
                        $scope.record_undo_stack.push({
                            breaker: oldVal,
                            target: $scope.current_event_target,
                            pos: $scope.current_event_target_cursor_pos
                        });

                        if ($scope.record_undo_stack.length != $scope.save_stack_depth) {
                            console.log('should get a listener... does not');
                            $('body').on('beforeunload', function(){
                                return 'There is unsaved data in this record.'
                            });
                        } else {
                            $('body').off('beforeunload');
                        }
                    }

                    if ($scope.record_undo_stack.length > $scope.max_undo)
                        $scope.record_undo_stack.shift();

                    console.log('undo stack is ' + $scope.record_undo_stack.length + ' deep');
                    $scope.in_redo = false;
                    $scope.in_undo = false;
                });

                $scope.processUndo = function () {
                    if ($scope.record_undo_stack.length) {
                        $scope.in_undo = true;

                        var undo_item = $scope.record_undo_stack.pop();
                        $scope.record_redo_stack.push(undo_item);

                        $scope.record = new MARC.Record({ marcbreaker : undo_item.breaker });
                        $scope.controlfields = $scope.record.fields.filter(function(f){ return f.isControlfield() });
                        $scope.datafields = $scope.record.fields.filter(function(f){ return !f.isControlfield() });

                        $scope.current_event_target = undo_item.target;
                        $scope.current_event_target_cursor_pos = undo_item.pos;
                        console.log('Undo targeting ' + $scope.current_event_target + ' position ' + $scope.current_event_target_cursor_pos);

                        $timeout(function(){$scope.$digest()}).then(setCaret);
                        return false;
                    }

                    return true;
                };

                $scope.processRedo = function () {
                    if ($scope.record_redo_stack.length) {
                        $scope.in_redo = true;

                        var redo_item = $scope.record_redo_stack.pop();
                        $scope.record_undo_stack.push(redo_item);

                        $scope.record = new MARC.Record({ marcbreaker : redo_item.breaker });
                        $scope.controlfields = $scope.record.fields.filter(function(f){ return f.isControlfield() });
                        $scope.datafields = $scope.record.fields.filter(function(f){ return !f.isControlfield() });

                        $scope.current_event_target = redo_item.target;
                        $scope.current_event_target_cursor_pos = redo_item.pos;
                        console.log('Redo targeting ' + $scope.current_event_target + ' position ' + $scope.current_event_target_cursor_pos);

                        $timeout(function(){$scope.$digest()}).then(setCaret);
                        return false;
                    }

                    return true;
                };

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

                if ($scope.recordId)
                    loadRecord();

            }
        ]          
    }
})

;
