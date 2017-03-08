/**
  * UI tools and directives.
  */
angular.module('egUiMod', ['egCoreMod', 'ui.bootstrap'])


/**
 * <input focus-me="iAmOpen"/>
 * $scope.iAmOpen = true;
 */
.directive('focusMe', 
       ['$timeout','$parse', 
function($timeout , $parse) {
    return {
        link: function(scope, element, attrs) {
            var model = $parse(attrs.focusMe);
            scope.$watch(model, function(value) {
                if(value === true) 
                    $timeout(function() {element[0].focus()});
            });
            element.bind('blur', function() {
                $timeout(function() {
                    scope.$apply(model.assign(scope, false));
                });
            })
        }
    };
}])

/**
 * <input blur-me="pleaseBlurMe"/>
 * $scope.pleaseBlurMe = true
 * Useful for de-focusing when no other obvious focus target exists
 */
.directive('blurMe', 
       ['$timeout','$parse', 
function($timeout , $parse) {
    return {
        link: function(scope, element, attrs) {
            var model = $parse(attrs.blurMe);
            scope.$watch(model, function(value) {
                if(value === true) 
                    $timeout(function() {element[0].blur()});
            });
            element.bind('focus', function() {
                $timeout(function() {
                    scope.$apply(model.assign(scope, false));
                });
            })
        }
    };
}])


// <input select-me="iWantToBeSelected"/>
// $scope.iWantToBeSelected = true;
.directive('selectMe', 
       ['$timeout','$parse', 
function($timeout , $parse) {
    return {
        link: function(scope, element, attrs) {
            var model = $parse(attrs.selectMe);
            scope.$watch(model, function(value) {
                if(value === true) 
                    $timeout(function() {element[0].select()});
            });
            element.bind('blur', function() {
                $timeout(function() {
                    scope.$apply(model.assign(scope, false));
                });
            })
        }
    };
}])


// 'reverse' filter 
// <div ng-repeat="item in items | reverse">{{item.name}}</div>
// http://stackoverflow.com/questions/15266671/angular-ng-repeat-in-reverse
// TODO: perhaps this should live elsewhere
.filter('reverse', function() {
    return function(items) {
        return items.slice().reverse();
    };
})

// 'date' filter
// Overriding the core angular date filter with a moment-js based one for
// better timezone and formatting support.
.filter('date',function() {

    var formatMap = {
        short  : 'l LT',
        medium : 'lll',
        long   : 'LLL',
        full   : 'LLLL',

        shortDate  : 'l',
        mediumDate : 'll',
        longDate   : 'LL',
        fullDate   : 'LL',

        shortTime  : 'LT',
        mediumTime : 'LTS'
    };

    var formatReplace = [
        [ /yyyy/g, 'YYYY' ],
        [ /yy/g,   'YY'   ],
        [ /y/g,    'Y'    ],
        [ /ww/g,   'WW'   ],
        [ /w/g,    'W'    ],
        [ /dd/g,   'DD'   ],
        [ /d/g,    'D'    ],
        [ /sss/g,  'SSS'  ],
        [ /EEEE/g, 'dddd' ],
        [ /EEE/g,  'ddd'  ],
        [ /Z/g,    'ZZ'   ]
    ];

    return function (date, format, tz) {
        if (!date) return '';

        if (date == 'now') 
            date = new Date().toISOString();

        if (format) {
            var fmt = formatMap[format] || format;
            angular.forEach(formatReplace, function (r) {
                fmt = fmt.replace(r[0],r[1]);
            });
        }

        var d = moment(date);
        if (tz && tz !== '-') d.tz(tz);

        return d.isValid() ? d.format(fmt) : '';
    }

})

// 'egOrgDate' filter
// Uses moment.js and moment-timezone.js to put dates into the most appropriate
// timezone for a given (optional) org unit based on its lib.timezone setting
.filter('egOrgDate',['$filter','egCore',
             function($filter , egCore) {

    var tzcache = {};

    function eg_date_filter (date, fmt, ouID) {
        if (ouID) {
            if (angular.isObject(ouID)) {
                if (angular.isFunction(ouID.id)) {
                    ouID = ouID.id();
                } else {
                    ouID = ouID.id;
                }
            }
    
            if (!tzcache[ouID]) {
                tzcache[ouID] = '-';
                egCore.org.settings('lib.timezone', ouID)
                .then(function(s) {
                    tzcache[ouID] = s['lib.timezone'] || OpenSRF.tz;
                });
            }
        }

        return $filter('date')(date, fmt, tzcache[ouID]);
    }

    eg_date_filter.$stateful = true;

    return eg_date_filter;
}])

// 'egOrgDateInContext' filter
// Uses the egOrgDate filter to make time and date location aware, and further
// modifies the format if one of [short, medium, long, full] to show only the
// date if the optional interval parameter is day-granular.  This is
// particularly useful for due dates on circulations.
.filter('egOrgDateInContext',['$filter','egCore',
                      function($filter , egCore) {

    function eg_context_date_filter (date, format, orgID, interval) {
        var fmt = format;
        if (!fmt) fmt = 'shortDate';

        // if this is a simple, one-word format, and it doesn't say "Date" in it...
        if (['short','medium','long','full'].filter(function(x){return fmt == x}).length > 0 && interval) {
            var secs = egCore.date.intervalToSeconds(interval);
            if (secs !== null && secs % 86400 == 0) fmt += 'Date';
        }

        return $filter('egOrgDate')(date, fmt, orgID);
    }

    eg_context_date_filter.$stateful = true;

    return eg_context_date_filter;
}])

// 'egDueDate' filter
// Uses the egOrgDateInContext filter to make time and date location aware, but
// only if the supplied interval is day-granular.  This is as wrapper for
// egOrgDateInContext to be used for circulation due date /only/.
.filter('egDueDate',['$filter','egCore',
                      function($filter , egCore) {

    function eg_context_due_date_filter (date, format, orgID, interval) {
        if (interval) {
            var secs = egCore.date.intervalToSeconds(interval);
            if (secs === null || secs % 86400 != 0) {
                orgID = null;
                interval = null;
            }
        }
        return $filter('egOrgDateInContext')(date, format, orgID, interval);
    }

    eg_context_due_date_filter.$stateful = true;

    return eg_context_due_date_filter;
}])

// 'join' filter
// TODO: perhaps this should live elsewhere
.filter('join', function() {
    return function(arr,sep) {
        if (typeof arr == 'object' && arr.constructor == Array) {
            return arr.join(sep || ',');
        } else {
            return '';
        }
    };
})

/**
 * Progress Dialog. 
 *
 * egProgressDialog.open();
 * egProgressDialog.open({value : 0});
 * egProgressDialog.open({value : 0, max : 123});
 * egProgressDialog.increment();
 * egProgressDialog.increment();
 * egProgressDialog.close();
 *
 * Each dialog has 2 numbers, 'max' and 'value'.
 * The content of these values determines how the dialog displays.  
 *
 * There are 3 flavors:
 *
 * -- value is set, max is set
 * determinate: shows a progression with a percent complete.
 *
 * -- value is set, max is unset
 * semi-determinate, with a value report.  Shows a value-less
 * <progress/>, but shows the value as a number in the dialog.
 *
 * This is useful in cases where the total number of items to retrieve
 * from the server is unknown, but we know how many items we've
 * retrieved thus far.  It helps to reinforce that something specific
 * is happening, but we don't know when it will end.
 *
 * -- value is unset
 * indeterminate: shows a generic value-less <progress/> with no 
 * clear indication of progress.
 *
 * Only 1 egProgressDialog instance will be activate at a time.
 * Each invocation of .open() destroys any existing instance.
 */

/* Simple storage class for egProgressDialog data maintenance.
 * This data lives outside of egProgressDialog so it can be 
 * directly imported into egProgressDialog's $uibModalInstance.
 */
.factory('egProgressData', [
    function() {
        var service = {}; // max/value initially unset

        service.reset = function() {
            delete service.max;
            delete service.value;
        }

        service.hasvalue = function() {
            return Number.isInteger(service.value);
        }

        service.hasmax = function() {
            return Number.isInteger(service.max);
        }

        service.percent = function() {
            if (service.hasvalue()  && 
                service.hasmax()    && 
                service.max > 0     &&
                service.value <= service.max)
                return Math.floor((service.value / service.max) * 100);
            return 100;
        }

        return service;
    }
])

.factory('egProgressDialog', [
            'egProgressData','$uibModal', 
    function(egProgressData , $uibModal) {
    var service = {};

    service.open = function(args) {
        service.close(); // force-kill existing instances.

        // Reset to an indeterminate progress bar, 
        // overlay with caller values.
        egProgressData.reset();
        service.update(angular.extend({}, args));

        return $uibModal.open({
            templateUrl: './share/t_progress_dialog',
            controller: ['$scope','$uibModalInstance','egProgressData',
                function( $scope , $uibModalInstance , egProgressData) {
                  service.currentInstance = $uibModalInstance;
                  $scope.data = egProgressData; // tiny service
                }
            ]
        });
    };

    service.close = function() {
        if (service.currentInstance) {
            service.currentInstance.close();
            delete service.currentInstance;
        }
    }

    // Set the current state of the progress bar.
    service.update = function(args) {
        if (args.max != undefined) 
            egProgressData.max = args.max;
        if (args.value != undefined) 
            egProgressData.value = args.value;
    }

    // Increment the current value.  If no amount is specified,
    // it increments by 1.  Calling increment() on an indetermite
    // progress bar will force it to be a (semi-)determinate bar.
    service.increment = function(amt) {
        if (!Number.isInteger(amt)) amt = 1;

        if (!egProgressData.hasvalue())
            egProgressData.value = 0;

        egProgressData.value += amt;
    }

    return service;
}])

/**
 * egAlertDialog.open({message : 'hello {{name}}'}).result.then(
 *     function() { console.log('alert closed') });
 */
.factory('egAlertDialog', 

        ['$uibModal','$interpolate',
function($uibModal , $interpolate) {
    var service = {};

    service.open = function(message, msg_scope) {
        return $uibModal.open({
            templateUrl: './share/t_alert_dialog',
            controller: ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.message = $interpolate(message)(msg_scope);
                    $scope.ok = function() {
                        if (msg_scope && msg_scope.ok) msg_scope.ok();
                        $uibModalInstance.close()
                    }
                }
            ]
        });
    }

    return service;
}])

/**
 * egConfirmDialog.open("some message goes {{here}}", {
 *  here : 'foo', ok : function() {}, cancel : function() {}},
 *  'OK', 'Cancel');
 */
.factory('egConfirmDialog', 
    
       ['$uibModal','$interpolate',
function($uibModal, $interpolate) {
    var service = {};

    service.open = function(title, message, msg_scope, ok_button_label, cancel_button_label) {
        msg_scope = msg_scope || {};
        return $uibModal.open({
            templateUrl: './share/t_confirm_dialog',
            controller: ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.title = $interpolate(title)(msg_scope);
                    $scope.message = $interpolate(message)(msg_scope);
                    $scope.ok_button_label = $interpolate(ok_button_label || '')(msg_scope);
                    $scope.cancel_button_label = $interpolate(cancel_button_label || '')(msg_scope);
                    $scope.ok = function() {
                        if (msg_scope.ok) msg_scope.ok();
                        $uibModalInstance.close()
                    }
                    $scope.cancel = function() {
                        if (msg_scope.cancel) msg_scope.cancel();
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        })
    }

    return service;
}])

/**
 * egPromptDialog.open(
 *    "prompt message goes {{here}}", 
 *    promptValue,  // optional
 *    {
 *      here : 'foo',  
 *      ok : function(value) {console.log(value)}, 
 *      cancel : function() {console.log('prompt denied')}
 *    }
 *  );
 */
.factory('egPromptDialog', 
    
       ['$uibModal','$interpolate',
function($uibModal, $interpolate) {
    var service = {};

    service.open = function(message, promptValue, msg_scope) {
        return $uibModal.open({
            templateUrl: './share/t_prompt_dialog',
            controller: ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.message = $interpolate(message)(msg_scope);
                    $scope.args = {value : promptValue || ''};
                    $scope.focus = true;
                    $scope.ok = function() {
                        if (msg_scope.ok) msg_scope.ok($scope.args.value);
                        $uibModalInstance.close()
                    }
                    $scope.cancel = function() {
                        if (msg_scope.cancel) msg_scope.cancel();
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        })
    }

    return service;
}])

/**
 * egSelectDialog.open(
 *    "message goes {{here}}", 
 *    list,           // ['values','for','dropdown'],
 *    selectedValue,  // optional
 *    {
 *      here : 'foo',
 *      ok : function(value) {console.log(value)}, 
 *      cancel : function() {console.log('prompt denied')}
 *    }
 *  );
 */
.factory('egSelectDialog', 
    
       ['$uibModal','$interpolate',
function($uibModal, $interpolate) {
    var service = {};

    service.open = function(message, inputList, selectedValue, msg_scope) {
        return $uibModal.open({
            templateUrl: './share/t_select_dialog',
            controller: ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.message = $interpolate(message)(msg_scope);
                    $scope.args = {
                        list  : inputList,
                        value : selectedValue
                    };
                    $scope.focus = true;
                    $scope.ok = function() {
                        if (msg_scope.ok) msg_scope.ok($scope.args.value);
                        $uibModalInstance.close()
                    }
                    $scope.cancel = function() {
                        if (msg_scope.cancel) msg_scope.cancel();
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        })
    }

    return service;
}])

/**
 * Warn on page unload and give the user a chance to avoid navigating
 * away from the current page.  
 * Only one handler is supported per page.
 * NOTE: we can't use an egUnloadDialog as the dialog builder, because
 * it renders asynchronously, which allows the page to redirect before
 * the dialog appears.
 */
.factory('egUnloadPrompt', [
        '$window','egStrings', 
function($window , egStrings) {
    var service = {attached : false};

    // attach a page/scope unload prompt
    service.attach = function($scope, msg) {
        if (service.attached) return;
        service.attached = true;

        // handle page change
        $($window).on('beforeunload', function() { 
            service.clear();
            return msg || egStrings.EG_UNLOAD_PAGE_PROMPT_MSG;
        });

        if (!$scope) return;

        // If a scope was provided, attach a scope-change handler,
        // similar to the page-page prompt.
        service.locChangeCancel = 
            $scope.$on('$locationChangeStart', function(evt, next, current) {
            if (confirm(msg || egStrings.EG_UNLOAD_CTRL_PROMPT_MSG)) {
                // user allowed the page to change.  
                // Clear the unload handler.
                service.clear();
            } else {
                evt.preventDefault();
            }
        });
    };

    // remove the page unload prompt
    service.clear = function() {
        $($window).off('beforeunload');
        if (service.locChangeCancel)
            service.locChangeCancel();
        service.attached = false;
    }

    return service;
}])

.directive('aDisabled', function() {
    return {
        restrict : 'A',
        compile: function(tElement, tAttrs, transclude) {
            //Disable ngClick
            tAttrs["ngClick"] = ("ng-click", "!("+tAttrs["aDisabled"]+") && ("+tAttrs["ngClick"]+")");

            //Toggle "disabled" to class when aDisabled becomes true
            return function (scope, iElement, iAttrs) {
                scope.$watch(iAttrs["aDisabled"], function(newValue) {
                    if (newValue !== undefined) {
                        iElement.toggleClass("disabled", newValue);
                    }
                });

                //Disable href on click
                iElement.on("click", function(e) {
                    if (scope.$eval(iAttrs["aDisabled"])) {
                        e.preventDefault();
                    }
                });
            };
        }
    };
})

.directive('egBasicComboBox', function() {
    return {
        restrict: 'E',
        replace: true,
        scope: {
            list: "=", // list of strings
            selected: "=",
            onSelect: "=",
            egDisabled: "=",
            allowAll: "@",
            placeholder: "@",
            focusMe: "=?"
        },
        template:
            '<div class="input-group">'+
                '<input placeholder="{{placeholder}}" type="text" ng-disabled="egDisabled" class="form-control" ng-model="selected" ng-change="makeOpen()" focus-me="focusMe">'+
                '<div class="input-group-btn" dropdown ng-class="{open:isopen}">'+
                    '<button type="button" ng-click="showAll()" ng-disabled="egDisabled" class="btn btn-default dropdown-toggle"><span class="caret"></span></button>'+
                    '<ul class="dropdown-menu dropdown-menu-right">'+
                        '<li ng-repeat="item in list|filter:selected:compare"><a href ng-click="changeValue(item)">{{item}}</a></li>'+
                        '<li ng-if="complete_list" class="divider"><span></span></li>'+
                        '<li ng-if="complete_list" ng-repeat="item in list"><a href ng-click="changeValue(item)">{{item}}</a></li>'+
                    '</ul>'+
                '</div>'+
            '</div>',
        controller: ['$scope','$filter',
            function( $scope , $filter) {

                $scope.complete_list = false;
                $scope.isopen = false;
                $scope.clickedopen = false;
                $scope.clickedclosed = null;

                $scope.compare = function (ex, act) {
                    if (act === null || act === undefined) return true;
                    if (act.toString) act = act.toString();
                    return new RegExp(act.toLowerCase()).test(ex)
                }

                $scope.showAll = function () {

                    $scope.clickedopen = !$scope.clickedopen;

                    if ($scope.clickedclosed === null) {
                        if (!$scope.clickedopen) {
                            $scope.clickedclosed = true;
                        }
                    } else {
                        $scope.clickedclosed = !$scope.clickedopen;
                    }

                    if ($scope.selected && $scope.selected.length > 0) $scope.complete_list = true;
                    if (!$scope.selected || $scope.selected.length == 0) $scope.complete_list = false;
                    $scope.makeOpen();
                }

                $scope.makeOpen = function () {
                    $scope.isopen = $scope.clickedopen || ($filter('filter')(
                        $scope.list,
                        $scope.selected
                    ).length > 0 && $scope.selected.length > 0);
                    if ($scope.clickedclosed) {
                        $scope.isopen = false;
                        $scope.clickedclosed = null;
                    }
                }

                $scope.changeValue = function (newVal) {
                    $scope.selected = newVal;
                    $scope.isopen = false;
                    $scope.clickedclosed = null;
                    $scope.clickedopen = false;
                    if ($scope.selected.length == 0) $scope.complete_list = false;
                    if ($scope.onSelect) $scope.onSelect();
                }

            }
        ]
    };
})

/**
 * Nested org unit selector modeled as a Bootstrap dropdown button.
 */
.directive('egOrgSelector', function() {
    return {
        restrict : 'AE',
        transclude : true,
        replace : true, // makes styling easier
        scope : {
            selected : '=', // defaults to workstation or root org,
                            // unless the nodefault attibute exists

            // Each org unit is passed into this function and, for
            // any org units where the response value is true, the
            // org unit will not be added to the selector.
            hiddenTest : '=',

            // Each org unit is passed into this function and, for
            // any org units where the response value is true, the
            // org unit will not be available for selection.
            disableTest : '=',

            // if set to true, disable the UI element altogether
            alldisabled : '@',

            // Caller can either $watch(selected, ..) or register an
            // onchange handler.
            onchange : '=',

            // optional primary drop-down button label
            label : '@',

            // optional name of settings key for persisting
            // the last selected org unit
            stickySetting : '@'
        },

        // any reason to move this into a TT2 template?
        template : 
            '<div class="btn-group eg-org-selector" uib-dropdown>'
            + '<button type="button" class="btn btn-default" uib-dropdown-toggle ng-disabled="disable_button">'
             + '<span style="padding-right: 5px;">{{getSelectedName()}}</span>'
             + '<span class="caret"></span>'
           + '</button>'
           + '<ul uib-dropdown-menu class="scrollable-menu">'
             + '<li ng-repeat="org in orgList" ng-hide="hiddenTest(org.id)">'
               + '<a href ng-click="orgChanged(org)" a-disabled="disableTest(org.id)" '
                 + 'style="padding-left: {{org.depth * 10 + 5}}px">'
                 + '{{org.shortname}}'
               + '</a>'
             + '</li>'
           + '</ul>'
          + '</div>',

        controller : ['$scope','$timeout','egCore','egStartup','egLovefield','$q',
              function($scope , $timeout , egCore , egStartup , egLovefield , $q) {

            if ($scope.alldisabled) {
                $scope.disable_button = $scope.alldisabled == 'true' ? true : false;
            } else {
                $scope.disable_button = false;
            }

            // avoid linking the full fleshed tree to the scope by 
            // tossing in a flattened list.
            // --
            // Run-time code referencing post-start data should be run
            // from within a startup block, otherwise accessing this
            // module before startup completes will lead to failure.
            //
            // controller() runs before link().
            // This post-startup code runs after link().
            egStartup.go(
            ).then(
                function() {
                    return egCore.env.classLoaders.aou();
                }
            ).then(
                function() {

                    $scope.orgList = egCore.org.list().map(function(org) {
                        return {
                            id : org.id(),
                            shortname : org.shortname(), 
                            depth : org.ou_type().depth()
                        }
                    });
                    
    
                    // Apply default values
    
                    if ($scope.stickySetting) {
                        var orgId = egCore.hatch.getLocalItem($scope.stickySetting);
                        if (orgId) {
                            $scope.selected = egCore.org.get(orgId);
                        }
                    }
    
                    if (!$scope.selected && !$scope.nodefault && egCore.auth.user()) {
                        $scope.selected = 
                            egCore.org.get(egCore.auth.user().ws_ou());
                    }
    
                    fire_orgsel_onchange(); // no-op if nothing is selected
                }
            );

            /**
             * Fire onchange handler after a timeout, so the
             * $scope.selected value has a chance to propagate to
             * the page controllers before the onchange fires.  This
             * way, the caller does not have to manually capture the
             * $scope.selected value during onchange.
             */
            function fire_orgsel_onchange() {
                if (!$scope.selected || !$scope.onchange) return;
                $timeout(function() {
                    console.debug(
                        'egOrgSelector onchange('+$scope.selected.id()+')');
                    $scope.onchange($scope.selected)
                });
            }

            $scope.getSelectedName = function() {
                if ($scope.selected && $scope.selected.shortname)
                    return $scope.selected.shortname();
                return $scope.label;
            }

            $scope.orgChanged = function(org) {
                $scope.selected = egCore.org.get(org.id);
                if ($scope.stickySetting) {
                    egCore.hatch.setLocalItem($scope.stickySetting, org.id);
                }
                fire_orgsel_onchange();
            }

        }],
        link : function(scope, element, attrs, egGridCtrl) {

            // boolean fields are presented as value-less attributes
            angular.forEach(
                ['nodefault'],
                function(field) {
                    if (angular.isDefined(attrs[field]))
                        scope[field] = true;
                    else
                        scope[field] = false;
                }
            );
        }
    }
})

.directive('nextOnEnter', function () {
    return function (scope, element, attrs) {
        element.bind("keydown keypress", function (event) {
            if(event.which === 13) {
                $('#'+attrs.nextOnEnter).focus();
                event.preventDefault();
            }
        });
    };
})

/* http://eric.sau.pe/angularjs-detect-enter-key-ngenter/ */
.directive('egEnter', function () {
    return function (scope, element, attrs) {
        element.bind("keydown keypress", function (event) {
            if(event.which === 13) {
                scope.$apply(function (){
                    scope.$eval(attrs.egEnter);
                });
 
                event.preventDefault();
            }
        });
    };
})

/*
* Handy wrapper directive for uib-datapicker-popup
*/
.directive(
    'egDateInput', ['egStrings', 'egCore',
    function(egStrings, egCore) {
        return {
            scope : {
                id : '@',
                closeText : '@',
                ngModel : '=',
                ngChange : '=',
                ngBlur : '=',
                minDate : '=?',
                maxDate : '=?',
                ngDisabled : '=',
                ngRequired : '=',
                hideDatePicker : '=',
                dateFormat : '=?',
                outOfRange : '=?',
                focusMe : '=?'
            },
            require: 'ngModel',
            templateUrl: './share/t_datetime',
            replace: true,
            controller : ['$scope', function($scope) {
                $scope.options = {
                    minDate : $scope.minDate,
                    maxDate : $scope.maxDate
                };

                var maxDateObj = $scope.maxDate ? new Date($scope.maxDate) : null;
                var minDateObj = $scope.minDate ? new Date($scope.minDate) : null;

                if ($scope.outOfRange !== undefined && (maxDateObj || minDateObj)) {
                    $scope.$watch('ngModel', function (n,o) {
                        if (n && n != o) {
                            var bad = false;
                            var newdate = new Date(n);
                            if (maxDateObj && newdate.getTime() > maxDateObj.getTime()) bad = true;
                            if (minDateObj && newdate.getTime() < minDateObj.getTime()) bad = true;
                            $scope.outOfRange = bad;
                        }
                    });
                }
            }],
            link : function(scope, elm, attrs) {
                if (!scope.closeText)
                    scope.closeText = egStrings.EG_DATE_INPUT_CLOSE_TEXT;

                if ('showTimePicker' in attrs)
                    scope.showTimePicker = true;

                var default_format = 'mediumDate';
                egCore.org.settings(['format.date']).then(function(set) {
                    default_format = set['format.date'];
                    scope.date_format = (scope.dateFormat) ?
                        scope.dateFormat :
                        default_format;
                });
            }
        };
    }
])

/*
 *  egFmValueSelector - widget for selecting a value from list specified
 *                      by IDL class
 */
.directive('egFmValueSelector', function() {
    return {
        restrict : 'E',
        transclude : true,
        scope : {
            idlClass : '@',
            ngModel : '=',

            // optional filter for refining the set of rows that
            // get returned. Example:
            //
            // filter="{'column':{'=':null}}"
            filter : '=',

            // optional name of settings key for persisting
            // the last selected value
            stickySetting : '@',

            // optional OU setting for fetching default value;
            // used only if sticky setting not set
            ouSetting : '@'
        },
        require: 'ngModel',
        templateUrl : './share/t_fm_value_selector',
        controller : ['$scope','egCore', function($scope , egCore) {

            $scope.org = egCore.org; // for use in the link function
            $scope.auth = egCore.auth; // for use in the link function
            $scope.hatch = egCore.hatch // for use in the link function

            function flatten_linked_values(cls, list) {
                var results = [];
                var fields = egCore.idl.classes[cls].fields;
                var id_field;
                var selector;
                angular.forEach(fields, function(fld) {
                    if (fld.datatype == 'id') {
                        id_field = fld.name;
                        selector = fld.selector ? fld.selector : id_field;
                        return;
                    }
                });
                angular.forEach(list, function(item) {
                    var rec = egCore.idl.toHash(item);
                    results.push({
                        id : rec[id_field],
                        name : rec[selector]
                    });
                });
                return results;
            }

            var search = {};
            search[egCore.idl.classes[$scope.idlClass].pkey] = {'!=' : null};
            if ($scope.filter) {
                angular.extend(search, $scope.filter);
            }
            egCore.pcrud.search(
                $scope.idlClass, search, {}, {atomic : true}
            ).then(function(list) {
                $scope.linked_values = flatten_linked_values($scope.idlClass, list);
            });

            $scope.handleChange = function(value) {
                if ($scope.stickySetting) {
                    egCore.hatch.setLocalItem($scope.stickySetting, value);
                }
            }

        }],
        link : function(scope, element, attrs) {
            if (scope.stickySetting && (angular.isUndefined(scope.ngModel) || (scope.ngModel === null))) {
                var value = scope.hatch.getLocalItem(scope.stickySetting);
                scope.ngModel = value;
            }
            if (scope.ouSetting && (angular.isUndefined(scope.ngModel) || (scope.ngModel === null))) {
                scope.org.settings([scope.ouSetting], scope.auth.user().ws_ou())
                .then(function(set) {
                    var value = parseInt(set[scope.ouSetting]);
                    if (!isNaN(value))
                        scope.ngModel = value;
                });
            }
        }
    }
})

/*
 *  egShareDepthSelector - widget for selecting a share depth
 */
.directive('egShareDepthSelector', function() {
    return {
        restrict : 'E',
        transclude : true,
        scope : {
            ngModel : '=',
        },
        require: 'ngModel',
        templateUrl : './share/t_share_depth_selector',
        controller : ['$scope','egCore', function($scope , egCore) {
            $scope.values = [];
            egCore.pcrud.search('aout',
                { id : {'!=' : null} },
                { order_by : {aout : ['depth', 'name']} },
                { atomic : true }
            ).then(function(list) {
                var scratch = [];
                angular.forEach(list, function(aout) {
                    var depth = parseInt(aout.depth());
                    if (depth in scratch) {
                        scratch[depth].push(aout.name());
                    } else {
                        scratch[depth] = [ aout.name() ]
                    }
                });
                scratch.forEach(function(val, idx) {
                    $scope.values.push({ id : idx,  name : scratch[idx].join(' / ') });
                });
            });
        }]
    }
})

/*
 * egHelpPopover - a helpful widget
 */
.directive('egHelpPopover', function() {
    return {
        restrict : 'E',
        transclude : true,
        scope : {
            helpText : '@',
            helpLink : '@'
        },
        templateUrl : './share/t_help_popover',
        controller : ['$scope','$sce', function($scope , $sce) {
            if ($scope.helpLink) {
                $scope.helpHtml = $sce.trustAsHtml(
                    '<a target="_new" href="' + $scope.helpLink + '">' +
                    $scope.helpText + '</a>'
                );
            }
        }]
    }
})

.factory('egWorkLog', ['egCore', function(egCore) {
    var service = {};

    service.retrieve_all = function() {
        var workLog = egCore.hatch.getLocalItem('eg.work_log') || [];
        var patronLog = egCore.hatch.getLocalItem('eg.patron_log') || [];

        return { 'work_log' : workLog, 'patron_log' : patronLog };
    }

    service.record = function(message,data) {
        var max_entries;
        var max_patrons;
        if (typeof egCore != 'undefined') {
            if (typeof egCore.env != 'undefined') {
                if (typeof egCore.env.aous != 'undefined') {
                    max_entries = egCore.env.aous['ui.admin.work_log.max_entries'];
                    max_patrons = egCore.env.aous['ui.admin.patron_log.max_entries'];
                } else {
                    console.log('worklog: missing egCore.env.aous');
                }
            } else {
                console.log('worklog: missing egCore.env');
            }
        } else {
            console.log('worklog: missing egCore');
        }
        if (!max_entries) {
            if (typeof egCore.org != 'undefined') {
                if (typeof egCore.org.cachedSettings != 'undefined') {
                    max_entries = egCore.org.cachedSettings['ui.admin.work_log.max_entries'];
                } else {
                    console.log('worklog: missing egCore.org.cachedSettings');
                }
            } else {
                console.log('worklog: missing egCore.org');
            }
        }
        if (!max_patrons) {
            if (typeof egCore.org != 'undefined') {
                if (typeof egCore.org.cachedSettings != 'undefined') {
                    max_patrons = egCore.org.cachedSettings['ui.admin.patron_log.max_entries'];
                } else {
                    console.log('worklog: missing egCore.org.cachedSettings');
                }
            } else {
                console.log('worklog: missing egCore.org');
            }
        }
        if (!max_entries) {
            max_entries = 20;
            console.log('worklog: defaulting to max_entries = ' + max_entries);
        }
        if (!max_patrons) {
            max_patrons = 10;
            console.log('worklog: defaulting to max_patrons = ' + max_patrons);
        }

        var workLog = egCore.hatch.getLocalItem('eg.work_log') || [];
        var patronLog = egCore.hatch.getLocalItem('eg.patron_log') || [];
        var entry = {
            'when' : new Date(),
            'msg' : message,
            'action' : data.action,
            'actor' : egCore.auth.user().usrname()
        };
        if (data.action == 'checkin') {
            entry['item'] = data.response.params.copy_barcode;
            entry['item_id'] = data.response.data.acp.id();
            if (data.response.data.au) {
                entry['user'] = data.response.data.au.family_name();
                entry['patron_id'] = data.response.data.au.id();
            }
        }
        if (data.action == 'checkout') {
            entry['item'] = data.response.params.copy_barcode;
            entry['user'] = data.response.data.au.family_name();
            entry['item_id'] = data.response.data.acp.id();
            entry['patron_id'] = data.response.data.au.id();
        }
        if (data.action == 'noncat_checkout') {
            entry['user'] = data.response.data.au.family_name();
            entry['patron_id'] = data.response.data.au.id();
        }
        if (data.action == 'renew') {
            entry['item'] = data.response.params.copy_barcode;
            entry['user'] = data.response.data.au.family_name();
            entry['item_id'] = data.response.data.acp.id();
            entry['patron_id'] = data.response.data.au.id();
        }
        if (data.action == 'requested_hold'
            || data.action == 'edited_patron'
            || data.action == 'registered_patron'
            || data.action == 'paid_bill') {
            entry['patron_id'] = data.patron_id;
        }
        if (data.action == 'requested_hold') {
            entry['hold_id'] = data.hold_id;
        }
        if (data.action == 'paid_bill') {
            entry['amount'] = data.total_amount;
        }

        workLog.push( entry );
        if (workLog.length > max_entries) workLog.shift();
        egCore.hatch.setLocalItem('eg.work_log',workLog); // hatch JSONifies the data, so should be okay re: memory leaks?

        if (entry['patron_id']) {
            var temp = [];
            for (var i = 0; i < patronLog.length; i++) { // filter out any matching patron
                if (patronLog[i]['patron_id'] != entry['patron_id']) temp.push(patronLog[i]);
            }
            temp.push( entry );
            if (temp.length > max_patrons) temp.shift();
            patronLog = temp;
            egCore.hatch.setLocalItem('eg.patron_log',patronLog);
        }

        console.log('worklog',entry);
    }

    return service;
}]);
