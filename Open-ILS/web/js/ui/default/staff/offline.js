/**
 * App to drive the offline UI
 */

lf.isOffline = true;

angular.module('egOffline', ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'ngToast', 'tableSort'])

.config(
       ['$routeProvider','$locationProvider','$compileProvider',
function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/);

    /**
     * Route resolvers allow us to run async commands
     * before the page controller is instantiated.
     */
    var resolver = {delay : ['egCore', 'egLovefield',
        function(egCore, egLovefield) {
            // the 'offline' schema is only active in the offline UI.
            egLovefield.activeSchemas.push('offline');
            return egCore.startup.go();
        }
    ]};

    $routeProvider.when('/offline-interface/:tab', {
        templateUrl: 'offline-template',
        controller: 'OfflineCtrl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : 'offline-template',
        controller : 'OfflineCtrl',
        resolve : resolver
    });
}])

.controller('OfflineSessionCtrl', 
           ['$scope','$window','egCore','$routeParams','$http','$q','$timeout','egPromptDialog','ngToast','egProgressDialog',
    function($scope , $window , egCore , $routeParams , $http , $q , $timeout , egPromptDialog , ngToast , egProgressDialog) {
        $scope.active_session_tab = 'pending';

        $scope.lookupNoncatTypeName = function (type) {
            var nc =  $scope.noncats.filter(function(n){ return n.id() == type })[0];
            if (nc) return nc.name();
            return '';
        }

        $scope.createDate = function (ts, epoch) {
            if (!ts) return '';
            if (epoch) ts = ts * 1000;
            return new Date(ts);
        }

        $scope.setSession = function (s, ind) {
            $scope.current_session = s;
            $scope.current_session_index = ind;

            return $scope.refreshExceptions(s);
        }

        $scope.createSession = function () {

            return egPromptDialog.open(
                egCore.strings.OFFLINE_SESSION_DESC, '',
                {ok : function(value) {
                    if (value) {

                        return $http.get(formURL({action:'create',desc:value})).then(function(res) {
                            if (res.data.ilsevent == "0") return $q.when(res.data.payload);
                            return $q.reject();
                        }).then(function (seskey) {
                            return $scope.refreshSessions().then(function() {
                                if (seskey) {
                                    var s = $scope.sessions.filter(function(s){ s.key == seskey })[0];
                                    var ind = $scope.sessions.length - 1; // sorted by create time, so new one is last
                                    return $scope.setSession(s, ind);
                                }
                            });
                        }, function() {
                            ngToast.warning(egCore.strings.OFFLINE_SESSION_CREATE_FAILED);
                        });
                    }
                }}
            );
        }

        $scope.processSession = function (s, ind) {
            return $scope.setSession(s, ind).then(function() {
                egProgressDialog.open();

                return $http.get(
                    formURL({action:'execute',seskey:$scope.current_session.key})
                ).then(function(res) {
                    if (res.data.ilsevent == "0") return $q.when(res.data.payload);
                    return $q.reject();
                }).then(function () {
                    egProgressDialog.close();
                    return $scope.refreshSessions()
                        .then(function(){ return $scope.refreshExceptions(s) });
                },function () {
                    egProgressDialog.close();
                    return $scope.refreshSessions().then(function() {
                        ngToast.warning(egCore.strings.OFFLINE_SESSION_PROCESSING_FAILED);
                    });
                });
            });
        }

        $scope.refreshExceptions = function (s) {
            return $http.get(
                formURL({
                    action      : 'status',
                    status_type : 'exceptions',
                    seskey      : s.key
                })
            ).then(function(res) {
                if (res.data.ilsevent) {
                    $scope.current_session.exceptions = [];
                } else {
                    $scope.current_session.exceptions = res.data;
                }
                return $q.when();
            });
        }

        $scope.sessions = [];
        $scope.refreshSessions = function () {

            return $http.get(formURL({action:'status',status_type:'sessions'})).then(function(res) {
                if (angular.isArray(res.data)) {
                    $scope.sessions = res.data;
                    return $q.when();
                }
                return $q.reject();
            }).then(function() {
                var creator_list = [$q.when()];
                angular.forEach($scope.sessions, function (s) {
                    s.total = 0;
                    s.org = egCore.org.get(s.org).shortname();
                    creator_list.push(egCore.pcrud.retrieve('au',s.creator).then(function(u) {
                        s.creator = u.family_name();
                    }));
                    angular.forEach(s.scripts, function(sc) {
                        s.total += sc.count;
                    });
                });

                return $q.all(creator_list);
            });
        }

        $scope.reprintLast = function () {
            egCore.print.reprintLast();
        }


        $scope.uploadPending = function (s, ind) {
            return $scope.setSession(s, ind).then(function() {

                egProgressDialog.open();
                return $scope.createOfflineXactBlob().then(function(blob) {

                    var form = new FormData();
                    form.append("ses", egCore.auth.token());
                    form.append("org", $scope.org.id());
                    form.append("ws", $scope.current_workstation_name());
                    form.append("wc", 1);
                    form.append("action", "load");
                    form.append("seskey", $scope.current_session.key);
                    form.append("file", blob, "file");

                    return $http.post(
                        '/cgi-bin/offline/offline.pl?' + new Date().getTime(),
                        form,
                        {
                            transformRequest: angular.identity,
                            headers: {'Content-Type': undefined}
                        }
                    ).then(function(res) {
                        egProgressDialog.close();
                        if (res.data.ilsevent == "0") {
                            return $scope.clear_pending(true).then(function() {
                                return $scope.refreshSessions();
                            });
                        } else {
                            ngToast.warning(egCore.strings.OFFLINE_SESSION_UPLOAD_FAILED);
                            return $scope.refreshSessions();
                        }
                    },function () { egProgressDialog.close() });
                });
            });
        }

        $scope.retrieveDetails = function (x) {
            alert(JSON.stringify(x, null, 2)); // egAlertDialog kills pretty printing
        }

        $scope.retrieveItem = function (bc) {
            return egCore.pcrud.search('acp',{deleted: 'f', barcode: bc}).then(function(copy) {
                if (copy) {
                    return $window.open(
                        egCore.env.basePath +
                        '/cat/item/' + copy.id(),
                        '_blank'
                    ).focus();
                }

                ngToast.warning(egCore.strings.ITEM_NOT_FOUND);
            });
        }

        $scope.retrievePatron = function (bc) {
            return egCore.pcrud.search('ac',{barcode: bc}).then(function(card) {
                if (card) {
                    return $window.open(
                        egCore.env.basePath +
                        '/circ/patron/' + card.usr() + '/checkout',
                        '_blank'
                    ).focus();
                }

                ngToast.warning(egCore.strings.PATRON_NOT_FOUND);
            });
        }

        function formURL (params) {
            var url = '/cgi-bin/offline/offline.pl?' + new Date().getTime();

            var defaults = {
                org : $scope.org ? $scope.org.id() : null,
                ws  : $scope.current_workstation_name(),
                wc  : 1,
                ses : egCore.auth.token()
            }

            angular.extend(params, defaults)

            var first = true;
            for (var k in params) {
                url += '&' + k + '=' + window.encodeURIComponent(params[k]);
            }
            return url;
        }

        $scope.$watch('org',function(n){if (n) $scope.refreshSessions()});

    }
])

.controller('OfflineCtrl', 
           ['$q','$scope','$window','$location','$rootScope','egCore',
            'egLovefield','$routeParams','$timeout','$http','ngToast',
            'egConfirmDialog','egUnloadPrompt','egProgressDialog', '$filter',
    function($q , $scope , $window , $location , $rootScope , egCore , 
             egLovefield , $routeParams , $timeout , $http , ngToast , 
             egConfirmDialog , egUnloadPrompt, egProgressDialog, $filter) {

        // Immediately redirect if we're really offline
        if (!$window.navigator.onLine) {
            if ($location.path().match(/session$/)) {
                var path = $location.path();
                console.log('internal redirect');
                return $location.path(path.replace('session','checkout'));
            }
        }

        var today = new Date();
        today.setHours(0);
        today.setMinutes(0);
        today.setSeconds(0);
        today.setMilliseconds(0);

        $scope.minDate = today;
        $scope.blocked_patron = null;
        $scope.bad_barcode = null;
        $scope.barcode_type = 'barcode';
        $scope.focusMe = true;
        $scope.shared = { outOfRange : false, due_date : null, due_date_offset : '' };
        $scope.workstation_obj = null;
        $scope.workstation = '';
        $scope.workstation_owner = '';
        $scope.workstations = [];
        $scope.org = null;
        $scope.do_print = Boolean($scope.active_tab == 'checkout');
        $scope.do_print_changed = false;
        $scope.printed = false;
        $scope.imported_pending_xacts = { data : '' };

        $scope.xact_page = { checkin:[], checkout:[], renew:[], in_house_use:[] };
        $scope.all_xact = [];
        $scope.noncats = [];

        $scope.checkout = { noncat_type : '' };
        $scope.renew = { noncat_type : '' };
        $scope.in_house_use = {count : 1};
        $scope.checkin = { backdate : new Date() };

        egLovefield.getOfflineBlockDate().then(
            function(blockListDateResp) {
                if (blockListDateResp) {
                    $scope.blockListDate =
                        Math.round(blockListDateResp.getTime() / 1000);
                }
            },
            function() {
                console.error("Error when retrieving block list download date");
            }
        );

        $scope.current_workstation_owning_lib = function () {
            return $scope.workstations.filter(function(w) {
                return $scope.workstation == w.id
            })[0].owning_lib;
        }

        $scope.current_workstation_name = function () {
            return $scope.workstations.filter(function(w) {
                return $scope.workstation == w.id
            })[0].name;
        }

        $scope.$watch('workstation', function (n,o) {
            if (egCore.env.aou)
                $scope.org = egCore.org.get($scope.current_workstation_owning_lib());
        });

        $scope.changeCheck = function () {
            $scope.strict_barcode = !$scope.strict_barcode;
            $scope.do_check_changed = true;
            egCore.hatch.setItem('eg.offline.strict_barcode', $scope.strict_barcode)
        }

        $scope.changePrint = function () {
            $scope.do_print = !$scope.do_print;
            $scope.do_print_changed = true;
            egCore.hatch.setItem('eg.offline.print_receipt', $scope.do_print)
        }

        $scope.lookupNoncatTypeName = function (type) {
            var nc =  $scope.noncats.filter(function(n){ return n.id() == type })[0];
            if (nc) return nc.name();
            return '';
        }

        $scope.logged_in = egCore.auth.token() ? true : false;


        $scope.active_tab = $routeParams.tab;
        $timeout(function(){
            if (!$scope.logged_in) {
                $scope.active_tab = 'checkout';
            } else {
                $scope.active_tab = 'session';
            }
        });
        
        egCore.hatch.getItem('eg.offline.print_receipt')
        .then(function(setting) {
            $scope.do_print = setting;
            if (setting !== undefined) $scope.do_print_changed = true;
        });

        egCore.hatch.getItem('eg.offline.strict_barcode')
        .then(function(setting) {
            $scope.strict_barcode = setting;
            if (setting !== undefined) $scope.do_check_changed = true;
        });

        egCore.hatch.getWorkstations()
        .then(function(all) {
            if (all && all.length) {
                $scope.workstations = all;

                if (ws = $location.search().ws) {
                    // user requested a workstation via URL
                    var match = all.filter(
                        function(w) {return ws == w.name} )[0];

                    if (match) {
                        // requested WS registered on this client
                        $scope.workstation_obj = match;
                        $scope.workstation = match.id;
                        $scope.workstation_owner = match.owning_lib;
                    } else {
                        // the requested WS is not registered on this client
                        $scope.wsNotRegistered = true;
                    }
                } else {
                    // no workstation requested; use the default
                    egCore.hatch.getDefaultWorkstation()
                    .then(function(ws) {
                        var ws_obj = all.filter(function(w) {
                            return ws == w.name
                        })[0];

                        $scope.workstation_obj = ws_obj;
                        $scope.workstation = ws_obj.id;
                        $scope.workstation_owner = ws_obj.owning_lib;

                        return egLovefield.reconstituteList('cnct').then(function () {
                            $scope.noncats = egCore.env.cnct.list;
                        });
                    });
                }
            } 
        });

        $scope.buildingBlockList = false;
        $scope.downloadBlockList = function () {
            $scope.buildingBlockList = true;
            egProgressDialog.open();
            egLovefield.populateBlockList().then(
                function(){
                    egLovefield.setOfflineBlockDate();
                    ngToast.create(egCore.strings.OFFLINE_BLOCKLIST_SUCCESS);
                },
                function(){
                    ngToast.warning(egCore.strings.OFFLINE_BLOCKLIST_FAIL);
                    egCore.audio.play('warning.offline.blocklist_fail');
                }
            )['finally'](function() {
                $scope.buildingBlockList = false;
                egProgressDialog.close();
            });
        }

        $scope.createOfflineXactBlob = function () {
            return egLovefield.retrievePendingOfflineXacts().then(function(list) {
                var flat_list = [];
                angular.forEach(list, function (i) {
                    flat_list.push(JSON.stringify(i) + '\n');
                });

                var blob = new Blob(flat_list, {type: 'text/plain'});

                return $q.when(blob)
            });
        }

        $scope.pending_xacts = [];
        $scope.retrieve_pending = function () {
            return egLovefield.retrievePendingOfflineXacts().then(function(list) {
                $scope.pending_xacts = list;
                return $q.when(list);
            });
        }

        $scope.save = function () {
            var promises = [$q.when()];
            angular.forEach($scope.all_xact, function (x) {
                promises.push(egLovefield.addOfflineXact(x));
            });

            var prints = [$q.when()];
            if ($scope.do_print) {
                angular.forEach(['checkin','checkout','renew','in_house_use'], function(xtype) {
                    if ($scope.xact_page[xtype].length > 0) {
                        prints.push(egCore.print.print({
                            context : 'offline', 
                            template : 'offline_'+xtype,
                            scope : {
                                transactions    : $scope.xact_page[xtype]
                            }
                        }));
                    }
                });
            }

            return $q.all(promises.concat(prints)).finally(function() {
                egUnloadPrompt.clear();
                if (prints.length > 1) $scope.printed = true;
                $scope.all_xact = [];
                $scope.xact_page = { checkin:[], checkout:[], renew:[], in_house_use:[] };
                angular.forEach(['checkout','renew'], function (xtype) {
                    $scope[xtype].patron_barcode = '';
                });
                $scope.retrieve_pending();
            });
        }

        $rootScope.save_offline_xacts = function () { return $scope.save() };
        $rootScope.active_tab = function (t) { $scope.active_tab = t };

        $scope.logout = function () {
            egCore.auth.logout();
            $window.location.href = location.href;
        }

        $scope.clear_pending = function (skip_confirm) {
            if (skip_confirm) {
                return egLovefield.destroyPendingOfflineXacts().then(function () {
                    return $scope.retrieve_pending();
                });
            }
            return egConfirmDialog.open(
                egCore.strings.CONFIRM_CLEAR_PENDING,
                egCore.strings.CONFIRM_CLEAR_PENDING_BODY,
                {}
            ).result.then(function() {
                return egLovefield.destroyPendingOfflineXacts().then(function () {
                    return $scope.retrieve_pending();
                });
            });

        }

        $scope.retrieve_pending();
        $scope.$watch('active_tab', function (n,o) {
            console.log('watch caught change to active_tab: ' + o + ' -> ' + n);
            if (n != o && !$scope.do_check_changed && n != 'checkout') $scope.strict_barcode = false;
            if (n != o && !$scope.do_check_changed && n == 'checkout') $scope.strict_barcode = true;
            if (n != o && !$scope.do_print_changed && n != 'checkout') $scope.do_print = false;
            if (n != o && !$scope.do_print_changed && n == 'checkout') $scope.do_print = true;
            if (n != o && n == 'session') $scope.retrieve_pending();
        });

        $scope.$watch('imported_pending_xacts.data', function (n, o) {
            if (n != 0) {
                var lines = n.split('\n');
                var promises = [];

                angular.forEach(lines, function (l) {
                    if (!l) return;

                    try {
                        promises.push(
                            egLovefield.addOfflineXact(JSON.parse(l))
                        );
                    } catch (err) {
                        ngToast.warning(err);
                    }
                });

                $q.all(promises).then(function () { $scope.retrieve_pending() });
            }
        });

        $scope.resetDueDate = function (xtype) {
            $scope.shared.due_date = new Date();
            $scope.shared.due_date.setDate($scope.shared.due_date.getDate() + parseInt($scope.shared.due_date_offset));
        }

        $scope.notEnough = function (xtype) {

            if (xtype == 'checkout') {
                if ($scope.shared.outOfRange) return true;
                if (
                    $scope.checkout.patron_barcode &&
                    ($scope.shared.due_date || $scope.shared.due_date_offset) &&
                    ($scope.checkout.barcode || ($scope.checkout.noncat_type && $scope.checkout.noncat_count))
                ) return false;
                return true;
            }

            if (xtype == 'renew') {
                if ($scope.shared.outOfRange) return true;
                if (
                    $scope.renew.barcode &&
                    ($scope.shared.due_date || $scope.shared.due_date_offset)
                ) return false;
                return true;
            }

            if (xtype == 'in_house_use') {
                if (
                    $scope.in_house_use.barcode && $scope.in_house_use.count
                ) return false;
                return true;
            }

            if (xtype == 'checkin') {
                if (
                    $scope.checkin.barcode && $scope.checkin.backdate
                ) return false;
                return true;
            }
        }

        $scope.clear = function (xtype) {
            $scope[xtype] = {};
            if (xtype=="in_house_use") $scope[xtype].count = 1;
        }

        $scope.add = function (xtype,next_focus) {

            var barcode = $scope[xtype].barcode;
            if (barcode) {
                if ($scope.xact_page[xtype].filter(function(x){ return x.barcode == barcode }).length > 0) {
                    ngToast.warning(egCore.strings.DUPLICATE_BARCODE);
                    egCore.audio.play('warning.offline.duplicate_barcode');
                    $scope[xtype].barcode = '';
                    if (next_focus) $('#'+next_focus).focus();
                    return;
                }
            }

            var pbarcode = $scope[xtype].patron_barcode;
            if (pbarcode) {
                egLovefield.testOfflineBlock(pbarcode).then(function (blocked) {
                    if (blocked) {
                        egCore.audio.play('warning.offline.blocked_patron');
                        var default_format = 'mediumDate';
                        egCore.org.settings(['webstaff.format.dates']).then(function(set) {
                            if (set && set['format.date']) default_format = set['webstaff.format.dates'];
                            $scope.date_format = default_format;
                            var fBlockListDate = $scope.blockListDate ?
                                $filter('date')(($scope.blockListDate * 1000), $scope.date_format) :
                                null;
                            egConfirmDialog.open(
                                egCore.strings.PATRON_BLOCKED,
                                egCore.strings.PATRON_BLOCKED_WHY[blocked],
                                {formatted_date: fBlockListDate, pbarcode: pbarcode},
                                egCore.strings.ALLOW, 
                                egCore.strings.REJECT
                            ).result.then(
                                function(){ // forced
                                    $scope.blocked_patron = null;
                                    _add_impl(xtype,true)
                                    if (next_focus) $('#'+next_focus).focus();
                                },function(){ // stopped
                                    $scope.blocked_patron = xtype;
                                    if (next_focus) $('#'+next_focus).focus();
                                    return;
                                }
                            );
                        });
                    } else {
                        $scope.blocked_patron = null;
                        _add_impl(xtype,true)
                        if (next_focus) $('#'+next_focus).focus();
                    }
                });
            } else {
                _add_impl(xtype);
                if (next_focus) $('#'+next_focus).focus();
            }
        }

        function _add_impl (xtype,digest) {
            var pbarcode = $scope[xtype].patron_barcode;
            var backdate = $scope[xtype].backdate;

            if ($scope.strict_barcode && pbarcode) {
                if (!check_barcode(pbarcode)) {
                    $scope.bad_barcode = xtype;
                    egCore.audio.play('warning.offline.bad_barcode');
                    return egConfirmDialog.open(
                        egCore.strings.BAD_PATRON_BARCODE,
                        egCore.strings.BAD_PATRON_BARCODE_CD,
                        {}, egCore.strings.ALLOW, egCore.strings.REJECT
                    ).result.then(
                        function(){ // forced
                            $scope.blocked_patron = null;
                            return _add_impl2(xtype,digest)
                        },function(){ // stopped
                            $scope.blocked_patron = xtype;
                        }
                    );
                }
            }

            if ($scope.strict_barcode && $scope[xtype].barcode) {
                if (!check_barcode($scope[xtype].barcode)) {
                    $scope.bad_barcode = xtype;
                    egCore.audio.play('warning.offline.bad_barcode');
                    return egConfirmDialog.open(
                        egCore.strings.BAD_BARCODE,
                        egCore.strings.BAD_BARCODE_CD,
                        {}, egCore.strings.ALLOW, egCore.strings.REJECT
                    ).result.then(
                        function(){ // forced
                            $scope.blocked_patron = null;
                            return _add_impl2(xtype,digest)
                        },function(){ // stopped
                            $scope.blocked_patron = xtype;
                        }
                    );
                }
            }

            return _add_impl2(xtype,digest);
        }

        function _add_impl2 (xtype,digest) {
            var pbarcode = $scope[xtype].patron_barcode;
            var backdate = $scope[xtype].backdate;

            $scope.bad_barcode = null;

            var now = new Date().getTime();
            now = now / 1000;

            if ($scope[xtype].noncat_type) $scope[xtype].noncat = 1;

            if ($scope.shared.due_date && (xtype == 'checkout' || xtype == 'renew')) {
                $scope[xtype].due_date = $scope.shared.due_date.toISOString();
                $scope[xtype].checkout_time = new Date().toISOString();
            }

            var xact = { timestamp : parseInt(now), type : xtype, delta : 0 };

            $scope.xact_page[xtype].push(
                angular.extend(xact, $scope[xtype])
            );

            $scope.all_xact.push(xact)
            egUnloadPrompt.attach($rootScope);

            $scope[xtype] = {};

            if (pbarcode) $scope[xtype].patron_barcode = pbarcode;
            if (backdate) $scope[xtype].backdate = backdate;
            if (xtype=="in_house_use") $scope[xtype].count = 1;

            if (digest) $timeout(function(){$scope.$apply()});
        }

        check_barcode = function(bc) {
            if (bc != Number(bc)) return false;
            bc = bc.toString();
            // "16.00" == Number("16.00"), but the . is bad.
            // Throw out any barcode that isn't just digits
            if (bc.search(/\D/) != -1) return false;
            var last_digit = bc.substr(bc.length-1);
            var stripped_barcode = bc.substr(0,bc.length-1);
            return barcode_checkdigit(stripped_barcode).toString() == last_digit;
        }
    
        barcode_checkdigit = function(bc) {
            var reverse_barcode = bc.toString().split('').reverse();
            var check_sum = 0; var multiplier = 2;
            for (var i = 0; i < reverse_barcode.length; i++) {
                var digit = reverse_barcode[i];
                var product = digit * multiplier; product = product.toString();
                var temp_sum = 0;
                for (var j = 0; j < product.length; j++) {
                    temp_sum += Number( product[j] );
                }
                check_sum += Number( temp_sum );
                multiplier = ( multiplier == 2 ? 1 : 2 );
            }
            check_sum = check_sum.toString();
            var next_multiple_of_10 = (check_sum.match(/(\d*)\d$/)[1] * 10) + 10;
            var check_digit = next_multiple_of_10 - Number(check_sum);
            if (check_digit == 10) check_digit = 0;
            return check_digit;
        }

        function fetch_org_after_tree_exists () {
            $timeout(function(){
                try {
                    $scope.org = egCore.org.get($scope.current_workstation_owning_lib());
                } catch(e) {
                    fetch_org_after_tree_exists();
                }
            },100);
        }

        fetch_org_after_tree_exists();
    }
])

// dummy service so standalone patron editor can reference it
.factory('patronSvc', function() { return { /* dummy */ } })

.factory('patronRegSvc', ['$q', 'egCore', 'egLovefield', function($q, egCore, egLovefield) {

    egLovefield.isOffline = true;

    var service = {
        org : null,                // will come from workstation org 
        field_doc : {},            // config.idl_field_doc
        profiles : [],             // permission groups
        edit_profiles : [],        // perm groups we can modify
        sms_carriers : [],
        user_settings : {},        // applied user settings
        user_setting_types : {},   // config.usr_setting_type
        opt_in_setting_types : {}, // config.usr_setting_type for event-def opt-in
        surveys : [],
        survey_questions : {},
        survey_answers : {},
        survey_responses : {},     // survey.responses for loaded patron in progress
        stat_cats : [],
        stat_cat_entry_maps : {},   // cat.id to selected value
        virt_id : -1,               // virtual ID for new objects
        init_done : false           // have we loaded our initialization data?
    };

    service.offlineMode = function () {
        return lf.isOffline;
    }

    // launch a series of parallel data retrieval calls
    service.init = function(scope) {

        // Data loaded here only needs to be retrieved the first time this
        // tab becomes active within the current instance of the patron app.
        // In other words, navigating between patron tabs will not cause
        // all of this data to be reloaded.  Navigating to a separate app
        // and returning will cause the data to be reloaded.
        if (service.init_done) return $q.when();
        service.init_done = true;

        return $q.all([
            service.get_field_doc(),
            service.get_perm_groups(),
            service.get_ident_types(),
            service.get_user_settings(),
            service.get_org_settings(),
            service.get_stat_cats(),
            service.get_surveys(),
            service.get_net_access_levels()
        ]);
    };

    service.get_linked_addr_users = function(addrs) {
        return $q.when();
    }

    service.apply_secondary_groups = function(user_id, group_ids) {
        return $q.when(true);
    }

    // See note above about not loading egUser.
    // TODO: i18n
    service.format_name = function(last, first, middle) {
        return last + ', ' + first + (middle ? ' ' + middle : '');
    }

    service.check_dupe_username = function(usrname) {
        return $q.when(false);
    }

    // determine which user groups our user is not allowed to modify
    service.set_edit_profiles = function() {
        service.edit_profiles = egCore.env.pgt.list.filter(
            function (p) { return p.application_perm() == 'group_application.user.patron' }
        );
        return $q.when;
    }

    // resolves to a hash of perm-name => boolean value indicating
    // wether the user has the permission at org_id.
    service.has_perms_for_org = function(org_id) {

        var perms_needed = [
            'UPDATE_USER',
            'CREATE_USER',
            'CREATE_USER_GROUP_LINK', 
            'UPDATE_PATRON_COLLECTIONS_EXEMPT',
            'UPDATE_PATRON_CLAIM_RETURN_COUNT',
            'UPDATE_PATRON_CLAIM_NEVER_CHECKED_OUT_COUNT',
            'UPDATE_PATRON_ACTIVE_CARD',
            'UPDATE_PATRON_PRIMARY_CARD'
        ];

        var hash = {};
        angular.forEach(perms_needed, function (p) {
            hash[p] = true;
        });

        return $q.when(hash);
    }

    service.get_surveys = function() {
        return egLovefield.reconstituteList('asv').then(function(offline) {
            return egLovefield.reconstituteList('asvq')
                    .then(function(){
                        return egLovefield.reconstituteList('asva');
                    }).then(function() {
                        angular.forEach(egCore.env.asv.list, function (s) {
                            s.questions( egCore.env.asvq.list.filter( function (q) {
                                return q.survey().id == s.id();
                            }));
                        });

                        angular.forEach(egCore.env.asvq.list, function (q) {
                            q.survey( egCore.env.asv.map[ q.survey().id ] );
                            q.answers( egCore.env.asva.list.filter( function (a) {
                                return q.id() == a.question();
                            }));
                        });

                        angular.forEach(egCore.env.asva.list, function (a) {
                            a.question( egCore.env.asvq.map[ a.question().id ] );
                        });

                        service.surveys = egCore.env.asv.list;
                        service.survey_questions = egCore.env.asvq.list;
                        service.survey_answers = egCore.env.asva.list;

                        return $q.when();
                    });
        });
    }

    service.get_stat_cats = function() {
        return egLovefield.getStatCatsCache().then(
            function(cats) {
                service.stat_cats = cats;
                return $q.when();
            }
        );
    };

    service.get_org_settings = function() {
        return egLovefield.getSettingsCache().then(
            function (list) {
                var hash = {};
                angular.forEach(list, function (s) {
                    hash[s.name] = s.value;
                });
                service.org_settings = hash;
                if (egCore && egCore.env && !egCore.env.aous) {
                    egCore.env.aous = hash;
                    console.log('setting egCore.env.aous');
                }
                return $q.when();
            }
        );
    };

    service.get_ident_types = function() {
        return egLovefield.reconstituteList('cit').then(function() {
            service.ident_types = egCore.env.cit.list;
            return $q.when();
        });
    };

    service.get_net_access_levels = function() {
        return egLovefield.reconstituteList('cnal').then(function() {
            service.net_access_levels = egCore.env.cnal.list;
            return $q.when();
        });
    }

    service.get_perm_groups = function() {
        if (egCore.env.pgt) {
            service.profiles = egCore.env.pgt.list;
            return service.set_edit_profiles();
        } else {
            return egLovefield.reconstituteTree('pgt').then(function(offline) {
                service.profiles = egCore.env.pgt.list;
                return service.set_edit_profiles();
            });
        }
    }

    service.get_field_doc = function() {
        return egLovefield.getListFromOfflineCache('fdoc').then(function (list) {
            angular.forEach(list, function(doc) {
                if (!service.field_doc[doc.fm_class()])
                    service.field_doc[doc.fm_class()] = {};
                service.field_doc[doc.fm_class()][doc.field()] = doc;
            });
            return $q.when();
        });
    };

    service.get_user_settings = function() {
        var static_types = [
            'circ.holds_behind_desk', 
            'circ.collections.exempt', 
            'opac.hold_notify', 
            'opac.default_phone', 
            'opac.default_pickup_location', 
            'opac.default_sms_carrier', 
            'opac.default_sms_notify'];

        angular.forEach(static_types, function (t) {
            service.user_settings[t] = null;
        });

        return egLovefield.getListFromOfflineCache('cust').then(function (list) {
            angular.forEach(list, function(stype) {
                service.user_setting_types[stype.name()] = stype;
                if (static_types.indexOf(stype.name()) == -1) {
                    service.opt_in_setting_types[stype.name()] = stype;
                }
                if (stype.reg_default() != undefined) {
                    service.user_settings[stype.name()] = 
                        stype.reg_default();
                }
            });
            return $q.when();
        });
    }

    service.invalidate_field = function(patron, field) {
        return;
    }

    service.dupe_patron_search = function(patron, type, value) {
        return $q.when({ search : search, count : 0 });
    }

    service.init_patron = function(current) {

        if (!current)
            return service.init_new_patron();

        service.patron = current;
        return service.init_existing_patron(current)
    }

    service.ingest_address = function(patron, addr) {
        addr.valid = addr.valid == 't';
        addr.within_city_limits = addr.within_city_limits == 't';
        addr._is_mailing = (patron.mailing_address && 
            addr.id == patron.mailing_address.id);
        addr._is_billing = (patron.billing_address && 
            addr.id == patron.billing_address.id);
    }

    /*
     * Existing patron objects reqire some data munging before insertion
     * into the scope.
     *
     * 1. Turn everything into a hash
     * 2. ... Except certain fields (selectors) whose widgets require objects
     * 3. Bools must be Boolean, not t/f.
     */
    service.init_existing_patron = function(current) {

        service.existing_patron = current;

        var patron = egCore.idl.toHash(current);

        patron.home_ou = egCore.org.get(patron.home_ou.id);
        patron.expire_date = new Date(Date.parse(patron.expire_date));
        patron.dob = service.parse_dob(patron.dob);
        patron.profile = current.profile(); // pre-hash version
        patron.net_access_level = current.net_access_level();
        patron.ident_type = current.ident_type();
        patron.groups = current.groups(); // pre-hash

        angular.forEach(
            ['juvenile', 'barred', 'active', 'master_account'],
            function(field) { patron[field] = patron[field] == 't'; }
        );

        angular.forEach(patron.cards, function(card) {
            card.active = card.active == 't';
            if (card.id == patron.card.id) {
                patron.card = card;
                card._primary = 'on';
            }
        });

        angular.forEach(patron.addresses, 
            function(addr) { service.ingest_address(patron, addr) });

        service.get_linked_addr_users(patron.addresses);

        // Remove stat cat entries that link to out-of-scope stat
        // cats.  With this, we avoid unnecessarily updating (or worse,
        // modifying) stat cat values that are not ours to modify.
        patron.stat_cat_entries = patron.stat_cat_entries.filter(
            function(map) {
                return Boolean(
                    // service.stat_cats only contains in-scope stat cats.
                    service.stat_cats.filter(function(cat) { 
                        return (cat.id() == map.stat_cat.id) })[0]
                );
            }
        );

        // toss entries for existing stat cat maps into our living 
        // stat cat entry map, which is modified within the template.
        angular.forEach(patron.stat_cat_entries, function(map) {
            service.stat_cat_entry_maps[map.stat_cat.id] = map.stat_cat_entry;
        });

        return patron;
    }

    service.init_new_patron = function() {
        var addr = {
            id : service.virt_id--,
            isnew : true,
            valid : true,
            address_type : egCore.strings.REG_ADDR_TYPE,
            _is_mailing : true,
            _is_billing : true,
            within_city_limits : false,
            country : service.org_settings['ui.patron.default_country'],
        };

        var card = {
            id : service.virt_id--,
            isnew : true,
            active : true,
            _primary : 'on'
        };

        var home_ou = egCore.org.get(service.org);

        var user = {
            isnew : true,
            active : true,
            card : card,
            cards : [card],
            home_ou : home_ou,
            stat_cat_entries : [],
            groups : [],
            addresses : [addr]
        };

        if (service.clone_user)
            service.copy_clone_data(user);

        if (service.stage_user)
            service.copy_stage_data(user);

        return user;
    }

    // dob is always YYYY-MM-DD
    // Dates of birth do not contain timezone info, which can lead to
    // inconcistent timezone handling, potentially representing
    // different points in time, depending on the implementation.
    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/parse
    // See "Differences in assumed time zone"
    // TODO: move this into egDate ?
    service.parse_dob = function(dob) {
        if (!dob) return null;
        var parts = dob.split('-');
        var d = new Date(); // always local time zone, yay.
        d.setFullYear(parts[0]);
        d.setMonth(parts[1] - 1);
        d.setDate(parts[2]);
        return d;
    }

    service.copy_stage_data = function(user) {
        var cuser = service.stage_user;

        // copy the data into our new user object

        for (var key in egCore.idl.classes.stgu.field_map) {
            if (egCore.idl.classes.au.field_map[key] &&
                !egCore.idl.classes.stgu.field_map[key].virtual) {
                if (cuser.user[key]() !== null)
                    user[key] = cuser.user[key]();
            }
        }

        if (user.home_ou) user.home_ou = egCore.org.get(user.home_ou);
        if (user.profile) user.profile = egCore.env.pgt.map[user.profile];
        if (user.ident_type) 
            user.ident_type = egCore.env.cit.map[user.ident_type];
        user.dob = service.parse_dob(user.dob);

        // Clear the usrname if it looks like a UUID
        if (user.usrname.replace(/-/g,'').match(/[0-9a-f]{32}/)) 
            user.usrname = '';

        // Don't use stub address if we have one from the staged user.
        if (cuser.mailing_addresses.length || cuser.billing_addresses.length)
            user.addresses = [];

        // is_mailing=false implies is_billing
        function addr_from_stage(stage_addr) {
            if (!stage_addr) return;
            var cls = stage_addr.classname;

            var addr = {
                id : service.virt_id--,
                usr : user.id,
                isnew : true,
                valid : true,
                _is_mailing : cls == 'stgma',
                _is_billing : cls == 'stgba'
            };

            user.mailing_address = addr;
            user.addresses.push(addr);

            for (var key in egCore.idl.classes[cls].field_map) {
                if (egCore.idl.classes.aua.field_map[key] &&
                    !egCore.idl.classes[cls].field_map[key].virtual) {
                    if (stage_addr[key]() !== null)
                        addr[key] = stage_addr[key]();
                }
            }
        }

        addr_from_stage(cuser.mailing_addresses[0]);
        addr_from_stage(cuser.billing_addresses[0]);

        if (user.addresses.length == 1) {
            // If there is only one address, 
            // use it as both mailing and billing.
            var addr = user.addresses[0];
            addr._is_mailing = addr._is_billing = true;
            user.mailing_address = user.billing_address = addr;
        }

        if (cuser.cards.length) {
            user.card = {
                id : service.virt_id--,
                barcode : cuser.cards[0].barcode(),
                isnew : true,
                active : true,
                _primary : 'on'
            };

            user.cards.push(user.card);
            if (user.usrname == '') 
                user.usrname = card.barcode;
        }

        angular.forEach(cuser.settings, function(setting) {
            service.user_settings[setting.setting()] = Boolean(setting.value());
        });
    }

    // copy select values from the cloned user to the new user.
    // user is a hash
    service.copy_clone_data = function(user) {
        var clone_user = service.clone_user;

        // flesh the home org locally
        user.home_ou = egCore.org.get(clone_user.home_ou());
        if (user.profile) user.profile = egCore.env.pgt.map[user.profile];

        if (!clone_user.billing_address() &&
            !clone_user.mailing_address())
            return; // no addresses to copy or link

        // if the cloned user has any addresses, we don't need 
        // the stub address created in init_new_patron.
        user.addresses = [];

        var copy_addresses = 
            service.org_settings['circ.patron_edit.clone.copy_address'];

        var clone_fields = [
            'day_phone',
            'evening_phone',
            'other_phone',
            'usrgroup'
        ]; 

        angular.forEach(clone_fields, function(field) {
            user[field] = clone_user[field]();
        });

        if (copy_addresses) {
            var bill_addr, mail_addr;

            // copy the billing and mailing addresses into new addresses
            function clone_addr(addr) {
                var new_addr = egCore.idl.toHash(addr);
                new_addr.id = service.virt_id--;
                new_addr.usr = user.id;
                new_addr.isnew = true;
                new_addr.valid = true;
                user.addresses.push(new_addr);
                return new_addr;
            }

            if (bill_addr = clone_user.billing_address()) {
                var addr = clone_addr(bill_addr);
                addr._is_billing = true;
                user.billing_address = addr;
            }

            if (mail_addr = clone_user.mailing_address()) {

                if (bill_addr && bill_addr.id() == mail_addr.id()) {
                    user.mailing_address = user.billing_address;
                    user.mailing_address._is_mailing = true;
                } else {
                    var addr = clone_addr(mail_addr);
                    addr._is_mailing = true;
                    user.mailing_address = addr;
                }

                if (!bill_addr) {
                    // if there is no billing addr, use the mailing addr
                    user.billing_address = user.mailing_address;
                    user.billing_address._is_billing = true;
                }
            }


        } else {

            // link the billing and mailing addresses
            var addr;
            if (addr = clone_user.billing_address()) {
                user.billing_address = egCore.idl.toHash(addr);
                user.billing_address._is_billing = true;
                user.addresses.push(user.billing_address);
                user.billing_address._linked_owner_id = clone_user.id();
                user.billing_address._linked_owner = service.format_name(
                    clone_user.family_name(),
                    clone_user.first_given_name(),
                    clone_user.second_given_name()
                );
            }

            if (addr = clone_user.mailing_address()) {
                if (user.billing_address && 
                    addr.id() == user.billing_address.id) {
                    // mailing matches billing
                    user.mailing_address = user.billing_address;
                    user.mailing_address._is_mailing = true;
                } else {
                    user.mailing_address = egCore.idl.toHash(addr);
                    user.mailing_address._is_mailing = true;
                    user.addresses.push(user.mailing_address);
                    user.mailing_address._linked_owner_id = clone_user.id();
                    user.mailing_address._linked_owner = service.format_name(
                        clone_user.family_name(),
                        clone_user.first_given_name(),
                        clone_user.second_given_name()
                    );
                }
            }
        }
    }

    // translate the patron back into IDL form
    service.save_user = function(phash) {

        var patron = egCore.idl.fromHash('au', phash);

        patron.home_ou(patron.home_ou().id());
        patron.expire_date(patron.expire_date().toISOString());
        patron.profile(patron.profile().id());
        if (patron.dob()) 
            patron.dob(patron.dob().toISOString().replace(/T.*/,''));
        if (patron.ident_type()) 
            patron.ident_type(patron.ident_type().id());
        if (patron.net_access_level())
            patron.net_access_level(patron.net_access_level().id());

        angular.forEach(
            ['juvenile', 'barred', 'active', 'master_account'],
            function(field) { patron[field](phash[field] ? 't' : 'f'); }
        );

        var card_hashes = patron.cards();
        patron.cards([]);
        angular.forEach(card_hashes, function(chash) {
            var card = egCore.idl.fromHash('ac', chash)
            card.usr(patron.id());
            card.active(chash.active ? 't' : 'f');
            patron.cards().push(card);
            if (chash._primary) {
                patron.card(card);
            }
        });

        var addr_hashes = patron.addresses();
        patron.addresses([]);
        angular.forEach(addr_hashes, function(addr_hash) {
            if (!addr_hash.isnew && !addr_hash.isdeleted) 
                addr_hash.ischanged = true;
            var addr = egCore.idl.fromHash('aua', addr_hash);
            patron.addresses().push(addr);
            addr.valid(addr.valid() ? 't' : 'f');
            addr.within_city_limits(addr.within_city_limits() ? 't' : 'f');
            if (addr_hash._is_mailing) patron.mailing_address(addr);
            if (addr_hash._is_billing) patron.billing_address(addr);
        });

        patron.survey_responses([]);
        angular.forEach(service.survey_responses, function(answer) {
            var question = service.survey_questions[answer.question()];
            var resp = new egCore.idl.asvr();
            resp.isnew(true);
            resp.survey(question.survey());
            resp.question(question.id());
            resp.answer(answer.id());
            resp.usr(patron.id());
            resp.answer_date('now');
            patron.survey_responses().push(resp);
        });
        
        // re-object-ify the patron stat cat entry maps
        var maps = [];
        angular.forEach(patron.stat_cat_entries(), function(entry) {
            var e = egCore.idl.fromHash('actscecm', entry);
            e.stat_cat(e.stat_cat().id);
            maps.push(e);
        });
        patron.stat_cat_entries(maps);

        // service.stat_cat_entry_maps maps stats to values
        // patron.stat_cat_entries is an array of stat_cat_entry_usr_map's
        angular.forEach(
            service.stat_cat_entry_maps, function(value, cat_id) {

            // see if we already have a mapping for this entry
            var existing = patron.stat_cat_entries().filter(
                function(e) { return e.stat_cat() == cat_id })[0];

            if (existing) { // we have a mapping
                // if the existing mapping matches the new one,
                // there' nothing left to do
                if (existing.stat_cat_entry() == value) return;

                // mappings differ.  delete the old one and create
                // a new one below.
                existing.isdeleted(true);
            }

            var newmap = new egCore.idl.actscecm();
            newmap.target_usr(patron.id());
            newmap.isnew(true);
            newmap.stat_cat(cat_id);
            newmap.stat_cat_entry(value);
            patron.stat_cat_entries().push(newmap);
        });

        if (!patron.isnew()) patron.ischanged(true);

        return egLovefield.addOfflineXact({
            user        : egCore.idl.toHash(patron),
            timestamp   : parseInt(new Date().getTime() / 1000),
            type        : 'register',
            delta       : 0
        }).then(function (success) {
            if (success) return patron;
        });
    }

    service.remove_staged_user = function() {
        if (!service.stage_user) return $q.when();
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.stage.delete',
            egCore.auth.token(),
            service.stage_user.user.row_id()
        );
    }

    service.save_user_settings = function(new_user, user_settings) {
        return;
    }

    // Applies field-specific validation regex's from org settings 
    // to form fields.  Be careful not remove any pattern data we
    // are not explicitly over-writing in the provided patterns obj.
    service.set_field_patterns = function(patterns) {
        if (service.org_settings['opac.username_regex']) {
            patterns.au.usrname = 
                new RegExp(service.org_settings['opac.username_regex']);
        }

        if (service.org_settings['opac.barcode_regex']) {
            patterns.ac.barcode = 
                new RegExp(service.org_settings['opac.barcode_regex']);
        }

        if (service.org_settings['global.password_regex']) {
            patterns.au.passwd = 
                new RegExp(service.org_settings['global.password_regex']);
        }

        var phone_reg = service.org_settings['ui.patron.edit.phone.regex'];
        if (phone_reg) {
            // apply generic phone regex first, replace below as needed.
            patterns.au.day_phone = new RegExp(phone_reg);
            patterns.au.evening_phone = new RegExp(phone_reg);
            patterns.au.other_phone = new RegExp(phone_reg);
        }

        // the remaining patterns fit a well-known key name pattern

        angular.forEach(service.org_settings, function(val, key) {
            if (!val) return;
            var parts = key.match(/ui.patron.edit\.(\w+)\.(\w+)\.regex/);
            if (!parts) return;
            var cls = parts[1];
            var name = parts[2];
            patterns[cls][name] = new RegExp(val);
        });
    }

    return service;
}])

.controller('PatronRegCtrl',
       ['$scope','$routeParams','$q','$uibModal','$window','egCore',
        'patronSvc','patronRegSvc','egUnloadPrompt','egAlertDialog',
        'egWorkLog','$timeout','egLovefield','$rootScope',
function($scope , $routeParams , $q , $uibModal , $window , egCore ,
         patronSvc , patronRegSvc , egUnloadPrompt, egAlertDialog ,
         egWorkLog , $timeout , egLovefield , $rootScope) {

    $scope.rs = $rootScope;
    if ($scope.workstation_obj) patronRegSvc.org = $scope.workstation_obj.owning_lib;
    $scope.offline = true;

    $scope.page_data_loaded = false;
    $scope.clone_id = patronRegSvc.clone_id = $routeParams.clone_id;
    $scope.stage_username = 
        patronRegSvc.stage_username = $routeParams.stage_username;
    $scope.patron_id = 
        patronRegSvc.patron_id = $routeParams.edit_id || $routeParams.id;

    // for existing patrons, disable barcode input by default
    $scope.disable_bc = $scope.focus_usrname = Boolean($scope.patron_id);
    $scope.focus_bc = !Boolean($scope.patron_id);
    $scope.address_alerts = [];
    $scope.dupe_counts = {};

    // map of perm name to true/false for perms the logged in user
    // has at the currently selected patron home org unit.
    $scope.perms = {};

    $scope.edit_passthru = {};

    // 0=all, 1=suggested, 2=required
    $scope.edit_passthru.vis_level = 2;
    $scope.name_tab = 'primary';

    // Apply default values for new patrons during initial registration
    // prs is shorthand for patronSvc
    function set_new_patron_defaults(prs) {
        if (!$scope.patron.passwd) {
            // passsword may originate from staged user.
            $scope.generate_password();
        }
        $scope.hold_notify_phone = true;
        $scope.hold_notify_email = true;

        // staged users may be loaded w/ a profile.
        $scope.set_expire_date();

        if (prs.org_settings['ui.patron.default_ident_type']) {
            // $scope.patron needs this field to be an object
            var id = prs.org_settings['ui.patron.default_ident_type'];
            var ident_type = $scope.ident_types.filter(
                function(type) { return type.id() == id })[0];
            $scope.patron.ident_type = ident_type;
        }
        if (prs.org_settings['ui.patron.default_inet_access_level']) {
            // $scope.patron needs this field to be an object
            var id = prs.org_settings['ui.patron.default_inet_access_level'];
            var level = $scope.net_access_levels.filter(
                function(lvl) { return lvl.id() == id })[0];
            $scope.patron.net_access_level = level;
        }
        if (prs.org_settings['ui.patron.default_country']) {
            $scope.patron.addresses[0].country = 
                prs.org_settings['ui.patron.default_country'];
        }
    }

    // A null or undefined pattern leads to exceptions.  Before the
    // patterns are loaded from the server, default all patterns
    // to an innocuous regex.  To avoid re-creating numerous
    // RegExp objects, cache the stub RegExp after initial creation.
    // note: angular docs say ng-pattern accepts a regexp or string,
    // but as of writing, it only works with a regexp object.
    // (Likely an angular 1.2 vs. 1.4 issue).
    var field_patterns = {au : {}, ac : {}, aua : {}};
    $scope.field_pattern = function(cls, field) { 
        if (!field_patterns[cls][field])
            field_patterns[cls][field] = new RegExp('.*');
        return field_patterns[cls][field];
    }

    patronRegSvc.offlineMode($scope.offline); // force offline if ng-init'd to do so
    patronRegSvc.init().then(function() {
        // called after initTab and patronRegSvc.init have completed
    
        var prs = patronRegSvc; // brevity
        // in standalone mode, we have no patronSvc
        $scope.patron = prs.init_patron(patronSvc ? patronSvc.current : null);
        $scope.field_doc = prs.field_doc;
        $scope.edit_profiles = prs.edit_profiles;
        $scope.ident_types = prs.ident_types;
        $scope.net_access_levels = prs.net_access_levels;
        $scope.user_setting_types = prs.user_setting_types;
        $scope.opt_in_setting_types = prs.opt_in_setting_types;
        $scope.org_settings = prs.org_settings;
        $scope.sms_carriers = prs.sms_carriers;
        $scope.stat_cats = prs.stat_cats;
        $scope.surveys = prs.surveys;
        $scope.survey_responses = prs.survey_responses;
        $scope.stat_cat_entry_maps = prs.stat_cat_entry_maps;
        $scope.stage_user = prs.stage_user;
        $scope.stage_user_requestor = prs.stage_user_requestor;
    
        $scope.user_settings = prs.user_settings;
        // clone the user settings back into the patronRegSvc so
        // we have a copy of the original state of the settings.
        prs.user_settings = {};
        angular.forEach($scope.user_settings, function(val, key) {
            prs.user_settings[key] = val;
        });
    
        extract_hold_notify();
        $scope.handle_home_org_changed();
    
        if ($scope.org_settings['ui.patron.edit.default_suggested'])
            $scope.edit_passthru.vis_level = 1;
    
        if ($scope.patron.isnew) 
            set_new_patron_defaults(prs);
    
        $scope.page_data_loaded = true;
    
        prs.set_field_patterns(field_patterns);
        apply_username_regex();
    });

    // update the currently displayed field documentation
    $scope.set_selected_field_doc = function(cls, field) {
        $scope.selected_field_doc = $scope.field_doc[cls][field];
    }

    // returns the tree depth of the selected profile group tree node.
    $scope.pgt_depth = function(grp) {
        var d = 0;
        while (grp = egCore.env.pgt.map[grp.parent()]) d++;
        return d;
    }

    // IDL fields used for labels in the UI.
    $scope.idl_fields = {
        au  : egCore.idl.classes.au.field_map,
        ac  : egCore.idl.classes.ac.field_map,
        aua : egCore.idl.classes.aua.field_map
    };

    // field visibility cache.  Some fields are universally required.
    // 3 == value universally required
    // 2 == field is visible by default
    // 1 == field is suggested by default
    var field_visibility = {};
    var default_field_visibility = {
        'ac.barcode' : 3,
        'au.usrname' : 3,
        'au.passwd' :  3,
        'au.first_given_name' : 3,
        'au.family_name' : 3,
        'au.pref_first_given_name' : 2,
        'au.ident_type' : 3,
        'au.home_ou' : 3,
        'au.profile' : 3,
        'au.expire_date' : 3,
        'au.net_access_level' : 3,
        'aua.address_type' : 3,
        'aua.post_code' : 3,
        'aua.street1' : 3,
        'aua.street2' : 2,
        'aua.city' : 3,
        'aua.county' : 2,
        'aua.state' : 2,
        'aua.country' : 3,
        'aua.valid' : 2,
        'aua.within_city_limits' : 2,
        'stat_cats' : 1,
        'surveys' : 1
    }; 

    // Returns true if the selected field should be visible
    // given the current required/suggested/all setting.
    // The visibility flag applied to each field as a result of calling
    // this function also sets (via the same flag) the requiredness state.
    $scope.show_field = function(field_key) {
        // org settings have not been received yet.
        if (!$scope.org_settings) return false;

        if (field_visibility[field_key] == undefined) {
            // compile and cache the visibility for the selected field

            var req_set = 'ui.patron.edit.' + field_key + '.require';
            var sho_set = 'ui.patron.edit.' + field_key + '.show';
            var sug_set = 'ui.patron.edit.' + field_key + '.suggest';

            if ($scope.org_settings[req_set]) {
                field_visibility[field_key] = 3;

            } else if ($scope.org_settings[sho_set]) {
                field_visibility[field_key] = 2;

            } else if ($scope.org_settings[sug_set]) {
                field_visibility[field_key] = 1;
            }
        }

        if (field_visibility[field_key] == undefined) {
            // No org settings were applied above.  Use the default
            // settings if present or assume the field has no
            // visibility flags applied.
            field_visibility[field_key] = 
                default_field_visibility[field_key] || 0;
        }

        return field_visibility[field_key] >= $scope.edit_passthru.vis_level;
    }

    // See $scope.show_field().
    // A field with visbility level 3 means it's required.
    $scope.field_required = function(cls, field) {

        // Value in the password field is not required
        // for existing patrons.
        if (field == 'passwd' && $scope.patron && !$scope.patron.isnew) 
          return false;

        return (field_visibility[cls + '.' + field] == 3 || default_field_visibility[cls + '.' + field] == 3);
    }

    // generates a random 4-digit password
    $scope.generate_password = function() {
        $scope.patron.passwd = Math.floor(Math.random()*9000) + 1000;
    }

    $scope.set_expire_date = function() {
        if (!$scope.patron.profile) return;
        var seconds = egCore.date.intervalToSeconds(
            $scope.patron.profile.perm_interval());
        var now_epoch = new Date().getTime();
        $scope.patron.expire_date = new Date(
            now_epoch + (seconds * 1000 /* milliseconds */))
    }

    // grp is the pgt object
    $scope.set_profile = function(grp) {
        $scope.patron.profile = grp;
        $scope.set_expire_date();
        $scope.field_modified();
    }

    $scope.invalid_profile = function() {
        return !(
            $scope.patron && 
            $scope.patron.profile && 
            $scope.patron.profile.usergroup() == 't'
        );
    }

    $scope.new_address = function() {
        var addr = egCore.idl.toHash(new egCore.idl.aua());
        patronRegSvc.ingest_address($scope.patron, addr);
        addr.id = patronRegSvc.virt_id--;
        addr.isnew = true;
        addr.valid = true;
        addr.within_city_limits = true;
        addr.country = $scope.org_settings['ui.patron.default_country'];
        $scope.patron.addresses.push(addr);
    }

    // keep deleted addresses out of the patron object so
    // they won't appear in the UI.  They'll be re-inserted
    // when the patron is updated.
    deleted_addresses = [];
    $scope.delete_address = function(id) {

        if ($scope.patron.isnew &&
            $scope.patron.addresses.length == 1 &&
            $scope.org_settings['ui.patron.registration.require_address']) {
            egAlertDialog.open(egCore.strings.REG_ADDR_REQUIRED);
            return;
        }

        var addresses = [];
        angular.forEach($scope.patron.addresses, function(addr) {
            if (addr.id == id) {
                if (id > 0) {
                    addr.isdeleted = true;
                    deleted_addresses.push(addr);
                }
            } else {
                addresses.push(addr);
            }
        });
        $scope.patron.addresses = addresses;
    } 

    $scope.post_code_changed = function(addr) { 
        if ($scope.offline) return;
        egCore.net.request(
            'open-ils.search', 'open-ils.search.zip', addr.post_code)
        .then(function(resp) {
            if (!resp) return;
            if (resp.city) addr.city = resp.city;
            if (resp.state) addr.state = resp.state;
            if (resp.county) addr.county = resp.county;
            if (resp.alert) alert(resp.alert);
        });
    }

    $scope.replace_card = function() {
        $scope.patron.card.active = false;
        $scope.patron.card.ischanged = true;
        $scope.disable_bc = false;

        var new_card = egCore.idl.toHash(new egCore.idl.ac());
        new_card.id = patronRegSvc.virt_id--;
        new_card.isnew = true;
        new_card.active = true;
        new_card._primary = 'on';
        $scope.patron.card = new_card;
        $scope.patron.cards.push(new_card);
    }

    $scope.day_phone_changed = function(phone) {
        if (phone && $scope.patron.isnew && 
            $scope.org_settings['patron.password.use_phone']) {
            $scope.patron.passwd = phone.substr(-4);
        }
    }

    $scope.barcode_changed = function(bc) {
        if (!bc) return;
        if (!$scope.patron.usrname)
            $scope.patron.usrname = bc;
    }

    $scope.cards_dialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/t_patron_cards_dialog',
            backdrop: 'static',
            controller: 
                   ['$scope','$uibModalInstance','cards','perms',
            function($scope , $uibModalInstance , cards , perms) {
                // scope here is the modal-level scope
                $scope.args = {cards : cards};
                $scope.perms = perms;
                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }],
            resolve : {
                cards : function() {
                    // scope here is the controller-level scope
                    return $scope.patron.cards;
                },
                perms : function() {
                    return $scope.perms;
                }
            }
        }).result.then(
            function(args) {
                angular.forEach(args.cards, function(card) {
                    card.ischanged = true; // assume cards need updating, OK?
                    if (card._primary == 'on' && 
                        card.id != $scope.patron.card.id) {
                        $scope.patron.card = card;
                    }
                });
            }
        );
    }

    $scope.set_addr_type = function(addr, type) {
        var addrs = $scope.patron.addresses;
        if (addr['_is_'+type]) {
            angular.forEach(addrs, function(a) {
                if (a.id != addr.id) a['_is_'+type] = false;
            });
        } else {
            // unchecking mailing/billing means we have to randomly
            // select another address to fill that role.  Select the
            // first address in the list (that does not match the
            // modifed address)
            for (var i = 0; i < addrs.length; i++) {
                if (addrs[i].id != addr.id) {
                    addrs[i]['_is_' + type] = true;
                    break;
                }
            }
        }
    }


    // Translate hold notify preferences from the form/scope back into a 
    // single user setting value for opac.hold_notify.
    function compress_hold_notify() {
        var hold_notify = '';
        var splitter = '';
        if ($scope.hold_notify_phone) {
            hold_notify = 'phone';
            splitter = ':';
        }
        if ($scope.hold_notify_email) {
            hold_notify = splitter + 'email';
            splitter = ':';
        }
        if ($scope.hold_notify_sms) {
            hold_notify = splitter + 'sms';
            splitter = ':';
        }
        $scope.user_settings['opac.hold_notify'] = hold_notify;
    }

    // dialog for selecting additional permission groups
    $scope.secondary_groups_dialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/t_patron_groups_dialog',
            backdrop: 'static',
            controller: 
                   ['$scope','$uibModalInstance','linked_groups','pgt_depth',
            function($scope , $uibModalInstance , linked_groups , pgt_depth) {

                $scope.pgt_depth = pgt_depth;
                $scope.args = {
                    linked_groups : linked_groups,
                    edit_profiles : patronRegSvc.edit_profiles,
                    new_profile   : patronRegSvc.edit_profiles[0]
                };

                // add a new group to the linked groups list
                $scope.link_group = function($event, grp) {
                    var found = false; // avoid duplicates
                    angular.forEach($scope.args.linked_groups, 
                        function(g) {if (g.id() == grp.id()) found = true});
                    if (!found) $scope.args.linked_groups.push(grp);
                    $event.preventDefault(); // avoid close
                }

                // remove a group from the linked groups list
                $scope.unlink_group = function($event, grp) {
                    $scope.args.linked_groups = 
                        $scope.args.linked_groups.filter(function(g) {
                        return g.id() != grp.id()
                    });
                    $event.preventDefault(); // avoid close
                }

                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }],
            resolve : {
                linked_groups : function() { return $scope.patron.groups },
                pgt_depth : function() { return $scope.pgt_depth }
            }
        }).result.then(
            function(args) {

                if ($scope.patron.isnew) {
                    // groups must be linked for new patrons after the
                    // patron is created.
                    $scope.patron.groups = args.linked_groups;
                    return;
                }

                // update links groups for existing users in real time.
                var ids = args.linked_groups.map(function(g) {return g.id()});
                patronRegSvc.apply_secondary_groups($scope.patron.id, ids)
                .then(function(success) {
                    if (success)
                        $scope.patron.groups = args.linked_groups;
                });
            }
        );
    }

    function extract_hold_notify() {
        notify = $scope.user_settings['opac.hold_notify'];
        if (!notify) return;
        $scope.hold_notify_phone = Boolean(notify.match(/phone/));
        $scope.hold_notify_email = Boolean(notify.match(/email/));
        $scope.hold_notify_sms = Boolean(notify.match(/sms/));
    }

    $scope.invalidate_field = function(field) {
        patronRegSvc.invalidate_field($scope.patron, field);
    }

    address_alert = function(addr) {
        if ($scope.offline) return;
        var args = {
            street1: addr.street1,
            street2: addr.street2,
            city: addr.city,
            state: addr.state,
            county: addr.county,
            country: addr.country,
            post_code: addr.post_code,
            mailing_address: addr._is_mailing,
            billing_address: addr._is_billing
        }

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.address_alert.test',
            egCore.auth.token(), egCore.auth.user().ws_ou(), args
            ).then(function(res) {
                $scope.address_alerts = res;
        });
    }

    $scope.dupe_value_changed = function(type, value) {
        $scope.dupe_counts[type] = 0;
        patronRegSvc.dupe_patron_search($scope.patron, type, value)
        .then(function(res) {
            $scope.dupe_counts[type] = res.count;
            if (res.count) {
                $scope.dupe_search_encoded = 
                    encodeURIComponent(js2JSON(res.search));
            } else {
                $scope.dupe_search_encoded = '';
            }
        });
    }

    // Dummy function in offline mode
    $scope.handle_home_org_changed = function() {}

    // This is called with every character typed in a form field,
    // since that's the only way to gaurantee something has changed.
    // See handle_field_changed for ng-change vs. ng-blur.
    $scope.field_modified = function() {
        // Call attach with every field change, regardless of whether
        // it's been called before.  This will allow for re-attach after
        // the user clicks through the unload warning. egUnloadPrompt
        // will ensure we only attach once.
        egUnloadPrompt.attach($rootScope);
    }

    // also monitor when form is changed *by the user*, as using
    // an ng-change handler doesn't work with eg-date-input
    $scope.$watch('reg_form.$pristine', function(newVal, oldVal) {
        if (!newVal) egUnloadPrompt.attach($rootScope);
    });

    // username regex (if present) must be removed any time
    // the username matches the barcode to avoid firing the
    // invalid field handlers.
    function apply_username_regex() {
        var regex = $scope.org_settings['opac.username_regex'];
        if (regex) {
            if ($scope.patron.card.barcode) {
                // username must match the regex or the barcode
                field_patterns.au.usrname = 
                    new RegExp(
                        regex + '|^' + $scope.patron.card.barcode + '$');
            } else {
                // username must match the regex
                field_patterns.au.usrname = new RegExp(regex);
            }
        } else {
            // username can be any format.
            field_patterns.au.usrname = new RegExp('.*');
        }
    }

    // obj could be the patron, an address, etc.
    // This is called any time a form field achieves then loses focus.
    // It does not necessarily mean the field has changed.
    // The alternative is ng-change, but it's called with each character
    // typed, which would be overkill for many of the actions called here.
    $scope.handle_field_changed = function(obj, field_name) {
        if (!obj) return;

        var cls = obj.classname; // set by egIdl
        var value = obj[field_name];

        // Hush!
        //console.log('changing field ' + field_name + ' to ' + value);

        switch (field_name) {
            case 'day_phone' : 
                if ($scope.patron.day_phone && 
                    $scope.patron.isnew && 
                    $scope.org_settings['patron.password.use_phone']) {
                    $scope.patron.passwd = phone.substr(-4);
                }
                break;

            case 'barcode':
                apply_username_regex();
                $scope.barcode_changed(value);
                break;

            case 'dob':
                maintain_juvenile_flag();
                break;

            default:
                break;
        }
    }

    // patron.juvenile is set to true if the user was born after
    function maintain_juvenile_flag() {
        if ( !($scope.patron && $scope.patron.dob) ) return;

        var juv_interval = 
            $scope.org_settings['global.juvenile_age_threshold'] 
            || '18 years';

        var base = new Date();

        base.setTime(base.getTime() - 
            Number(egCore.date.intervalToSeconds(juv_interval) + '000'));

        $scope.patron.juvenile = ($scope.patron.dob > base);
    }

    // returns true (disable) for orgs that cannot have users.
    $scope.disable_home_org = function(org_id) {
        if (!org_id) return;
        var org = egCore.org.get(org_id);
        return (
            org &&
            org.ou_type() &&
            org.ou_type().can_have_users() == 'f'
        );
    }

    $scope.edit_passthru.self_edit_disallowed = function() {
        return false;
    }

    $scope.edit_passthru.group_edit_disallowed = function() {
        return false;
    }

    // Returns true if the Save and Save & Clone buttons should be disabled.
    $scope.edit_passthru.hide_save_actions = function() {
        return false;
    }

    // Returns true if any input elements are tagged as invalid
    // via Angular patterns or required attributes.
    function form_has_invalid_fields() {
        return $('#patron-reg-container .ng-invalid').length > 0;
    }

    function form_is_incomplete() {
        return (
            $scope.dupe_username ||
            $scope.dupe_barcode ||
            form_has_invalid_fields()
        );

    }

    $scope.edit_passthru.save = function(save_args) {
        if (!save_args) save_args = {};

        if (form_is_incomplete()) {
            // User has not provided valid values for all required fields.
            return egAlertDialog.open(egCore.strings.REG_INVALID_FIELDS);
        }

        // remove page unload warning prompt
        egUnloadPrompt.clear();

        // toss the deleted addresses back into the patron's list of
        // addresses so it's included in the update
        $scope.patron.addresses = 
            $scope.patron.addresses.concat(deleted_addresses);
        
        compress_hold_notify();

        var updated_user;

        patronRegSvc.save_user($scope.patron)
        .then($scope.rs.save_offline_xacts)
        .then(function(new_user) { 
            // reload the current page
            $window.location.href = location.href;
        });
    }
}])
