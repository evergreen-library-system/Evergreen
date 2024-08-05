angular.module('egCoreMod')

.directive('egNavbar', function() {
    return {
        restrict : 'AE',
        transclude : true,
        templateUrl : 'eg-navbar-template',
        controller:['$scope','$window','$location','$timeout','hotkeys','$rootScope',
                    'egCore','$uibModal','ngToast','egOpChange','$element','egLovefield',
            function($scope , $window , $location , $timeout , hotkeys , $rootScope ,
                     egCore , $uibModal , ngToast , egOpChange , $element , egLovefield) {

                $scope.rs = $rootScope;
                $scope.showAngularCirc = false;

                $scope.reprintLast = function () {
                    egCore.print.reprintLast();
                    return;
                }

                function navTo(path) {

                    if (path.match(/^\/eg2\//)) {
                        // Hotkey for /eg2/ page.  Go directly to the
                        // provided URL.
                        $window.location.href = path;
                        return;
                    }

                    path = path.replace(/^\.\//,'');
                    $window.location.href = egCore.env.basePath + path;
                }       

                // adds a keyboard shortcut
                // http://chieffancypants.github.io/angular-hotkeys/
                $scope.addHotkey = function(key, path, desc, elm) {
                    angular.forEach(key.split(' '), function (k) {
                        hotkeys.add({
                            combo: k,
                            allowIn: ['INPUT','SELECT','TEXTAREA'],
                            description: desc,
                            callback: function(e) {
                                e.preventDefault();
                                if (path) return navTo(path);
                                return $timeout(function(){$(elm).trigger('click')});
                            }
                        });
                    });
                };

                function find_accesskeys(elm) {
                    elm = angular.element(elm);
                    if (elm.attr('eg-accesskey')) {
                        $scope.addHotkey(
                            elm.attr('eg-accesskey'),
                            elm.attr('href'),
                            elm.attr('eg-accesskey-desc'),
                            elm
                        );
                    }
                    angular.forEach(elm.children(), find_accesskeys);
                }

                $scope.retrieveLastRecord = function() {
                    var last_record = egCore.hatch.getLocalItem("eg.cat.last_record_retrieved");
                    if (last_record) {
                        $window.location.href = 
                            '/eg2/staff/catalog/record/' + last_record;
                    }
                }

                $scope.applyLocale = function(locale) {
                    // EGWeb.pm can change the locale for us w/ the right param
                    // Note: avoid using $location.search() to derive a new
                    // URL, since it creates an intermediate path change.
                    // Instead, use the ham-fisted approach of killing any
                    // search args and applying the args we want.
                    $window.location.href = egCore.env.basePath +
                        '?set_eg_locale=' + encodeURIComponent(locale);
                }

                $scope.changeOperatorUndo = function() {
                    egOpChange.changeOperatorUndo().then(function() {
                        $scope.op_changed = false;
                        $scope.username = egCore.auth.user().usrname();
                    });
                }

                $scope.changeOperator = function() {
                    egOpChange.changeOperator().then(function() {
                        $scope.op_changed = egCore.auth.OCtoken() ? true : false;
                        $scope.username = egCore.auth.user().usrname();
                    });
                }

                $scope.currentToken = function () {
                    return egCore.auth.token();
                }

                // Returns true if the browser is connected to Hatch
                $scope.hatchConnected = function() {
                    return egCore.hatch.hatchAvailable;
                }

                // tied to logout link
                $scope.logout = function() {
                    egCore.auth.logout();
                    return true;
                };

                $scope.offlineDisabled = function() {
                    return egLovefield.cannotConnect;
                }

                egCore.startup.go().then(
                    function() {
                        if (egCore.auth.user()) {
                            $scope.op_changed = egCore.auth.OCtoken() ? true : false;
                            $scope.username = egCore.auth.user().usrname();
                            $scope.user_id = egCore.auth.user().id();
                            $scope.ws_ou = egCore.auth.user().ws_ou();
                            $scope.workstation = egCore.auth.workstation();

                            egCore.org.settings([
                                'ui.staff.max_recent_patrons',
                                'ui.staff.traditional_catalog.enabled',
                                'ui.staff.angular_circ.enabled',
                                'ui.staff.angular_acq_selection.enabled',
                                'circ.curbside'
                            ]).then(function(s) {
                                var val = s['ui.staff.max_recent_patrons'];
                                $scope.showRecentPatron = val > 0;
                                $scope.showRecentPatrons = val > 1;

                                val = s['ui.staff.traditional_catalog.enabled'];
                                $scope.showTraditionalCatalog = (val !== false);
                                $scope.showAngularAcq =
                                    s['ui.staff.angular_acq_selection.enabled'];
                                $scope.enableCurbside = s['circ.curbside'];

                                if (s['ui.staff.angular_circ.enabled']) {
                                    egCore.perm.hasPermHere('ACCESS_ANGULAR_CIRC')
                                    .then(function(yes) { $scope.showAngularCirc = yes; });
                                }
                            }).then(function() {
                                // need to defer initialization of hotkeys to this point
                                // as it depends on various settings.
                                $timeout(function(){find_accesskeys($element)});
                            });
                        } else {
                            // fallback initialization of hotkeys
                            $timeout(function(){find_accesskeys($element)});
                        }
                    }
                );
            }
        ]
    }
});
 
