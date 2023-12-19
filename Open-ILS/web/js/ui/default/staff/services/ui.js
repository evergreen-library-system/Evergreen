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
                    if (model.assign && typeof model.assign == 'function')
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

// <select int-to-str ><option value="1">Value</option></select>
// use integer models for string values
.directive('intToStr', function() {
    return {
        restrict: 'A',
        require: 'ngModel',
        link: function(scope, element, attrs, ngModel) {
            ngModel.$parsers.push(function(value) {
                return parseInt(value);
            });
            ngModel.$formatters.push(function(value) {
                return '' + value;
            });
        }
    };
})

// <input str-to-int value="10"/>
.directive('strToInt', function() {
    return {
        restrict: 'A',
        require: 'ngModel',
        link: function(scope, element, attrs, ngModel) {
            ngModel.$parsers.push(function(value) {
                return '' + value;
            });
            ngModel.$formatters.push(function(value) {
                return parseInt(value);
            });
        }
    };
})

// <input float-to-str
.directive('floatToStr', function() {
    return {
        restrict: 'A',
        require: 'ngModel',
        link: function(scope, element, attrs, ngModel) {
            ngModel.$parsers.push(function(value) {
                return parseFloat(value);
            });
            ngModel.$formatters.push(function(value) {
                return '' + value;
            });
        }
    };
})

.directive('strToFloat', function() {
    return {
        restrict: 'A',
        require: 'ngModel',
        link: function(scope, element, attrs, ngModel) {
            ngModel.$parsers.push(function(value) {
                return '' + value;
            });
            ngModel.$formatters.push(function(value) {
                return parseFloat(value);
            });
        }
    };
})

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
        if (!fmt) fmt = 'short';

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
        return $uibModal.open({
            templateUrl: './share/t_progress_dialog',
            /* backdrop: 'static', */ /* allow 'cancelling' of progress dialog */
            controller: ['$scope','$uibModalInstance','egProgressData',
                function( $scope , $uibModalInstance , egProgressData) {
                    // Once the new modal instance is available, force-
                    // kill any other instances
                    service.close(true); 

                    // Reset to an indeterminate progress bar, 
                    // overlay with caller values.
                    egProgressData.reset();
                    service.update(angular.extend({}, args));

                    service.currentInstance = $uibModalInstance;
                    $scope.data = egProgressData; // tiny service
                }
            ]
        });
    };

    service.close = function(warn) {
        if (service.currentInstance) {
            if (warn) {
                console.warn("egProgressDialog replacing existing instance. "
                    + "Only one may be open at a time.");
            }
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
        if (args.label != undefined) 
            egProgressData.label = args.label;
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
            backdrop: 'static',
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
            backdrop: 'static',
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
            backdrop: 'static',
            controller: ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.message = $interpolate(message)(msg_scope);
                    $scope.args = {value : promptValue || ''};
                    $scope.focus = true;
                    $scope.ok = function() {
                        if (msg_scope && msg_scope.ok) msg_scope.ok($scope.args.value);
                        $uibModalInstance.close($scope.args);
                    }
                    $scope.cancel = function() {
                        if (msg_scope && msg_scope.cancel) msg_scope.cancel();
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
            backdrop: 'static',
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

/**
 * egAddCopyAlertDialog - manage copy alerts
 */
.factory('egAddCopyAlertDialog', 
       ['$uibModal','$interpolate','egCore',
function($uibModal , $interpolate , egCore) {
    var service = {};

    service.open = function(args) {
        return $uibModal.open({
            templateUrl: './share/t_add_copy_alert_dialog',
            controller: ['$scope','$q','$uibModalInstance',
                function( $scope , $q , $uibModalInstance) {

                    $scope.copy_ids = args.copy_ids;
                    egCore.pcrud.search('ccat',
                        { active : 't' },
                        {},
                        { atomic : true }
                    ).then(function (ccat) {
                        $scope.alert_types = ccat;
                    }); 

                    $scope.copy_alert = {
                        create_staff : egCore.auth.user().id(),
                        note         : '',
                        temp         : false
                    };

                    $scope.ok = function(copy_alert) {
                        if (typeof(copy_alert.note) != 'undefined' &&
                            copy_alert.note != '') {
                            copy_alerts = [];
                            angular.forEach($scope.copy_ids, function (cp_id) {
                                var a = new egCore.idl.aca();
                                a.isnew(1);
                                a.create_staff(copy_alert.create_staff);
                                a.note(copy_alert.note);
                                a.temp(copy_alert.temp ? 't' : 'f');
                                a.copy(cp_id);
                                a.ack_time(null);
                                a.alert_type(
                                    $scope.alert_types.filter(function(at) {
                                        return at.id() == copy_alert.alert_type;
                                    })[0]
                                );
                                copy_alerts.push( a );
                            });
                            if (copy_alerts.length > 0) {
                                egCore.pcrud.apply(copy_alerts).finally(function() {
                                    if (args.ok) args.ok();
                                    $uibModalInstance.close()
                                });
                            }
                        } else {
                            if (args.ok) args.ok();
                            $uibModalInstance.close()
                        }
                    }
                    $scope.cancel = function() {
                        if (args.cancel) args.cancel();
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        })
    }

    return service;
}])

/**
 * egCopyAlertManagerDialog - manage copy alerts
 */
.factory('egCopyAlertManagerDialog', 
       ['$uibModal','$interpolate','egCore',
function($uibModal , $interpolate , egCore) {
    var service = {};

    service.get_user_copy_alerts = function(copy_id) {
        return egCore.pcrud.search('aca', { copy : copy_id, ack_time : null },
            { flesh : 1, flesh_fields : { aca : ['alert_type'] } },
            { atomic : true }
        );
    }

    service.open = function(args) {
        return $uibModal.open({
            templateUrl: './share/t_copy_alert_manager_dialog',
            controller: ['$scope','$q','$uibModalInstance',
                function( $scope , $q , $uibModalInstance) {

                    function init(args) {
                        var defer = $q.defer();
                        if (args.copy_id) {
                            service.get_user_copy_alerts(args.copy_id).then(function(aca) {
                                defer.resolve(aca);
                            });
                        } else {
                            defer.resolve(args.alerts);
                        }
                        return defer.promise;
                    }

                    // returns a promise resolved with the list of circ statuses
                    $scope.get_copy_statuses = function() {
                        if (egCore.env.ccs)
                            return $q.when(egCore.env.ccs.list);

                        return egCore.pcrud.retrieveAll('ccs', null, {atomic : true})
                        .then(function(list) {
                            egCore.env.absorbList(list, 'ccs');
                            return list;
                        });
                    };

                    $scope.mode = args.mode || 'checkin';

                    var next_statuses = [];
                    var seen_statuses = {};
                    $scope.next_statuses = [];
                    $scope.params = {
                        'the_next_status' : null
                    }
                    init(args).then(function(copy_alerts) {
                        $scope.alerts = copy_alerts;
                        angular.forEach($scope.alerts, function(copy_alert) {
                            var state = copy_alert.alert_type().state();
                            copy_alert.evt = copy_alert.alert_type().event();

                            copy_alert.message = copy_alert.note() ||
                                egCore.strings.ON_DEMAND_COPY_ALERT[copy_alert.evt][state];

                            if (copy_alert.temp() == 't') {
                                angular.forEach(copy_alert.alert_type().next_status(), function (st) {
                                    if (!seen_statuses[st]) {
                                        seen_statuses[st] = true;
                                        next_statuses.push(st);
                                    }
                                });
                            }
                        });
                        if ($scope.mode == 'checkin' && next_statuses.length > 0) {
                            $scope.get_copy_statuses().then(function() {
                                angular.forEach(next_statuses, function(st) {
                                    if (egCore.env.ccs.map[st])
                                    	$scope.next_statuses.push(egCore.env.ccs.map[st]);
                                });
                                $scope.params.the_next_status = $scope.next_statuses[0].id();
                            });
                        }
                    });

                    $scope.isAcknowledged = function(copy_alert) {
                        return (copy_alert.acked);
                    };
                    $scope.canBeAcknowledged = function(copy_alert) {
                        return (!copy_alert.ack_time() && copy_alert.temp() == 't');
                    };
                    $scope.canBeRemoved = function(copy_alert) {
                        return (!copy_alert.ack_time() && copy_alert.temp() == 'f');
                    };

                    $scope.ok = function() {
                        var acks = [];
                        angular.forEach($scope.alerts, function (copy_alert) {
                            if (copy_alert.acked) {
                                copy_alert.ack_time('now');
                                copy_alert.ack_staff(egCore.auth.user().id());
                                copy_alert.ischanged(true);
                                acks.push(copy_alert);
                            }
                        });
                        if (acks.length > 0) {
                            egCore.pcrud.apply(acks).finally(function() {
                                if (args.ok) args.ok($scope.params.the_next_status);
                                $uibModalInstance.close()
                            });
                        } else {
                            if (args.ok) args.ok($scope.params.the_next_status);
                            $uibModalInstance.close()
                        }
                    }
                    $scope.cancel = function() {
                        if (args.cancel) args.cancel();
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        })
    }

    return service;
}])

/**
 * egCopyAlertEditorDialog - manage copy alerts
 */
.factory('egCopyAlertEditorDialog', 
       ['$uibModal','$interpolate','egCore',
function($uibModal , $interpolate , egCore) {
    var service = {};

    service.get_user_copy_alerts = function(copy_id) {
        return egCore.pcrud.search('aca', { copy : copy_id, ack_time : null },
            { flesh : 1, flesh_fields : { aca : ['alert_type'] } },
            { atomic : true }
        );
    }

    service.get_copy_alert_types = function() {
        return egCore.pcrud.search('ccat',
            { active : 't' },
            {},
            { atomic : true }
        );
    };

    service.open = function(args) {
        return $uibModal.open({
            templateUrl: './share/t_copy_alert_editor_dialog',
            controller: ['$scope','$q','$uibModalInstance',
                function( $scope , $q , $uibModalInstance) {

                    function init(args) {
                        var defer = $q.defer();
                        if (args.copy_id) {
                            service.get_user_copy_alerts(args.copy_id).then(function(aca) {
                                defer.resolve(aca);
                            });
                        } else {
                            defer.resolve(args.alerts);
                        }
                        return defer.promise;
                    }

                    init(args).then(function(copy_alerts) {
                        $scope.copy_alert_list = copy_alerts;
                    });
                    service.get_copy_alert_types().then(function(ccat) {
                        $scope.alert_types = ccat;
                    });

                    $scope.ok = function() {
                        egCore.pcrud.apply($scope.copy_alert_list).finally(function() {
                            $uibModalInstance.close();
                        });
                    }
                    $scope.cancel = function() {
                        if (args.cancel) args.cancel();
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        })
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
                '<input placeholder="{{placeholder}}" type="text" ng-disabled="egDisabled" class="form-control" ng-model="selected" ng-change="makeOpen()" focus-me="focusMe" ng-click="inputClick()">'+
                '<div class="input-group-btn" uib-dropdown ng-class="{open:isopen}">'+
                    '<button type="button" ng-click="showAll()" ng-disabled="egDisabled" class="btn btn-default" uib-dropdown-toggle><span class="caret"></span></button>'+
                    '<ul uib-dropdown-menu class="dropdown-menu-right">'+
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
                    if (act.toString) {
                        act = act.toString();
                        act = act.replace(/[|\\{}()[\]^$+*?.]/g, '\\$&'); // modify string to make sure characters like [ are accepted in the regex
                    }
                    return new RegExp(act.toLowerCase()).test(ex.toLowerCase());
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

                $scope.inputClick = function() {
                    if ($scope.isopen) {
                        $scope.isopen = false;
                        $scope.clickedclosed = null;
                    }
                }

                $scope.makeOpen = function () {
                    $scope.isopen = $scope.clickedopen || ($filter('filter')(
                        $scope.list,
                        $scope.selected
                    ).length > 0 && $scope.selected && $scope.selected.length > 0);
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

.directive('egListCounts', function() {
    return {
        restrict: 'E',
        replace: true,
        scope: {
            label: "@",
            list: "=", // list of things
            render: "=", // function to turn thing into string; default to stringification
            onSelect: "=" // function to fire when option selected. passed one copy of the selected value
        },
        templateUrl: './share/t_listcounts',
        controller: ['$scope','$timeout',
            function( $scope , $timeout ) {

                $scope.isopen = false;
                $scope.count_hash = {};

                $scope.renderer = $scope.render ? $scope.render : function (x) { return ""+x };

                $scope.$watchCollection('list',function() {
                    $scope.count_hash = {};
                    angular.forEach($scope.list, function (item) {
                        var str = $scope.renderer(item);
                        if (!$scope.count_hash[str]) {
                            $scope.count_hash[str] = {
                                count : 1,
                                value : str,
                                original : item
                            };
                        } else {
                            $scope.count_hash[str].count++;
                        }
                    });
                });

                $scope.selectValue = function (item) {
                    if ($scope.onSelect) $scope.onSelect(item);
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

            // optional typeahead placeholder text
            label : '@',

            // optional name of settings key for persisting
            // the last selected org unit
            stickySetting : '@'
        },

        templateUrl : './share/t_org_select',

        controller : ['$scope','$timeout','egCore','egStartup','$q',
              function($scope , $timeout , egCore , egStartup , $q) {

            // See emptyTypeahead directive below.
            var secretEmptyKey = '_INTERNAL_';

            function formatName(org) {
                return " ".repeat(org.ou_type().depth()) + org.shortname();
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

                    $scope.selecteName = '';

                    $scope.shortNames = egCore.org.list()
                    .filter(function(org) {
                        return !(
                            $scope.hiddenTest && 
                            $scope.hiddenTest(org.id())
                        );
                    }).map(function(org) {
                        return formatName(org);
                    });
    
                    // Apply default values
    
                    if ($scope.stickySetting) {
                        var orgId = egCore.hatch.getLocalItem($scope.stickySetting);
                        if (orgId) {
                            var org = egCore.org.get(orgId);
                            if (org) {
                                $scope.selected = org;
                                $scope.selectedName = org.shortname();
                            }
                        }
                    }
    
                    if (!$scope.selected && !$scope.nodefault && egCore.auth.user()) {
                        var org = egCore.org.get(egCore.auth.user().ws_ou());
                        $scope.selected = org;
                        $scope.selectedName = org.shortname();
                    }
    
                    fire_orgsel_onchange(); // no-op if nothing is selected
                    watch_external_changes();
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

            // Force the compare filter to run when the input is
            // clicked.  This allows for displaying all values when
            // clicking on an empty input.
            $scope.handleClick = function (e) {
                $timeout(function () {
                    var current = $scope.selectedName;
                    // HACK-CITY
                    // Force the input value to "" so when the compare 
                    // function runs it will see the special empty key
                    // instead of the selected value.
                    $(e.target).val('');
                    $(e.target).trigger('input');
                    // After the compare function runs, reset the the
                    // selected value.
                    $scope.selectedName = current;
                });
            }

            $scope.compare = function(shortName, inputValue) {
                return inputValue === secretEmptyKey ||
                    (shortName || '').toLowerCase().trim()
                        .indexOf((inputValue || '').toLowerCase().trim()) > -1;
            }

            // Trim leading tree-spaces before displaying selected value
            $scope.formatDisplayName = function(shortName) {
                return ($scope.selectedName || '').trim();
            }

            $scope.orgIsDisabled = function(shortName) {
                if ($scope.alldisabled === 'true') return true;
                if (shortName && $scope.disableTest) {
                    var org = egCore.org.list().filter(function(org) {
                        return org.shortname() === shortName.trim();
                    })[0];

                    return org && $scope.disableTest(org.id());
                }
                return false;
            }

            $scope.inputChanged = function(shortName) {
                // Avoid watching for changes on $scope.selected while
                // manually applying values below.
                unwatch_external_changes();

                // Manually prevent selection of disabled orgs
                if ($scope.selectedName && 
                    !$scope.orgIsDisabled($scope.selectedName)) {
                    $scope.selected = egCore.org.list().filter(function(org) {
                        return org.shortname() === $scope.selectedName.trim()
                    })[0];
                } else {
                    $scope.selected = null;
                }
                if ($scope.selected && $scope.stickySetting) {
                    egCore.hatch.setLocalItem(
                        $scope.stickySetting, $scope.selected.id());
                }

                fire_orgsel_onchange();
                $timeout(watch_external_changes);
            }

            // Propagate external changes on $scope.selected to the typeahead
            var dewatcher;
            function watch_external_changes() {
                dewatcher = $scope.$watch('selected', function(newVal, oldVal) {
                    if (newVal) {
                        $scope.selectedName = newVal.shortname();
                    } else {
                        $scope.selectedName = '';
                    }
                });
            }

            function unwatch_external_changes() {
                if (dewatcher) {
                    dewatcher();
                    dewatcher = null;
                }
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

/*
https://stackoverflow.com/questions/24764802/angular-js-automatically-focus-input-and-show-typeahead-dropdown-ui-bootstra
*/
.directive('emptyTypeahead', function () {
    return {
        require: 'ngModel',
        link: function(scope, element, attrs, modelCtrl) {

            var secretEmptyKey = '_INTERNAL_';

            // this parser run before typeahead's parser
            modelCtrl.$parsers.unshift(function (inputValue) {
                // replace empty string with secretEmptyKey to bypass typeahead-min-length check
                var value = (inputValue ? inputValue : secretEmptyKey);
                // this $viewValue must match the inputValue pass to typehead directive
                modelCtrl.$viewValue = value;
                return value;
            });

            // this parser run after typeahead's parser
            modelCtrl.$parsers.push(function (inputValue) {
                // set the secretEmptyKey back to empty string
                return inputValue === secretEmptyKey ? '' : inputValue;
            });
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
                hideTimePicker : '=?',
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
                        var bad = false;
                        var newdate = new Date(n);
                        if (isNaN(newdate.getTime())) bad = true;
                        if (maxDateObj && newdate.getTime() > maxDateObj.getTime()) bad = true;
                        if (minDateObj && newdate.getTime() < minDateObj.getTime()) bad = true;
                        $scope.outOfRange = bad;
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
                    if (set) default_format = set['format.date'];
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
            useOpacLabel : '@',
            maxDepth : '@',
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
                    if (typeof $scope.maxDepth == 'undefined' || depth <= $scope.maxDepth) {
                        var text = $scope.useOpacLabel ? aout.opac_label() : aout.name();
                        if (depth in scratch) {
                            scratch[depth].push(text);
                        } else {
                            scratch[depth] = [ text ]
                        }
                    }
                });
                scratch.forEach(function(val, idx) {
                    $scope.values.push({ id : idx,  name : scratch[idx].join(' / ') });
                });
            });
        }],
        link : function(scope, elm, attrs) {
            if ('useOpacLabel' in attrs)
                scope.useOpacLabel = true;
            if ('maxDepth' in attrs) // I feel like I'm doing this wrong :)
                scope.maxDepth = parseInt(attrs.maxdepth);
        }
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
            || data.action == 'canceled_hold'
            || data.action == 'edited_patron'
            || data.action == 'registered_patron'
            || data.action == 'paid_bill') {
            entry['patron_id'] = data.patron_id;
        }
        if (data.action == 'requested_hold'
            || data.action == 'canceled_hold') {
            entry['hold_id'] = data.hold_id;
        }
        if (data.action == 'paid_bill') {
            entry['amount'] = data.total_amount;
        }
        if (data.action == 'canceled_hold') {
            entry['item_id'] = data.item_id;
            entry['item'] = data.item;
            entry['user'] = data.user;
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
