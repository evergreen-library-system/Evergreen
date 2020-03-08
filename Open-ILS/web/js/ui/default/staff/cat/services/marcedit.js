/**
 *  A MARC editor...
 */

angular.module('egMarcMod', ['egCoreMod', 'ui.bootstrap'])

.directive("egContextMenuItem", ['$timeout',function ($timeout) {
    return {
        restrict: 'E',
        replace: true,
        template: '<li><a ng-click="setContent(item.value,item.action)">{{item.label}}</a></li>',
        scope: { item: '=', content: '=', contextMenuEvent: '=' },
        controller: ['$scope','$element',
            function ($scope , $element) {
                if (!$scope.item.label) $scope.item.label = $scope.item.value;
                if ($scope.item.divider) {
                    $element.css('borderTop','solid 1px');
                }

                $scope.setContent = function (v, a) {
                    var replace_with = v;

                    if (a) {
                        replace_with = a(
                            $scope,
                            $element,
                            $scope.item.value,
                            $scope.$parent.$parent.content,
                            $scope.contextMenuEvent
                        );
                    }

                    if (typeof replace_with !== 'undefined') {
                        $timeout(function(){
                            $scope.$parent.$parent.$apply(function(){
                                $scope.$parent.$parent.content = replace_with
                            })
                        }, 0);
                    }
                    $($element).parent().css({display: 'none'});
                }
            }
        ]
    }
}])

.directive("contenteditable", function() {
    return {
        restrict: "A",
        require: "ngModel",
        link: function(scope,element,attrs,ngModel){

            function read(){
                // save new text into model
                var elhtml = element.text();
                ngModel.$setViewValue(elhtml);
            }

            ngModel.$render = function(){
                element.text(ngModel.$viewValue || "");
            };

            element.bind("blur.c_e keyup.c_e change.c_e", function(){
                scope.$apply(read);
            });
        }
    };
})

.directive("egMarcEditEditable", ['$timeout', '$compile', '$document', function ($timeout, $compile, $document) {
    return {
        restrict: 'E',
        replace: true,
        templateUrl: './cat/share/t_marcedit_editable',
        scope: {
            field: '=',
            onKeydown: '=',
            subfield: '=',
            content: '=',
            contextItemContainer: '@',
            contextItemGenerator: '=',
            max: '@',
            itype: '@',
            selectOnFocus: '=',
            advanceFocusAfterInput: '=',
            isDisabled: "="
        },
        controller : ['$scope',
            function ( $scope ) {
                $scope.isInputDisabled = $scope.isDisabled == 'disabled';
                if ($scope.contextItemContainer && angular.isArray($scope.$parent[$scope.contextItemContainer]))
                    $scope.item_container = $scope.$parent[$scope.contextItemContainer];
                else if ($scope.contextItemGenerator)
                    $scope.item_generator = $scope.contextItemGenerator;

                $scope.showContext = function (event) {
                    $scope.item_list = [];
                    if ($scope.item_container) {
                        $scope.item_list = $scope.item_container;
                    } else if ($scope.item_generator) {
                        // always recalculate; tag and/or subfield
                        // codes may have changed

                        var generator = $scope.item_generator;
                        if (!angular.isArray(generator)) generator = [generator];

                        var is_first = true;
                        angular.forEach(generator, function (g) {
                            var sub_list = g();

                            if (is_first)
                                is_first = false;
                            else if (Boolean(sub_list[0]))
                                sub_list[0].divider = true;

                            $scope.item_list = $scope.item_list.concat(sub_list);
                        });

                    } else {
                        return true;
                    }

                    if (angular.isArray($scope.item_list) && $scope.item_list.length > 0) { // we have a list of values or transforms
                        console.log('Showing context menu...');
                        $('body').trigger('click');

                        $scope.contextMenuEvent = event;
                        var tmpl = 
                            '<ul class="dropdown-menu scrollable-menu" role="menu" style="z-index: 2000;">'+
                                '<eg-context-menu-item context-menu-event="contextMenuEvent" ng-repeat="item in item_list" item="item" content="content"/>'+
                            '</ul>';
            
                        var tnode = angular.element(tmpl);
                        $document.find('body').append(tnode);

                        $(tnode).css({
                            display: 'block',
                            top: event.pageY,
                            left: event.pageX
                        });

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

            if (scope.onKeydown) element.bind('keydown', {scope : scope}, scope.onKeydown);

            if (Boolean(scope.selectOnFocus)) {
                element.addClass('noSelection');
                element.bind('focus', function (e) {
                    var el = $(e.target).children('input').first();
                    if (el.select) { el.select(); }
                });
            }

            element.children("div[contenteditable]").each(function() {
                $(this).focus(function(e) {
                    var tNode = e.target.firstChild;
                    var range = document.createRange();
                    range.setStart(tNode, 0);
                    range.setEnd(tNode, tNode.length);
                    var sel = window.getSelection();
                    sel.removeAllRanges();
                    sel.addRange(range);
                });
            });

            function findCaretTarget(id, itype) {
                var tgt = null;
                if (itype == 'tag') {
                    tgt = id.replace(/tag$/, 'i1');
                } else if (itype == 'ind') {
                    if (id.match(/i1$/)) {
                        tgt = id.replace(/i1$/, 'i2');
                    } else if (id.match(/i2$/)) {
                        tgt = id.replace(/i2$/, 's0code');
                    }
                } else if (itype == 'sfc') {
                    tgt = id.replace(/code$/, 'value');
                }
                return tgt;
            }
            if (Boolean(scope.advanceFocusAfterInput)) {
                element.bind('input', function (e) {
                    if (scope.content.length == scope.max) {
                        var tgt = findCaretTarget(e.currentTarget.id, scope.itype);
                        if (tgt) {
                            var element = $('#' + tgt).get(0);
                            if (element) {
                                element.focus();
                            }
                        }
                    }
                });
            }

            element.bind('change', function (e) { element.size = scope.max || parseInt(scope.content.length * 1.1) });

            element.bind('contextmenu', {scope : scope}, scope.showContext);
        }
    }
}])

.directive("egMarcEditFixedField", ['$timeout', '$compile', '$document', function ($timeout, $compile, $document) {
    return {
        transclude: true,
        restrict: 'E',
        template: '<div class="col-md-2">'+
                    '<div class="col-md-1"><label name="{{fixedField}}" for="{{fixedField}}_ff_input">{{fixedFieldLabel}}</label></div>'+
                    '<div class="col-md-1"><input type="text" style="padding-left: 5px; margin-left: 1em" size="4" id="{{fixedField}}_ff_input"/></div>'+
                  '</div>',
        scope: { record: "=", fixedField: "@", fixedFieldLabel: "@" },
        replace: true,
        controller : ['$scope', '$element', 'egTagTable',
            function ( $scope ,  $element ,  egTagTable) {
                $($element).removeClass('fixed-field-box');
                $($element).children().css({ display : 'none' });
                $scope.fixedFieldLabel = $scope.fixedFieldLabel || $scope.fixedField;
                $scope.me = null;
                $scope.content = null; // this is where context menus dump their values
                $scope.item_container = [];
                $scope.in_handler = false;
                $scope.ready = false;
                $element.find('input').bind('focus', function (e) { e.target.select() });
                $element.find('input').bind('mouseup', function(e) {
                    e.preventDefault()
                    return false;
                });

                $scope.$watch('content', function (newVal, oldVal) {
                    var input = $($element).find('input');
                    input.val(newVal);
                    input.trigger('keyup'); // cascade the update
                });

                $scope.$watch('record.ready', function (newVal, oldVal) { // wait for the record to be loaded
                    if (newVal && !$scope.ready) {
                        $scope.rtype = $scope.record.recordType();

                        egTagTable.fetchFFPosTable( $scope.rtype ).then(function (ff_list) {
                            angular.forEach(ff_list, function (ff) {
                                if (!$scope.me) {
                                    if (ff.fixed_field == $scope.fixedField && ff.rec_type == $scope.rtype) {
                                        $scope.me = ff;
                                        $scope.ready = true;
                                        $($element).addClass('fixed-field-box');
                                        $($element).children().css({ display : 'inline' });

                                        var input = $($element).find('input');
                                        input.attr('maxlength', $scope.me.length);
                                        input.val($scope.record.extractFixedField($scope.me.fixed_field));
                                        input.on('keyup', function(e) {
                                            $scope.in_handler = true;
                                            $scope.record.setFixedField($scope.me.fixed_field, input.val());
                                            try { $scope.$parent.$digest(); } catch(e) {};
                                        });
                                    }
                                }
                            });
                            return $scope.me;
                        }).then(function (me) {
                            if (me) {
                                $scope.$watch(
                                    function() {
                                        return $scope.record.extractFixedField($scope.fixedField);
                                    },
                                    function (newVal, oldVal) {
                                        if ($scope.in_handler) {
                                            $scope.in_handler = false;
                                        } else if (oldVal != newVal) {
                                            $($element).find('input').val(newVal);
                                        }
                                    }
                                );
                            }
                        }).then(function () {
                            return egTagTable.fetchFFValueTable( $scope.rtype );
                        }).then(function (vlist) {
                            if (vlist[$scope.fixedField]) {
                                vlist[$scope.fixedField].forEach(function (v) {
                                    if (v[0].length <= v[2]) {
                                        $scope.item_container.push({ value : v[0], label : v[0] + ': ' + v[1] });
                                    }
                                });
                            }
                        }).then(function () {
                            if ($scope.item_container && $scope.item_container.length)
                                $($element).bind('contextmenu', $scope.showContext);
                        });

                    }
                });

                $scope.showContext = function (event) {
                    if ($scope.context_menu_element) {
                        console.log('Reshowing context menu...');
                        $('body').trigger('click');
                        $($scope.context_menu_element).css({ display: 'block', top: event.pageY, left: event.pageX });
                        $('body').on('click.context_menu',function() {
                            $($scope.context_menu_element).css('display','none');
                            $('body').off('click.context_menu');
                        });
                        return false;
                    }

                    if (angular.isArray($scope.item_container)) { // we have a list of values or transforms
                        console.log('Showing context menu...');
                        $('body').trigger('click');

                        var tmpl = 
                            '<ul class="dropdown-menu scrollable-menu" role="menu" style="z-index: 2000;">'+
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
        ]
    }
}])

.directive("egMarcEditSubfield", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<span>'+
                    '<span><label class="marcedit marcsfcodedelimiter"'+
                        'for="r{{field.record.subfield(\'901\',\'c\')[1] || 0}}f{{field.position}}s{{subfield[2]}}code" '+
                        '>‡</label><eg-marc-edit-editable '+
                        'itype="sfc" '+
                        'select-on-focus="true" '+
                        'advance-focus-after-input="true" '+
                        'class="marcedit marcsf marcsfcode" '+
                        'field="field" '+
                        'subfield="subfield" '+
                        'content="subfield[0]" '+
                        'max="1" '+
                        'on-keydown="onKeydown" '+
                        'context-item-generator="sf_code_options" '+
                        'id="r{{field.record.subfield(\'901\',\'c\')[1] || 0}}f{{field.position}}s{{subfield[2]}}code" '+
                    '/></span>'+
                    '<span><eg-marc-edit-editable '+
                        'itype="sfv" '+
                        'select-on-focus="true" '+
                        'class="marcedit marcsf marcsfvalue" '+
                        'field="field" '+
                        'subfield="subfield" '+
                        'content="subfield[1]" '+
                        'on-keydown="onKeydown" '+
                        'context-item-generator="sf_val_options" '+
                        'id="r{{field.record.subfield(\'901\',\'c\')[1] || 0}}f{{field.position}}s{{subfield[2]}}value" '+
                    '/></span>'+
                  '</span>',
        scope: { field: "=", subfield: "=", onKeydown: '=' },
        replace: true,
        controller : ['$scope', 'egTagTable',
            function ( $scope ,  egTagTable) {

                $scope.sf_code_options = function () {
                    return egTagTable.getSubfieldCodes($scope.field.tag);
                }
                $scope.sf_val_options = function () {
                    return egTagTable.getSubfieldValues($scope.field.tag, $scope.subfield[0]);
                }
            }
        ]
    }
})

.directive("egMarcEditInd", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<span><eg-marc-edit-editable '+
                      'itype="ind" '+
                      'class="marcedit marcind" '+
                      'select-on-focus="true" '+
                      'advance-focus-after-input="true" '+
                      'field="field" '+
                      'content="ind" '+
                      'max="1" '+
                      'on-keydown="onKeydown" '+
                      'context-item-generator="ind_val_options" '+
                      'id="r{{field.record.subfield(\'901\',\'c\')[1] || 0}}f{{field.position}}i{{indNumber}}"'+
                      '/></span>',
        scope: { ind : '=', field: '=', onKeydown: '=', indNumber: '@' },
        replace: true,
        controller : ['$scope', 'egTagTable',
            function ( $scope ,  egTagTable) {

                $scope.ind_val_options = function () {
                    return egTagTable.getIndicatorValues($scope.field.tag, $scope.indNumber);
                }
            }
        ]
    }
})

.directive("egMarcEditTag", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<span><eg-marc-edit-editable '+
                      'itype="tag" '+
                      'class="marcedit marctag" '+
                      'select-on-focus="true" '+
                      'advance-focus-after-input="true" '+
                      'field="field" '+
                      'content="tag" '+
                      'max="3" '+
                      'on-keydown="onKeydown" '+
                      'context-item-generator="tag_options" '+
                      'id="r{{field.record.subfield(\'901\',\'c\')[1] || 0}}f{{field.position}}tag"'+
                      '/></span>',
        scope: { tag : '=', field: '=', onKeydown: '=', contextFunctions: '=' },
        replace: true,
        controller : ['$scope', 'egTagTable', 'egCore',
            function ( $scope ,  egTagTable,   egCore) {

                $scope.tag_options = [
                    function () {
                        var options = [
                            { label : egCore.strings.ADD_006, action : function(j1,j2,j3,j4,e) { $scope.contextFunctions.add006(e) } },
                            { label : egCore.strings.ADD_007, action : function(j1,j2,j3,j4,e) { $scope.contextFunctions.add007(e) } },
                            { label : egCore.strings.ADD_REPLACE_008, action : function(j1,j2,j3,j4,e) { $scope.contextFunctions.reify008(e) } },
                        ];

                        if (!$scope.field.isControlfield()) {
                            options = options.concat([
                                { label : egCore.strings.INSERT_FIELD_AFTER, action : function(j1,j2,j3,j4,e) { $scope.contextFunctions.addDatafield(e) } },
                                { label : egCore.strings.INSERT_FIELD_BEFORE, action : function(j1,j2,j3,j4,e) { $scope.contextFunctions.addDatafield(e,true) } },
                            ]);
                        }

                        options.push({ label : egCore.strings.DELETE_FIELD, action : function(j1,j2,j3,j4,e) { $scope.contextFunctions.deleteDatafield(e) } });
                        return options;
                    },
                    function () { return egTagTable.getFieldTags() }
                ];

            }
        ]
    }
})

.directive("egMarcEditDatafield", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag context-functions="contextFunctions" field="field" tag="field.tag" on-keydown="onKeydown"/></span>'+
                    '<span><eg-marc-edit-ind field="field" ind="field.ind1" on-keydown="onKeydown" ind-number="1"/></span>'+
                    '<span><eg-marc-edit-ind field="field" ind="field.ind2" on-keydown="onKeydown" ind-number="2"/></span>'+
                    '<span><eg-marc-edit-subfield ng-class="{ \'unvalidatedheading\' : field.heading_checked && !field.heading_valid, \'marcedit_stacked_subfield\' : stackSubfields.enabled }" ng-repeat="subfield in field.subfields" subfield="subfield" field="field" on-keydown="onKeydown"/></span>'+
                    // FIXME: template should probably be moved to file to improve
                    // translatibility
                    '<span  ng-class="{ \'marcedit_stacked_subfield\' : stackSubfields.enabled }">' +
                    '<button class="btn btn-info btn-xs" '+
                    'aria-label="Manage authority record links" '+
                    'ng-show="isAuthorityControlled(field)"'+
                    'ng-click="spawnAuthorityLinker()"'+
                    '>'+
                    '<span class="glyphicon glyphicon-link"></span>'+
                    '</button>'+
                    '<span ng-show="field.heading_checked && field.heading_valid" class="glyphicon glyphicon-ok-sign"></span>'+
                    '<span ng-show="field.heading_checked && !field.heading_valid" class="glyphicon glyphicon-question-sign"></span>'+
                    '</span>'+
                  '</div>',
        scope: { field: "=", onKeydown: '=', contextFunctions: '=' },
        replace: true,
        controller : ['$scope','$uibModal',
            function ( $scope,  $uibModal ) {
                $scope.stackSubfields = $scope.$parent.$parent.stackSubfields;
                $scope.isAuthorityControlled = function () {
                    return ($scope.$parent.$parent.record_type == 'bre') &&
                           $scope.$parent.$parent.controlSet.bibFieldByTag($scope.field.tag);
                }
                $scope.spawnAuthorityLinker = function() {
                    // intentionally making a clone in case
                    // user decides to abandon the linking
                    var fieldCopy = new MARC21.Field({
                        tag       : $scope.field.tag,
                        ind1      : $scope.field.ind1,
                        ind2      : $scope.field.ind2
                    });
                    angular.forEach($scope.field.subfields, function(sf) {
                        fieldCopy.subfields.push(sf.slice(0));
                    });
                    var cs = $scope.$parent.$parent.controlSet;
                    var args = { changed : false };
                    $uibModal.open({
                        templateUrl: './cat/share/t_authority_link_dialog',
                        backdrop: 'static',
                        size: 'lg',
                        controller: ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                            $scope.controlSet = cs;
                            $scope.bibField = fieldCopy;
                            $scope.focusMe = true;
                            $scope.args = args;
                            $scope.ok = function(args) { $uibModalInstance.close(args) };
                            $scope.cancel = function () { $uibModalInstance.dismiss() };
                        }]
                    }).result.then(function (args) {
                        if (args.changed) {
                            $scope.field.subfields.length = 0;
                            angular.forEach(fieldCopy.subfields, function(sf) {
                                $scope.field.addSubfields(sf[0], sf[1]);
                            });
                        }
                    });
                }
            }
        ]
    }
})

.directive("egMarcEditControlfield", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-tag context-functions="contextFunctions" field="field" tag="field.tag" on-keydown="onKeydown"/></span>'+
                    '<span><eg-marc-edit-editable '+
                      'itype="cfld" '+
                      'field="field" '+
                      'class="marcedit marcdata" '+
                      'content="field.data" '+
                      'on-keydown="onKeydown" '+
                      'id="r{{field.record.subfield(\'901\',\'c\')[1] || 0}}f{{field.position}}data"'+
                      '/></span>'+
                      // TODO: move to TT2 template
                      '<button class="btn btn-info btn-xs" '+
                      'aria-label="Physical Characteristics Wizard" '+
                      'ng-show="showPhysCharLink()"'+
                      'ng-click="spawnPhysCharWizard()"'+
                      '>'+
                      '<span class="glyphicon glyphicon-edit"></span>'+
                      '</button>'+
                  '</div>',
        scope: { field: "=", onKeydown: '=', contextFunctions: '=' },
        controller : ['$scope','$uibModal',
            function ( $scope,  $uibModal) {
                $scope.showPhysCharLink = function () {
                    return ($scope.$parent.$parent.record_type == 'bre') 
                        && $scope.field.tag == '007';
                }
                $scope.spawnPhysCharWizard = function() {
                    var args = {
                        changed : false,
                        field : $scope.field,
                        orig_value : $scope.field.data
                    };
                    $uibModal.open({
                        templateUrl: './cat/share/t_physchar_dialog',
                        controller: ['$scope','$uibModalInstance',
                            function( $scope , $uibModalInstance) {
                            $scope.focusMe = true;
                            $scope.args = args;
                            $scope.ok = function(args) { $uibModalInstance.close(args) };
                            $scope.cancel = function () { 
                                $uibModalInstance.dismiss();
                                args.field.data = args.orig_value;
                            };
                        }],
                    }).result.then(function (args) {
                        // $scope.field.data is changed within the 
                        // wizard.  Nothing left to do on submit.
                    });

                }
            }
        ]
    }
})

.directive("egMarcEditLeader", function () {
    return {
        transclude: true,
        restrict: 'E',
        template: '<div>'+
                    '<span><eg-marc-edit-editable '+
                      'class="marcedit marctag" '+
                      'content="tag" '+
                      'on-keydown="onKeydown" '+
                      'id="leadertag" '+
                      'is-disabled="disabled"'+
                      '/></span>'+
                    '<span><eg-marc-edit-editable '+
                      'class="marcedit marcdata" '+
                      'itype="ldr" '+
                      'max="{{record.leader.length}}" '+
                      'content="record.leader" '+
                      'id="r{{record.subfield(\'901\',\'c\')[1] || 0}}leaderdata" '+
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
        templateUrl : './cat/share/t_marcedit',
        restrict: 'E',
        replace: true,
        scope: {
            dirtyFlag : '=',
            recordId : '=',
            marcXml : '=',
            bibSource : '=?',
            onSave : '=',
            // in-place mode means that the editor is being
            // used just to munge some MARCXML client-side, rather
            // than to (immediately) update the database
            //
            // In short, we can use inPlaceMode as a way to skip
            // "normal" bre saving and then process the MARC ourselves
            // via a callback
            //
            // inPlaceMode is r/w to allow our Z39.50 import editor to be
            // switched back into a normal editor after the initial import
            inPlaceMode : '=',
            fastAdd : '@',
            flatOnly : '@',
            embedded : '@',
            recordType : '@',
            maxUndo : '@',
            saveLabel : '@'
        },
        link: function (scope, element, attrs) {

            element.bind('mouseup', function(e) {;
                scope.current_event_target = $(e.target).attr('id');
                if (scope.current_event_target && $(e.target).hasClass('noSelection')) {
                    e.preventDefault()
                    return false;
                }
            });

            element.bind('click', function(e) {;
                scope.current_event_target = $(e.target).attr('id');
                if (scope.current_event_target) {
                    console.log('Recording click event on ' + scope.current_event_target);
                    scope.current_event_target_cursor_pos =
                        e.target.selectionDirection=='backward' ?
                            e.target.selectionStart :
                            e.target.selectionEnd;
                }
            });

        },
        controller : ['$timeout','$scope','$q','$window','egCore', 'egTagTable',
                      'egConfirmDialog','egAlertDialog','ngToast','egStrings',
            function ( $timeout , $scope , $q,  $window , egCore ,  egTagTable , 
                       egConfirmDialog , egAlertDialog , ngToast , egStrings) {


                $scope.onSaveCallback = $scope.onSave;
                if (typeof $scope.onSaveCallback !== 'undefined' && !angular.isArray($scope.onSaveCallback))
                    $scope.onSaveCallback = [ $scope.onSaveCallback ];

                $scope.$watch('dirtyFlag',
                    function(newVal, oldVal) {
                        if (newVal && newVal != oldVal && !$scope.opac_iframe) {
                            $($window).on('beforeunload', function(){
                                return egCore.strings.DIRTY_MARC_WARNING;
                            });
                        } else {
                            if (!$scope.opac_iframe)
                                $($window).off('beforeunload');
                        }
                    }
                );

                MARC21.Record.delimiter = '$';

                $scope.enable_fast_add = false;
                $scope.fast_item_callnumber = '';
                $scope.fast_item_barcode = '';

                $scope.flatEditor = { isEnabled : $scope.flatOnly ? true : false };
                
                egCore.hatch.getItem('cat.marcedit.flateditor').then(function(val) {
                    $scope.flatEditor.isEnabled = val;
                });
                
                $scope.$watch('flatEditor.isEnabled', function (newVal, oldVal) {
                    if (newVal != oldVal) egCore.hatch.setItem('cat.marcedit.flateditor', newVal);
                });

                // necessary to prevent ng-model scope hiding ugliness in egMarcEditBibSource:
                $scope.bib_source = {
                    id : $scope.bibSource ? $scope.bibSource : null,
                    name: null
                };
                $scope.brandNewRecord = false;
                $scope.record_type = $scope.recordType || 'bre';
                $scope.max_undo = $scope.maxUndo || 100;
                $scope.record_undo_stack = [];
                $scope.record_redo_stack = [];
                $scope.in_undo = false;
                $scope.in_redo = false;
                $scope.record = new MARC21.Record();
                $scope.save_stack_depth = 0;
                $scope.controlfields = [];
                $scope.datafields = [];
                $scope.controlSet = egTagTable.getAuthorityControlSet();
                $scope.showHelp = false;
                $scope.stackSubfields = { enabled : false };
                egCore.hatch.getItem('cat.marcedit.stack_subfields').then(function(val) {
                    $scope.stackSubfields.enabled = val;
                });
                $scope.$watch('stackSubfields.enabled', function (newVal, oldVal) {
                    if (newVal != oldVal) egCore.hatch.setItem('cat.marcedit.stack_subfields', newVal);
                });
                $scope.caretRecId = $scope.recordId;

                egTagTable.loadTagTable({ marcRecordType : $scope.record_type });

                $scope.saveFlatTextMARC = function () {
                    $scope.record = new MARC21.Record({ marcbreaker : $scope.flat_text_marc });
                };

                $scope.refreshVisual = function () {
                    if (!$scope.flatEditor.isEnabled) {
                        $scope.controlfields = $scope.record.fields.filter(function(f){ return f.isControlfield() });
                        $scope.datafields = $scope.record.fields.filter(function(f){ return !f.isControlfield() });
                    }
                };

                var addDatafield = function (e,before) {
                    var element = $(e.target);

                    var index_field = e.data.scope.field.position;
                    var new_field_index = index_field;

                    var new_field = new MARC21.Field({
                        tag : '999',
                        subfields : [[' ','',0]]
                    });

                    if (Boolean(before)) {
                        e.data.scope.field.record.insertFieldsBefore(
                            e.data.scope.field,
                            new_field
                        );
                    } else {
                        e.data.scope.field.record.insertFieldsAfter(
                            e.data.scope.field,
                            new_field
                        );
                        new_field_index++;
                    }

                    $scope.current_event_target = 'r' + $scope.caretRecId +
                                                  'f' + new_field_index + 'tag';

                    $scope.current_event_target_cursor_pos = 0;
                    $scope.current_event_target_cursor_pos_end = 3;
                    $scope.force_render = true;

                    $timeout(function(){$scope.$digest()}).then(setCaret);
                };

                var deleteDatafield = function (e) {
                    var del_field = e.data.scope.field.position;

                    var sf901c = e.data.scope.field.record.subfield('901','c');
                    var recId = (sf901c === null) ? '' : sf901c[1];
                    var domnode = $('#r' + recId + 'f' + del_field);

                    e.data.scope.field.record.deleteFields(
                        e.data.scope.field
                    );

                    domnode.scope().$destroy();
                    domnode.remove();

                    $scope.current_event_target = 'r' + $scope.caretRecId +
                                                  'f' + del_field + 'tag';

                    $scope.current_event_target_cursor_pos = 0;
                    $scope.current_event_target_cursor_pos_end = 0
                    $scope.force_render = true;

                    $timeout(function(){$scope.$digest()}).then(setCaret);
                };

                var add006 = function (e) {
                    e.data.scope.field.record.insertOrderedFields(
                        new MARC21.Field({
                            tag : '006',
                            data : '                                        '
                        })
                    );

                    $scope.force_render = true;
                    $timeout(function(){$scope.$digest()}).then(setCaret);
                };

                var add007 = function (e) {
                    e.data.scope.field.record.insertOrderedFields(
                        new MARC21.Field({
                            tag : '007',
                            data : '                                        '
                        })
                    );

                    $scope.force_render = true;
                    $timeout(function(){$scope.$digest()}).then(setCaret);
                };

                var reify008 = function (e) {
                    var new_008_data = e.data.scope.field.record.generate008();


                    var old_008s = e.data.scope.field.record.field('008',true);
                    old_008s.forEach(function(o) {
                        var domnode = $('#r'+o.record.subfield('901','c')[1] + 'f' + o.position);
                        domnode.scope().$destroy();
                        domnode.remove();
                        e.data.scope.field.record.deleteFields(o);
                    });

                    e.data.scope.field.record.insertOrderedFields(
                        new MARC21.Field({
                            tag : '008',
                            data : new_008_data
                        })
                    );

                    $scope.force_render = true;
                    $timeout(function(){$scope.$digest()}).then(setCaret);
                };

                $scope.context_functions = {
                    addDatafield : addDatafield,
                    deleteDatafield : deleteDatafield,
                    add006 : add006,
                    add007 : add007,
                    reify008 : reify008
                };

                $scope.onKeydown = function (event) {
                    var event_return = true;

                    console.log(
                        'keydown: which='+event.which+
                        ', ctrlKey='+event.ctrlKey+
                        ', shiftKey='+event.shiftKey+
                        ', altKey='+event.altKey+
                        ', metaKey='+event.altKey
                    );

                    if (event.which == 89 && event.ctrlKey) { // ctrl+y, redo
                        event_return = $scope.processRedo();
                    } else if (event.which == 90 && event.ctrlKey) { // ctrl+z, undo
                        event_return = $scope.processUndo();
                    } else if ((event.which == 68 || event.which == 73) && event.ctrlKey) { // ctrl+d or ctrl+i, insert subfield

                        var element = $(event.target);
                        var new_sf, index_sf, move_data;

                        if (element.hasClass('marcsfvalue')) {
                            index_sf = event.data.scope.subfield[2];
                            new_sf = index_sf + 1;

                            var start = event.target.selectionStart || getCaretPosEditableDiv(element);
                            var end;
                            if (event.target.value){
                                end = event.target.selectionEnd - event.target.selectionStart ?
                                        event.target.selectionEnd :
                                        event.target.value.length;
                            } else {
                                end = element.text().length;
                            }

                            move_data = element.value ?
                                element.value.substring(start,end) :
                                element.text().substring(start, end);

                        } else if (element.hasClass('marcsfcode')) {
                            index_sf = event.data.scope.subfield[2];
                            new_sf = index_sf + 1;
                        } else if (element.hasClass('marctag') || element.hasClass('marcind')) {
                            index_sf = 0;
                            new_sf = index_sf;
                        }

                        $scope.current_event_target = 'r' + $scope.caretRecId +
                                                      'f' + event.data.scope.field.position + 
                                                      's' + new_sf + 'code';

                        event.data.scope.field.subfields.forEach(function(sf) {
                            if (sf[2] >= new_sf) sf[2]++;
                            if (sf[2] == index_sf) {
                                sf[1] = event.target.value ?
                                    event.target.value.substring(0,start) + event.target.value.substring(end) :
                                    element.text().substring(0, start);
                            }
                        });
                        event.data.scope.field.subfields.splice(
                            new_sf,
                            0,
                            [' ', move_data, new_sf ]
                        );

                        $scope.current_event_target_cursor_pos = 0;
                        $scope.current_event_target_cursor_pos_end = 1;

                        $timeout(function(){$scope.$digest()}).then(setCaret);

                        event_return = false;

                    } else if (event.which == 117 && event.shiftKey) { // shift + F6, insert 006
                        add006(event);
                        event_return = false;

                    } else if (event.which == 118 && event.shiftKey) { // shift + F7, insert 007
                        add007(event);
                        event_return = false;

                    } else if (event.which == 119 && event.shiftKey) { // shift + F8, insert/replace 008
                        reify008(event);
                        event_return = false;

                    } else if (event.which == 13 && event.ctrlKey) { // ctrl+enter, insert datafield
                        addDatafield(event, event.shiftKey); // shift key inserts before
                        event_return = false;

                    } else if (event.which == 13 &&
                              ($(event.target).hasClass('marcsf') || $(event.target.parentNode).hasClass('marcsf'))
                              ) {
                        // bare return; don't allow it
                        event_return = false;

                    } else if (event.which == 46 && event.ctrlKey) { // ctrl+del, remove field
                        deleteDatafield(event);
                        event_return = false;

                    } else if (event.which == 46 && event.shiftKey && ($(event.target).hasClass('marcsf') || $(event.target.parentNode).hasClass('marcsf'))) { 
                        // shift+del, remove subfield

                        var sf = event.data.scope.subfield[2] - 1;
                        if (sf == -1) sf = 0;

                        event.data.scope.field.deleteExactSubfields(
                            event.data.scope.subfield
                        );

                        if (!event.data.scope.field.subfields[sf]) {
                            $scope.current_event_target = 'r' + $scope.caretRecId +
                                                          'f' + event.data.scope.field.position + 
                                                          'tag';
                        } else {
                            $scope.current_event_target = 'r' + $scope.caretRecId +
                                                          'f' + event.data.scope.field.position + 
                                                          's' + sf + 'value';
                        }

                        $scope.current_event_target_cursor_pos = 0;
                        $scope.current_event_target_cursor_pos_end = 0;
                        $scope.force_render = true;

                        $timeout(function(){$scope.$digest()}).then(setCaret);

                        event_return = false;

                    } else if (event.keyCode == 38) {
                        if (event.ctrlKey) { // copy the field up
                            var index_field = event.data.scope.field.position;

                            var field_obj;
                            if (event.data.scope.field.isControlfield()) {
                                field_obj = new MARC21.Field({
                                    tag : event.data.scope.field.tag,
                                    data : event.data.scope.field.data
                                });
                            } else {
                                var sf_clone = [];
                                for (var i in event.data.scope.field.subfields) {
                                    sf_clone.push(event.data.scope.field.subfields[i].slice());
                                }
                                field_obj = new MARC21.Field({
                                    tag : event.data.scope.field.tag,
                                    ind1 : event.data.scope.field.ind1,
                                    ind2 : event.data.scope.field.ind2,
                                    subfields : sf_clone
                                });
                            }


                            event.data.scope.field.record.insertFieldsBefore(
                                event.data.scope.field,
                                field_obj
                            );

                            $scope.current_event_target = 'r' + $scope.caretRecId +
                                                          'f' + index_field + 'tag';

                            $scope.current_event_target_cursor_pos = 0;
                            $scope.current_event_target_cursor_pos_end = 3;
                            $scope.force_render = true;

                            $timeout(function(){$scope.$digest()}).then(setCaret);

                        } else { // jump to prev field
                            if (event.data.scope.field.position > 0) {
                                $timeout(function(){
                                    $scope.current_event_target_cursor_pos = 0;
                                    $scope.current_event_target_cursor_pos_end = 0;
                                    $scope.current_event_target = 'r' + $scope.caretRecId +
                                                                  'f' + (event.data.scope.field.position - 1) +
                                                                  'tag';
                                }).then(setCaret);
                            }
                        }

                        event_return = false;

                    } else if (event.keyCode == 40) { // down arrow...
                        if (event.ctrlKey) { // copy the field down

                            var index_field = event.data.scope.field.position;
                            var new_field = index_field + 1;

                            var field_obj;
                            if (event.data.scope.field.isControlfield()) {
                                field_obj = new MARC21.Field({
                                    tag : event.data.scope.field.tag,
                                    data : event.data.scope.field.data
                                });
                            } else {
                                var sf_clone = [];
                                for (var i in event.data.scope.field.subfields) {
                                    sf_clone.push(event.data.scope.field.subfields[i].slice());
                                }
                                field_obj = new MARC21.Field({
                                    tag : event.data.scope.field.tag,
                                    ind1 : event.data.scope.field.ind1,
                                    ind2 : event.data.scope.field.ind2,
                                    subfields : sf_clone
                                });
                            }

                            event.data.scope.field.record.insertFieldsAfter(
                                event.data.scope.field,
                                field_obj
                            );

                            $scope.current_event_target = 'r' + $scope.caretRecId +
                                                          'f' + new_field + 'tag';

                            $scope.current_event_target_cursor_pos = 0;
                            $scope.current_event_target_cursor_pos_end = 3;
                            $scope.force_render = true;

                            $timeout(function(){$scope.$digest()}).then(setCaret);

                        } else { // jump to next field
                            if (event.data.scope.field.record.fields[event.data.scope.field.position + 1]) {
                                $timeout(function(){
                                    $scope.current_event_target_cursor_pos = 0;
                                    $scope.current_event_target_cursor_pos_end = 0;
                                    $scope.current_event_target = 'r' + $scope.caretRecId +
                                                                  'f' + (event.data.scope.field.position + 1) +
                                                                  'tag';
                                }).then(setCaret);
                            }
                        }

                        event_return = false;

                    } else { // Assumes only marc editor elements have IDs that can trigger this event handler.
                        $scope.current_event_target = $(event.target).hasClass('focusable') ? $(event.target) : null;//.attr('id');
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
                        console.log("Putting caret in " + $scope.current_event_target);
                        if (!$scope.current_event_target_cursor_pos_end)
                            $scope.current_event_target_cursor_pos_end = $scope.current_event_target_cursor_pos

                        var element = $('#'+$scope.current_event_target + " .focusable").get(0);
                        if (element) {
                            element.focus();
                            if (element.setSelectionRange) {
                                element.setSelectionRange(
                                    $scope.current_event_target_cursor_pos,
                                    $scope.current_event_target_cursor_pos_end
                                );
                            }
                        }
                        $scope.current_event_cursor_pos_end = null;
                        $scope.current_event_target = null;
                    }
                }

                function getCaretPosEditableDiv(editableDiv){
                    var caretPos = 0, sel, range;
                    if (window.getSelection) {
                        sel = window.getSelection();
                        if (sel.rangeCount) {
                            range = sel.getRangeAt(0);
                            if (range.commonAncestorContainer.parentNode == editableDiv[0]) {
                                caretPos = range.endOffset;
                            }
                        }
                    }
                    return caretPos;
                }

                function loadRecord() {
                    return (function() {
                        var deferred = $q.defer();
                        if ($scope.recordId) {
                            egCore.pcrud.retrieve(
                                $scope.record_type, $scope.recordId
                            ).then(function(rec) {
                                deferred.resolve(rec);
                            });
                        } else {
                            if ($scope.recordType == 'bre') {
                                var bre = new egCore.idl.bre();
                                bre.marc($scope.marcXml);
                                deferred.resolve(bre);
                            } else if ($scope.recordType == 'are') {
                                var are = new egCore.idl.are();
                                are.marc($scope.marcXml);
                                deferred.resolve(are);
                            } else if ($scope.recordType == 'sre') {
                                var sre = new egCore.idl.sre();
                                sre.marc($scope.marcXml);
                                deferred.resolve(sre);
                            }
                            $scope.brandNewRecord = true;
                        }
                        return deferred.promise;
                    })().then(function(rec) {
                        $scope.in_redo = true;
                        $scope[$scope.record_type] = rec;
                        $scope.record = new MARC21.Record({ marcxml : $scope.Record().marc() });
                        if (!$scope.recordId) {
                            var sf901c = $scope.record.subfield('901', 'c');
                            if (sf901c !== null) {
                                $scope.caretRecId = sf901c[1];
                            }
                        }
                        $scope.calculated_record_type = $scope.record.recordType();
                        $scope.controlfields = $scope.record.fields.filter(function(f){ return f.isControlfield() });
                        $scope.datafields = $scope.record.fields.filter(function(f){ return !f.isControlfield() });
                        $scope.save_stack_depth = $scope.record_undo_stack.length;
                        $scope.dirtyFlag = false;
                        $scope.flat_text_marc = $scope.record.toBreaker();

                        if ($scope.record_type == 'bre' && !$scope.brandNewRecord) {
                            $scope.bib_source.id = $scope.bibSource = rec.source(); //$scope.Record().source();
                        }

                    }).then(function(){
                        return egTagTable.fetchFFPosTable($scope.calculated_record_type)
                    }).then(function(){
                        return egTagTable.fetchFFValueTable($scope.calculated_record_type)
                    }).then(setCaret);
                }

                $scope.$watch('record.toBreaker()', function (newVal, oldVal) {
                    if (!$scope.in_undo && !$scope.in_redo && oldVal != newVal) {
                        $scope.record_undo_stack.push({
                            breaker: oldVal,
                            target: $scope.current_event_target,
                            pos: $scope.current_event_target_cursor_pos
                        });

                        if ($scope.force_render) {
                            $scope.controlfields = $scope.record.fields.filter(function(f){ return f.isControlfield() });
                            $scope.datafields = $scope.record.fields.filter(function(f){ return !f.isControlfield() });
                            $scope.force_render = false;
                        }

                        $scope.flat_text_marc = newVal;
                    }

                    if ($scope.record_undo_stack.length != $scope.save_stack_depth) {
                        $scope.dirtyFlag = true;
                    } else {
                        $scope.dirtyFlag = false;
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

                        $scope.record = new MARC21.Record({ marcbreaker : undo_item.breaker });
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

                        $scope.record = new MARC21.Record({ marcbreaker : redo_item.breaker });
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

                $scope.Record = function () {
                    return $scope[$scope.record_type];
                };

                $scope.deleteRecord = function () {
                    egConfirmDialog.open(
                        egCore.strings.CONFIRM_DELETE_RECORD,
                        (($scope.record_type == 'bre') ?
                            egCore.strings.CONFIRM_DELETE_BRE_MSG :
                            egCore.strings.CONFIRM_DELETE_ARE_MSG),
                        { id : $scope.recordId }
                    ).result.then(function() {
                        if ($scope.record_type == 'bre') {
                            egCore.net.request(
                                'open-ils.cat',
                                'open-ils.cat.biblio.record_entry.delete',
                                egCore.auth.token(), $scope.recordId
                            ).then(function(resp) {
                                var evt = egCore.evt.parse(resp);
                                if (evt) {
                                    return egAlertDialog.open(
                                        egCore.strings.ALERT_DELETE_FAILED,
                                        { id : $scope.recordId, desc : evt.desc }
                                    );
                                } else {
                                    loadRecord().then(processOnSaveCallbacks);
                                }
                            });
                        } else {
                            $scope.Record().deleted(true);
                            return $scope.saveRecord();
                        }
                    });
                };

                $scope.undeleteRecord = function () {
                    if ($scope.record_type == 'bre') {
                        egCore.net.request(
                            'open-ils.cat',
                            'open-ils.cat.biblio.record_entry.undelete',
                            egCore.auth.token(), $scope.recordId
                        ).then(function(resp) {
                            var evt = egCore.evt.parse(resp);
                            if (evt) {
                                return egAlertDialog.open(
                                    egCore.strings.ALERT_UNDELETE_FAILED,
                                    { id : $scope.recordId, desc : evt.desc }
                                );
                            } else {
                                ngToast.create(egCore.strings.SUCCESS_UNDELETE_RECORD);
                                loadRecord().then(processOnSaveCallbacks);
                            }
                        });
                    }
                };

                $scope.validateHeadings = function () {
                    if ($scope.record_type != 'bre') return;
                    var chain = $q.when();
                    angular.forEach($scope.record.fields, function(f) {
                        if (!$scope.controlSet.bibFieldByTag(f.tag)) return;
                        // if heading already has a $0, assume it's good
                        if (f.subfield('0', true).length) {
                            f.heading_checked = true;
                            f.heading_valid = true;
                            return;
                        }
                        var auth_match = $scope.controlSet.bibToAuthorities(f);
                        if (auth_match.length == 0) return;
                        chain = chain.then(function() {
                            var promise = egCore.net.request(
                                'open-ils.search',
                                'open-ils.search.authority.simple_heading.from_xml.batch.atomic',
                                auth_match[0]
                            ).then(function (matches) {
                                f.heading_valid = false;
                                if (matches[0]) { // probably set
                                    for (var cset in matches[0]) {
                                        var arr = matches[0][cset];
                                        if (arr.length) {
                                            // protect against errant empty string values
                                            if (arr.length == 1 && arr[0] == '')
                                                continue;
                                            f.heading_valid = true;
                                            break;
                                        }
                                    }
                                }
                                f.heading_checked = true;
                            });
                            return promise;
                        });
                    });
                }

                processOnSaveCallbacks = function() {
                    var deferred = $q.defer();
                    if (typeof $scope.onSaveCallback !== 'undefined') {
                        var promise = deferred.promise;

                        angular.forEach($scope.onSaveCallback, function (f) {
                            if (angular.isFunction(f)) promise = promise.then(f);
                        });

                    }
                    return deferred.resolve($scope.recordId)
                };

                // Returns a promise 
                function createOrUpdateRecord() {

                    var promise;
                    if ($scope.recordId) {  

                        var method = $scope.record_type === 'bre' ?
                            'open-ils.cat.biblio.record.xml.update' :
                            'open-ils.cat.authority.record.overlay';

                        promise = egCore.net.request(
                            'open-ils.cat', method,
                            egCore.auth.token(), $scope.recordId, 
                            $scope.Record().marc(), $scope.bib_source.name
                        );

                    } else {

                        var method = $scope.record_type === 'bre' ?
                            'open-ils.cat.biblio.record.xml.create' :
                            'open-ils.cat.authority.record.import';

                        promise = egCore.net.request(
                            'open-ils.cat', method,
                            egCore.auth.token(), 
                            $scope.Record().marc(),
                            $scope.bib_source.name
                        );
                    }

                    return promise.then(handleCreateOrUpdateResult);
                }

                function handleCreateOrUpdateResult(result) {

                    var evt = egCore.evt.parse(result)
                    var mode = $scope.recordId ? 'update' : 'create';

                    if (evt) {
                        var msg = mode === 'update' ? 
                            egStrings.MARC_ALERT_UPDATE_FAILED :
                            egStrings.MARC_ALERT_CREATE_FAILED;
                        ngToast.warning(msg, {error: '' + evt});
                        return $q.reject();
                    }

                    var msg = mode === 'update' ? 
                        egStrings.MARC_ALERT_UPDATE_SUCCESS :
                        egStrings.MARC_ALERT_CREATE_SUCCESS;
                    ngToast.create(msg);

                    console.debug('MARC create/update returned', result);

                    // synchronize values 
                    if (!$scope.recordId) {
                        $scope.recordId = $scope.caretRecId = result.id(); 
                    }

                    $scope.dirtyFlag = false;

                    return result;
                }

                $scope.saveRecord = function () {
                    
                    if ($scope.inPlaceMode) {
                        $scope.marcXml = $scope.record.toXmlString();
                        
                        if ($scope.record_type == 'bre'){
                            $scope.bibSource = $scope.bib_source.id;
                        }

                        return $timeout(processOnSaveCallbacks);
                    }

                    $scope.mangle_005();
                    $scope.record.pruneEmptyFieldsAndSubfields();
                    $scope.Record().marc($scope.record.toXmlString());

                    var updating = Boolean($scope.recordId);
                    return createOrUpdateRecord().then(function(record) {

                        if (updating) {
                            $scope.save_stack_depth = $scope.record_undo_stack.length;
                        }

                        if (!$scope.enable_fast_add) {
                            return record;
                        }

                        egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.anon_cache.set_value',
                            null, 'edit-these-copies', {
                                record_id: $scope.recordId,
                                raw: [{
                                    label : $scope.fast_item_callnumber,
                                    barcode : $scope.fast_item_barcode,
                                    fast_add : true
                                }],
                                hide_vols : false,
                                hide_copies : false
                            }
                        ).then(function(key) {
                            if (key) {
                                var url = egCore.env.basePath + 'cat/volcopy/' + key;
                                $timeout(function() { $window.open(url, '_blank') });
                            } else {
                                alert('Could not create anonymous cache key!');
                            }
                        });
                    }).then(loadRecord).then(processOnSaveCallbacks);
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
                $scope.$watch('marcXml',
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            loadRecord();
                        }
                    }
                );

                var unregister = $scope.$watch(function() {
                    return egTagTable.initialized();
                }, function(val) {
                    if (val) {
                        unregister();
                        if ($scope.recordId || $scope.marcXml) {
                            loadRecord();
                        }
                    }
                });

                $scope.mangle_005 = function () {
                    var now = new Date();
                    var y = now.getUTCFullYear();
                
                    var m = now.getUTCMonth() + 1;
                    if (m < 10) m = '0' + m;
                
                    var d = now.getUTCDate();
                    if (d < 10) d = '0' + d;
                
                    var H = now.getUTCHours();
                    if (H < 10) H = '0' + H;
                
                    var M = now.getUTCMinutes();
                    if (M < 10) M = '0' + M;
                
                    var S = now.getUTCSeconds();
                    if (S < 10) S = '0' + S;
                
                    var stamp = '' + y + m + d + H + M + S + '.0';
                    var f = $scope.record.field('005',true)[0];
                    if (f) {
                        f.data = stamp;
                    } else {
                        $scope.record.insertOrderedFields(
                            new MARC21.Field({
                                tag : '005',
                                data: stamp
                            })
                        );
                    }
                
                }

            }
        ]          
    }
})

.directive("egMarcEditBibsource", ['$timeout',function ($timeout) {
    return {
        restrict: 'E',
        replace: true,
        template: '<span class="nullable">'+
                    '<select class="form-control" ng-model="bib_source.id" ng-options="s.id() as s.source() for s in bib_sources | orderBy: \'source()\'">'+
                      '<option value="">Select a Source</option>'+
                    '</select>'+
                  '</span>',
        controller: ['$scope','egCore',
            function ($scope , egCore) {

                egCore.pcrud.retrieveAll('cbs', {}, {atomic : true})
                    .then(function(list) {
                        $scope.bib_sources = list;
                    });

                $scope.$watch('bib_source.id',
                    function(newVal, oldVal) {
                        if (newVal !== oldVal) {
                            $scope.bre.source(newVal);
                            var cbs = $scope.bib_sources.filter(function(s) { return s.id() == newVal });
                            $scope.$parent.bib_source.name = (cbs && cbs[0]) ? cbs[0].source() : null;
                        }
                    }
                );

            }
        ]
    }
}])

.directive("egMarcEditAuthorityLinker", function () {
    return {
        restrict: 'E',
        replace: true,
        templateUrl: './cat/share/t_authority_linker',
        scope : {
            bibField : '=',
            controlSet : '=',
            changed : '='
        },
        controller: ['$scope','$uibModal','egCore','egAuth',
            function ($scope , $uibModal,  egCore,  egAuth) {

                $scope.searchStr = '';
                var cni = egCore.env.aous['cat.marc_control_number_identifier'] ||
                  'Set cat.marc_control_number_identifier in Library Settings';

                var axis_list = $scope.controlSet.bibFieldBrowseAxes($scope.bibField.tag);
                $scope.axis = axis_list[0];

                $scope._controlled_sf_list = {};
                $scope._controlled_auth_sf_list = {};
                var found_acs = [];
                angular.forEach($scope.controlSet.controlSetList(), function(acs_id) {
                    if ($scope.controlSet.controlSet(acs_id).control_map[$scope.bibField.tag])
                        found_acs.push(acs_id);
                });
                if (found_acs.length) {
                     angular.forEach($scope.controlSet.controlSet(found_acs[0]).control_map[$scope.bibField.tag],
                        function(value, sf_label) {
                            $scope._controlled_sf_list[ sf_label ] = 1;
                            angular.forEach($scope.controlSet.controlSet(found_acs[0]).control_map[$scope.bibField.tag][sf_label],
                                function(auth_sf, auth_tag) {
                                    if (!$scope._controlled_auth_sf_list[auth_tag]) {
                                        $scope._controlled_auth_sf_list[auth_tag] = { };
                                    }
                                    $scope._controlled_auth_sf_list[auth_tag][auth_sf] = 1;
                                }
                            );
                        }
                    )
                }

                $scope.bibField.subfields.forEach(function (sf) {
                    if (sf[0] in $scope._controlled_sf_list) {
                        sf.selected = true;
                        sf.selectable = true;
                    } else {
                        sf.selectable = false;
                    }
                });
                $scope.summarizeField = function() {
                    var source_f = {
                        'tag': $scope.bibField.tag,
                        'ind1': $scope.bibField.ind1,
                        'ind2': $scope.bibField.ind2,
                        'subfields': []
                    };
                    $scope.bibField.subfields.forEach(function(sf) {
                        if (sf.selected) {
                            source_f.subfields.push([ sf[0], sf[1] ]);
                        }
                    });
                    return source_f;
                }
                $scope.getSearchString = function() {
                    var source_f = $scope.summarizeField();
                    var values = [];
                    angular.forEach(source_f.subfields, function(val) {
                        values.push(val[1]);
                    });
                    return values.join(' ');
                }
                $scope.searchStr = $scope.getSearchString();
                $scope.$watch(function() {
                    var ct = 0;
                    angular.forEach($scope.bibField.subfields, function(sf) {
                        if (sf.selected) ct++
                        });
                    return ct;
                },
                function(newVal, oldVal) {
                    $scope.searchStr = $scope.getSearchString();
                });

                $scope.updateSubfieldZero = function(value) {
                    $scope.changed = true;
                    $scope.bibField.deleteSubfield({ code : ['0'] });
                    $scope.bibField.subfields.push([
                        '0', '(' + cni + ')' + value
                    ]);
                };

                $scope.applyHeading = function(headingField) {
                    // TODO: move the MARC21 rules for copying indicators
                    // out of here
                    if (headingField.tag == '130' && $scope.bibField.tag == '130') {
                        $scope.bibField.ind1 = headingField.ind2;
                    } else {
                        $scope.bibField.ind1 = headingField.ind1;
                    }
                    // deal with 4xx and 5xx
                    var authFallbackTag = '1' + headingField.tag.substr(1, 2);
                    var _valid_auth_sfs = (headingField.tag in $scope._controlled_auth_sf_list) ?
                                          $scope._controlled_auth_sf_list[headingField.tag] :
                                          (authFallbackTag in $scope._controlled_auth_sf_list) ?
                                          $scope._controlled_auth_sf_list[authFallbackTag] :
                                          [];
                    // save the $0 for later use
                    var sfZero = '';
                    if (headingField.subfield('0')) {
                        sfZero = headingField.subfield('0')[1];
                    }
                    // grab any bib subfields not under authority control
                    // TODO do something about uncontrolled subdivisions
                    var uncontrolledBibSf = [];
                    angular.forEach($scope.bibField.subfields, function(sf) {
                        if (!(sf[0] in $scope._controlled_sf_list) && (sf[0] != '0')) {
                            uncontrolledBibSf.push([ sf[0], sf[1] ]);
                        }
                    });
                    // grab the authority subfields
                    var authoritySf = [];
                    angular.forEach(headingField.subfields, function(sf) {
                        if (sf[0] in _valid_auth_sfs) {
                            authoritySf.push([ sf[0], sf[1] ]);
                        }
                    });
                    $scope.bibField.subfields.length = 0;
                    angular.forEach(authoritySf, function(sf) {
                        $scope.bibField.addSubfields(sf[0], sf[1]);
                    });
                    angular.forEach(uncontrolledBibSf, function(sf) {
                        $scope.bibField.addSubfields(sf[0], sf[1]);
                    });
                    if (sfZero) {
                        $scope.bibField.addSubfields('0', sfZero);
                    }
                    $scope.bibField.subfields.forEach(function (sf) {
                    if (sf[0] in $scope._controlled_sf_list) {
                            // intentionally not selecting any subfields
                            // after we've applied an authority heading
                            sf.selected = false;
                            sf.selectable = true;
                        } else {
                            sf.selectable = false;
                        }
                    });
                    $scope.changed = true;
                }

                $scope.createAuthorityFromBib = function(spawn_editor) {
                    var source_f = $scope.summarizeField();

                    var args = { authority_id : 0 };
                    var method = (spawn_editor) ?
                        'open-ils.cat.authority.record.create_from_bib.readonly' :
                        'open-ils.cat.authority.record.create_from_bib';
                    egCore.net.request(
                        'open-ils.cat',
                        method,
                        source_f,
                        cni,
                        egAuth.token()
                    ).then(function(newAuthority) {
                        if (spawn_editor) {
                            $uibModal.open({
                                templateUrl: './cat/share/t_edit_new_authority',
                                size: 'lg',
                                controller:
                                    ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                                    $scope.focusMe = true;
                                    $scope.args = args;
                                    $scope.dirty_flag = false;
                                    $scope.marc_xml = newAuthority,
                                    $scope.ok = function(args) { $uibModalInstance.close(args) }
                                    $scope.cancel = function () { $uibModalInstance.dismiss() }
                                }]
                            }).result.then(function (args) {
                                if (!args || !args.authority_id) return;
                                $scope.updateSubfieldZero(args.authority_id);
                            });
                        } else {
                            $scope.updateSubfieldZero(newAuthority.id());
                        }
                    });
                }

            }
        ]
    }
})

.directive("egPhyscharWizard", ['$sce', function ($sce) {
    return {
        restrict: 'E',
        replace: true,
        templateUrl: './cat/share/t_physchar_wizard',
        scope : {
            field : '='
        },
        controller: ['$scope','$q','egTagTable',
            function ($scope , $q , egTagTable) {

                // $scope.step is the 1-based position in the list of 
                // subfields for the currently selected type.
                // step==0 means we are currently selecting the type
                $scope.step = 0;

                // position and offset of the "subfields" we're
                // currently editing; this is maintained as a convenience
                // for the highlighting of the currently active position
                $scope.offset = 0;
                $scope.len = 1;

                if (!$scope.field.data) 
                    $scope.field.data = '';

                // currently selected subfield value selector option
                $scope.selected_option = null;

                function current_ptype() {
                    return $scope.field.data.substr(0, 1);   
                }

                function current_subfield() {
                    return egTagTable.getPhysCharSubfieldMap(current_ptype())
                    .then(function(sf_list) {return sf_list[$scope.step-1]});
                }

                $scope.values_for_step = [];
                function set_values_for_step() {
                    var promise;

                    if ($scope.step == 0) {
                        $scope.offset = 0;
                        $scope.len    = 1;
                        promise = egTagTable.getPhysCharTypeMap();
                    } else {
                        promise = current_subfield().then(
                            function(subfield) {
                                return egTagTable
                                    .getPhysCharValueMap(subfield.id());
                            }
                        );
                    }

                    return promise.then(function(list) { 
                        $scope.values_for_step = list;
                        set_selected_option_from_field();
                        set_label_for_step();
                    });
                }

                $scope.change_ptype = function(option) {
                    $scope.selected_option = option;
                    var new_val = option.ptype_key();
                    if (current_ptype() != new_val) {
                        $scope.field.data = new_val; // total reset
                    }
                }

                $scope.change_option = function(option) {
                    $scope.selected_option = option;
                    var new_val = option.value();
                    get_step_slot().then(function(slot) {
                        var value = $scope.field.data;
                        while (value.length < (slot[0] + slot[1])) 
                            value += ' ';
                        var before = value.substr(0, slot[0]);
                        var after = value.substr(slot[0] + slot[1]);
                        $scope.field.data = 
                            before + new_val.substr(0, slot[1]) + after;
                        $scope.offset = slot[0];
                        $scope.len    = slot[1];
                    });
                }

                function get_step_slot() {
                    if ($scope.step == 0) return $q.when([0, 1]);
                    return current_subfield().then(function(sf) {
                        return [sf.start_pos(), sf.length()]
                    });
                }

                $scope.is_last_step = function() {
                    // This one is called w/ every digest, so avoid async
                    // calls.  Wait until we have loaded the current ptype
                    // subfields to determine if this is the last step.
                    return (
                        current_ptype() && 
                        egTagTable.phys_char_sf_map[current_ptype()] &&
                        egTagTable.phys_char_sf_map[current_ptype()].length 
                            == $scope.step
                    );
                }

                $scope.label_for_step = '';
                function set_label_for_step() {
                    if ($scope.step > 0) {
                        current_subfield().then(function(sf) {
                            $scope.label_for_step = sf.label();
                        });
                    }
                }
                
                $scope.next_step = function() {
                    $scope.step++;
                    set_values_for_step();
                }

                $scope.prev_step = function() {
                    $scope.step--;
                    set_values_for_step();
                }

                function set_selected_option_from_field() {
                    if ($scope.step == 0) {
                        $scope.selected_option = $scope.values_for_step
                        .filter(function(opt) {
                            return (opt.ptype_key() == current_ptype())})[0];
                    } else {
                        get_step_slot().then(function(slot) {
                            $scope.offset = slot[0];
                            $scope.len    = slot[1];
                            var val = String.prototype.substr.apply(                      
                                $scope.field.data, slot);
                            if (val) {
                                $scope.selected_option = $scope.values_for_step
                                .filter(function(opt) { 
                                    return (opt.value() == val)})[0];
                            } else {
                                $scope.selected_option = null;
                            }
                        })
                    }
                }

                $scope.highlightedFieldData = function() {
                    if (
                            $scope.len && $scope.field.data &&
                            $scope.field.data.length > 0 &&
                            $scope.field.data.length >= $scope.offset
                        ) {
                        return $sce.trustAsHtml(
                            $scope.field.data.substring(0, $scope.offset) + 
                            '<span class="active-physchar">' +
                            $scope.field.data.substr($scope.offset, $scope.len) +
                            '</span>' +
                            $scope.field.data.substr($scope.offset + $scope.len)
                        );
                    } else {
                        return $scope.field.data;
                    }
                };

                set_values_for_step();
            }
        ]
    }
}])


.directive("egMarcEditAuthorityBrowser", function () {
    return {
        restrict: 'E',
        replace: true,
        templateUrl: './cat/share/t_authority_browser',
        scope : {
            searchString : '=',
            controlSet : '=',
            axis : '=',
            applyHeading : '&'
        },
        controller: ['$scope','$http',
            function ($scope , $http) {

                $scope.page = 0;
                $scope.limit = 5;
                $scope.main_headings = [];

                function getHeadingString(headingField) {
                    var heading = '';
                    angular.forEach(headingField.subfields, function (sf) {
                        if (['x', 'y', 'z'].indexOf(sf[0]) > -1) {
                            heading += ' --';
                        }
                        if (heading) {
                            heading += ' ';
                        }
                        heading += sf[1];
                    });
                    return heading;
                }

                $scope.doBrowse = function() {
                    $scope.main_headings.length = 0;
                    if ($scope.searchString.length == 0) return;
                    var type = 'authority.'
                    var url = '/opac/extras/browse/marcxml/'
                            + 'authority.' + $scope.axis + '.refs'
                            + '/1' // OU - currently unscoped
                            + '/' + $scope.searchString
                            + '/' + $scope.page
                            + '/' + $scope.limit;
                    $http({
                        url : url,
                        method : 'GET',
                        transformResponse : function(data) {
                            // use a bit of jQuery to deal with the XML
                            var $xml = $( $.parseXML(data) );
                            var marc = [];
                            $xml.find('record').each(function() {
                                var rec = new MARC21.Record();
                                rec.fromXmlDocument($(this)[0].outerHTML);
                                marc.push(rec);
                            });
                            return marc;
                        }
                    }).then(function(response) {
                        angular.forEach(response.data, function(rec) {
                            var authId = rec.subfield('901', 'c')[1];
                            var auth_org = '';
                            if (rec.field('003')) {
                                auth_org = rec.field('003').data;
                            }
                            var headingField = rec.field('1..');
                            var seeFroms = rec.field('4..', true);
                            var seeAlsos = rec.field('5..', true);

                            var main_heading = {
                                authority_id : authId,
                                heading : getHeadingString(headingField),
                                seealso_headings : [ ],
                                seefrom_headings : [ ],
                            };

                            var sfZero = '';
                            if (auth_org) {
                                sfZero = '(' + auth_org + ')';
                            }
                            sfZero += authId;
                            headingField.addSubfields('0', sfZero);

                            main_heading['headingField'] = headingField;
                            angular.forEach(seeAlsos, function(headingField) {
                                main_heading.seealso_headings.push({
                                    heading : getHeadingString(headingField),
                                    headingField : headingField
                                });
                            });
                            angular.forEach(seeFroms, function(headingField) {
                                main_heading.seefrom_headings.push({
                                    heading : getHeadingString(headingField),
                                    headingField : headingField
                                });
                            });
                            $scope.main_headings.push(main_heading);
                        });
                    });
                }

                $scope.$watch('searchString',
                    function(newVal, oldVal) {
                        if (newVal !== oldVal) {
                            $scope.doBrowse();
                        }
                    }
                );
                $scope.$watch('page',
                    function(newVal, oldVal) {
                        if (newVal !== oldVal) {
                            $scope.doBrowse();
                        }
                    }
                );

                $scope.doBrowse();
            }
        ]
    }
})

;
