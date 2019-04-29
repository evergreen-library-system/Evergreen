/**
 * Patron App
 *
 * Search, checkout, items out, holds, bills, edit, etc.
 */

angular.module('egPatronApp', ['ngRoute', 'ui.bootstrap', 'egUserBucketMod', 
    'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod', 'ngToast',
    'egPatronSearchMod'])

.config(['ngToastProvider', function(ngToastProvider) {
    ngToastProvider.configure({
        verticalPosition: 'bottom',
        animation: 'fade'
    });
}])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    // data loaded at startup which only requires an authtoken goes
    // here. this allows the requests to be run in parallel instead of
    // waiting until startup has completed.
    var resolver = {delay : ['egCore','egUser', function(egCore , egUser) {

        // fetch the org settings we care about during egStartup
        // and toss them into egCore.env as egCore.env.aous[name] = value.
        // note: only load settings here needed by all tabs; load tab-
        // specific settings from within their respective controllers
        egCore.env.classLoaders.aous = function() {
            return egCore.org.settings([
                'ui.staff.require_initials.patron_info_notes',
                'circ.do_not_tally_claims_returned',
                'circ.tally_lost',
                'circ.obscure_dob',
                'ui.circ.show_billing_tab_on_bills',
                'circ.patron_expires_soon_warning',
                'ui.circ.items_out.lost',
                'ui.circ.items_out.longoverdue',
                'ui.circ.items_out.claimsreturned'
            ]).then(function(settings) { 
                // local settings are cached within egOrg.  Caching them
                // again in egEnv just simplifies the syntax for access.
                egCore.env.aous = settings;
            });
        }

        egCore.env.loadClasses.push('aous');

        // app-globally modify the default flesh fields for 
        // fleshed user retrieval.
        if (egUser.defaultFleshFields.indexOf('profile') == -1) {
            egUser.defaultFleshFields = egUser.defaultFleshFields.concat([
                'profile',
                'net_access_level',
                'ident_type',
                'ident_type2',
                'cards',
                'groups'
            ]);
        }

        return egCore.startup.go();
    }]};

    $routeProvider.when('/circ/patron/search', {
        templateUrl: './circ/patron/t_search',
        controller: 'PatronSearchCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/bcsearch', {
        templateUrl: './circ/patron/t_bcsearch',
        controller: 'PatronBarcodeSearchCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/credentials', {
        templateUrl: './circ/patron/t_credentials',
        controller: 'PatronVerifyCredentialsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/last', {
        templateUrl: './circ/patron/t_last_patron',
        controller: 'PatronFetchLastCtrl',
        resolve : resolver
    });

    // the following require a patron ID

    $routeProvider.when('/circ/patron/:id/alerts', {
        templateUrl: './circ/patron/t_alerts',
        controller: 'PatronAlertsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/checkout', {
        templateUrl: './circ/patron/t_checkout',
        controller: 'PatronCheckoutCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/items_out', {
        templateUrl: './circ/patron/t_items_out',
        controller: 'PatronItemsOutCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/holds', {
        templateUrl: './circ/patron/t_holds',
        controller: 'PatronHoldsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/holds/create', {
        templateUrl: './circ/patron/t_holds_create',
        controller: 'PatronHoldsCreateCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/holds/:hold_id', {
        templateUrl: './circ/patron/t_holds',
        controller: 'PatronHoldsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/hold/:hold_id', {
        templateUrl: './circ/patron/t_hold_details',
        controller: 'PatronHoldDetailsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/bills', {
        templateUrl: './circ/patron/t_bills',
        controller: 'PatronBillsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/bill/:xact_id/:xact_tab', {
        templateUrl: './circ/patron/t_xact_details',
        controller: 'XactDetailsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/bill_history/:history_tab', {
        templateUrl: './circ/patron/t_bill_history',
        controller: 'BillHistoryCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/messages', {
        templateUrl: './circ/patron/t_messages',
        controller: 'PatronMessagesCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/edit', {
        templateUrl: './circ/patron/t_edit',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/credentials', {
        templateUrl: './circ/patron/t_credentials',
        controller: 'PatronVerifyCredentialsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/notes', {
        templateUrl: './circ/patron/t_notes',
        controller: 'PatronNotesCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/triggered_events', {
        templateUrl: './circ/patron/t_triggered_events',
        controller: 'PatronTriggeredEventsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/message_center', {
        templateUrl: './circ/patron/t_message_center',
        controller: 'PatronMessageCenterCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/edit_perms', {
        templateUrl: './circ/patron/t_edit_perms',
        controller: 'PatronPermsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/group', {
        templateUrl: './circ/patron/t_group',
        controller: 'PatronGroupCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/stat_cats', {
        templateUrl: './circ/patron/t_stat_cats',
        controller: 'PatronStatCatsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/:id/surveys', {
        templateUrl: './circ/patron/t_surveys',
        controller: 'PatronSurveyCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/circ/patron/search'});
})

/**
 * Manages tabbed patron view.
 * This is the parent scope of all patron tab scopes.
 *
 * */
.controller('PatronCtrl',
       ['$scope','$q','$location','$filter','egCore','egNet','egUser','egAlertDialog','egConfirmDialog','egPromptDialog','patronSvc',
function($scope,  $q , $location , $filter , egCore , egNet , egUser , egAlertDialog , egConfirmDialog , egPromptDialog , patronSvc) {

    $scope.is_patron_edit = function() {
        return Boolean($location.path().match(/patron\/\d+\/edit$/));
    }

    // To support the fixed position patron edit actions bar,
    // its markup has to live outside the scope of the patron 
    // edit controller.  Insert a scope blob here that can be
    // modifed from within the patron edit controller.
    $scope.edit_passthru = {};

    // returns true if a redirect occurs
    function redirectToAlertPanel() {

        $scope.alert_penalties = 
            function() {return patronSvc.alert_penalties}

        if (patronSvc.alertsShown()) return false;

        // if the patron has any unshown alerts, show them now
        if (patronSvc.hasAlerts && 
            !$location.path().match(/alerts$/)) {

            $location
                .path('/circ/patron/' + patronSvc.current.id() + '/alerts')
                .search('card', null);
            return true;
        }

        // no alert required.  If the patron has fines and the show-bills
        // OUS is applied, direct to the bills page.
        if ($scope.patron_stats().fines.balance_owed > 0 // TODO: != 0 ?
            && egCore.env.aous['ui.circ.show_billing_tab_on_bills']
            && !$location.path().match(/bills$/)) {

            $scope.tab = 'bills';
            $location
                .path('/circ/patron/' + patronSvc.current.id() + '/bills')
                .search('card', null);

            return true;
        }

        return false;
    }

    // called after each route-specified controller is instantiated.
    // this doubles as a way to inform the top-level controller that
    // egStartup.go() has completed, which means we are clear to 
    // fetch the patron, etc.
    $scope.initTab = function(tab, patron_id) {
        console.log('init tab ' + tab);
        $scope.tab = tab;
        $scope.aous = egCore.env.aous;
        $scope.auth_user_id = egCore.auth.user().id();

        if (patron_id) {
            $scope.patron_id = patron_id;
            return patronSvc.setPrimary($scope.patron_id)
            .then(function() {
                // the page title context label comes from the tab.
                egCore.strings.setPageTitle(
                    egCore.strings.PAGE_TITLE_PATRON_NAME, 
                    egCore.strings['PAGE_TITLE_PATRON_' + tab.toUpperCase()],
                    {   lname : patronSvc.current.family_name(),
                        fname : patronSvc.current.first_given_name(),
                        mname : patronSvc.current.second_given_name()
                    }
                );
            })
            .then(function() {return patronSvc.checkAlerts()})
            .then(redirectToAlertPanel)
            .then(function(){
                $scope.ident_type_name = $scope.patron().ident_type().name()
                $scope.hasIdentTypeName = $scope.ident_type_name.length > 0;
            });
        } else {
            // No patron, use the tab name as the page title.
            egCore.strings.setPageTitle(
                egCore.strings['PAGE_TITLE_PATRON_' + tab.toUpperCase()]);
        }
        return $q.when();
    }

    $scope._show_dob = {};
    $scope.show_dob = function (val) {
        if ($scope.patron()) {
            if (typeof val != 'undefined') $scope._show_dob[$scope.patron().id()] = val;
            return $scope._show_dob[$scope.patron().id()];
        }
        return !egCore.env.aous['circ.obscure_dob'];
    }
        
    $scope.obscure_dob = function() { 
        return egCore.env.aous && egCore.env.aous['circ.obscure_dob'];
    }
    $scope.now_show_dob = function() { 
        return egCore.env.aous && egCore.env.aous['circ.obscure_dob'] ?
            $scope.show_dob() : true; 
    }

    $scope.patron = function() { return patronSvc.current }
    $scope.patron_stats = function() { return patronSvc.patron_stats }
    $scope.summary_stat_cats = function() { return patronSvc.summary_stat_cats }
    $scope.hasAlerts = function() { return patronSvc.hasAlerts }
    $scope.isPatronExpired = function() { return patronSvc.patronExpired }

    $scope.print_address = function(addr) {
        egCore.print.print({
            context : 'default', 
            template : 'patron_address', 
            scope : {
                patron : egCore.idl.toHash(patronSvc.current),
                address : egCore.idl.toHash(addr)
            }
        });
    }

    $scope.copy_address = function(addr) {
        // Alas, navigator.clipboard is not yet supported in FF and others.
        var lNode = document.querySelector('#patron-address-copy-' + addr.id());

        // Un-hide the textarea just long enough to copy its data.
        // Using node.style instead of ng-show/ng-hide in hopes it 
        // will be quicker, so the user never sees the textarea.
        lNode.style.visibility = 'visible';
        lNode.focus();
        lNode.select();

        if (!document.execCommand('copy')) {
            console.error('Copy command failed');
        }

        lNode.style.visibility = 'hidden';
    }

    $scope.toggle_expand_summary = function() {
        if ($scope.collapsePatronSummary) {
            $scope.collapsePatronSummary = false;
            egCore.hatch.removeItem('eg.circ.patron.summary.collapse');
        } else {
            $scope.collapsePatronSummary = true;
            egCore.hatch.setItem('eg.circ.patron.summary.collapse', true);
        }
    }
    
    // always expand the patron summary in the search UI, regardless
    // of stored preference.
    $scope.collapse_summary = function() {
        return $scope.tab != 'search' && $scope.collapsePatronSummary;
    }

    function _purge_account(dest_usr,override) {
        egNet.request(
            'open-ils.actor',
            'open-ils.actor.user.delete' + (override ? '.override' : ''),
            egCore.auth.token(),
            $scope.patron().id(),
            dest_usr
        ).then(function(resp){
            if (evt = egCore.evt.parse(resp)) {
                if (evt.code == '2004' /* ACTOR_USER_DELETE_OPEN_XACTS */) {
                    egConfirmDialog.open(
                        egCore.strings.PATRON_PURGE_CONFIRM_TITLE, egCore.strings.PATRON_PURGE_OVERRIDE_PROMPT,
                        {ok : function() {
                            _purge_account(dest_usr,true);
                        }}
                    );
                } else {
                    alert(js2JSON(evt));
                }
            } else {
                location.href = egCore.env.basePath + '/circ/patron/search';
            }
        });
    }

    function _purge_account_with_destination(dest_barcode) {
        egCore.pcrud.search('ac', {barcode : dest_barcode})
        .then(function(card) {
            if (!card) {
                egAlertDialog.open(egCore.strings.PATRON_PURGE_STAFF_BAD_BARCODE);
            } else {
                _purge_account(card.usr());
            }
        });
    }

    $scope.purge_account = function() {
        egConfirmDialog.open(
            egCore.strings.PATRON_PURGE_CONFIRM_TITLE, egCore.strings.PATRON_PURGE_CONFIRM,
            {ok : function() {
                egConfirmDialog.open(
                    egCore.strings.PATRON_PURGE_CONFIRM_TITLE, egCore.strings.PATRON_PURGE_LAST_CHANCE,
                    {ok : function() {
                        egNet.request(
                            'open-ils.actor',
                            'open-ils.actor.user.has_work_perm_at',
                            egCore.auth.token(), 'STAFF_LOGIN', $scope.patron().id()
                        ).then(function(resp) {
                            var is_staff = resp.length > 0;
                            if (is_staff) {
                                egPromptDialog.open(
                                    egCore.strings.PATRON_PURGE_STAFF_PROMPT,
                                    null, // TODO: this would be cool if it worked: egCore.auth.user().card().barcode(),
                                    {ok : function(barcode) {_purge_account_with_destination(barcode)}}
                                );
                            } else {
                                _purge_account();
                            }
                        });
                    }
                });
            }
        });
    }

    egCore.hatch.getItem('eg.circ.patron.summary.collapse')
    .then(function(val) {$scope.collapsePatronSummary = Boolean(val)});
}])

.controller('PatronBarcodeSearchCtrl',
       ['$scope','$location','egCore','egConfirmDialog','egUser','patronSvc','$uibModal','$q',
function($scope , $location , egCore , egConfirmDialog , egUser , patronSvc , $uibModal , $q) {
    $scope.selectMe = true; // focus text input
    patronSvc.clearPrimary(); // clear the default user

    // jump to the patron checkout UI
    function loadPatron(user_id) {
        egCore.audio.play('success.patron.by_barcode');
        $location
        .path('/circ/patron/' + user_id + '/checkout')
        .search('card', $scope.args.barcode);
        patronSvc.search_barcode = $scope.args.barcode;
    }

    // create an opt-in=yes response for the loaded user
    function createOptIn(user_id) {
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.org_unit_opt_in.create',
            egCore.auth.token(), user_id).then(function(resp) {
                if (evt = egCore.evt.parse(resp)) return alert(evt);
                loadPatron(user_id);
            }
        );
    }

    $scope.submitBarcode = function(args) {
        $scope.bcNotFound = null;
        $scope.optInRestricted = false;
        if (!args.barcode) return;
        args.barcode = args.barcode.replace(/\s/g,'');
        // blur so next time it's set to true it will re-apply select()
        $scope.selectMe = false;

        var user_id;

        // given a scanned barcode, this function finds any matching users
        // and handles multiple matches due to barcode completion
        function handleBarcodeCompletion(scanned_barcode) {
            var deferred = $q.defer();

            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.get_barcodes',
                egCore.auth.token(), egCore.auth.user().ws_ou(), 
                'actor', scanned_barcode)

            .then(function(resp) { // get_barcodes

                if (evt = egCore.evt.parse(resp)) {
                    alert(evt); // FIXME
                    deferred.reject();
                    return;
                }

                if (!resp || !resp[0]) {
                    $scope.bcNotFound = args.barcode;
                    $scope.selectMe = true;
                    egCore.audio.play('warning.patron.not_found');
                    deferred.reject();
                    return;
                }

                if (resp.length == 1) {
                    // exactly one matching barcode: return it
                    deferred.resolve();
                    user_id = resp[0].id;
                } else {
                    // multiple matching barcodes: let the user pick one 
                    var barcode_map = {};
                    var matches = [];
                    var promises = [];
                    var selected_barcode;
                    angular.forEach(resp, function(match) {
                        promises.push(
                            egUser.get(match.id, {useFields : ['home_ou']}).then(function(user) {
                                barcode_map[match.barcode] = user.id();
                                matches.push( {
                                    barcode: match.barcode,
                                    title: user.first_given_name() + ' ' + user.family_name(),
                                    org_name: user.home_ou().name(),
                                    org_shortname: user.home_ou().shortname()
                                });
                            })
                        );
                    });
                    return $q.all(promises)
                    .then(function() {
                        $uibModal.open({
                            templateUrl: './circ/share/t_barcode_choice_dialog',
                            controller:
                                ['$scope', '$uibModalInstance',
                                function($scope, $uibModalInstance) {
                                $scope.matches = matches;
                                $scope.ok = function(barcode) {
                                    $uibModalInstance.close();
                                    selected_barcode = barcode;
                                }
                                $scope.cancel = function() {$uibModalInstance.dismiss()}
                            }],
                        }).result.then(function() {
                            deferred.resolve();
                            user_id = barcode_map[selected_barcode];
                        });
                    });
                }
            });
            return deferred.promise;
        }

        // call our function to lookup matching users for the scanned barcode
        handleBarcodeCompletion(args.barcode).then(function() {

            // see if an opt-in request is needed
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.user.org_unit_opt_in.check',
                egCore.auth.token(), user_id
            ).then(function(optInResp) { // opt_in_check

                if (evt = egCore.evt.parse(optInResp)) {
                    alert(evt); // FIXME
                    return;
                }

                if (optInResp == 2) {
                    // opt-in disallowed at this location by patron's home library
                    $scope.optInRestricted = true;
                    $scope.selectMe = true;
                    egCore.audio.play('warning.patron.opt_in_restricted');
                    return;
                }
            
                if (optInResp == 1) {
                    // opt-in handled or not needed
                    return loadPatron(user_id);
                }

                // opt-in needed, show the opt-in dialog
                egUser.get(user_id, {useFields : []})

                .then(function(user) { // retrieve user
                    var org = egCore.org.get(user.home_ou());
                    egConfirmDialog.open(
                        egCore.strings.OPT_IN_DIALOG_TITLE,
                        egCore.strings.OPT_IN_DIALOG,
                        {   family_name : user.family_name(),
                            first_given_name : user.first_given_name(),
                            org_name : org.name(),
                            org_shortname : org.shortname(),
                            ok : function() { createOptIn(user.id()) },
                            cancel : function() {}
                        }
                    );
                })
            })
        })
    }
}])


/**
 * Manages patron search
 */
.controller('PatronSearchCtrl',
       ['$scope','$q','$routeParams','$timeout','$window','$location','egCore','ngToast',
       '$filter','egUser', 'patronSvc','egGridDataProvider','$document','bucketSvc',
       'egPatronMerge','egProgressDialog','$controller','$interpolate','$uibModal',
function($scope,  $q,  $routeParams,  $timeout,  $window,  $location,  egCore , ngToast,
         $filter,  egUser,  patronSvc , egGridDataProvider , $document , bucketSvc,
        egPatronMerge , egProgressDialog , $controller , $interpolate , $uibModal) {

    angular.extend(this, $controller('BasePatronSearchCtrl', {$scope : $scope}));
    $scope.initTab('search');

    $scope.gridControls = {
        activateItem : function(item) {
            $location.path('/circ/patron/' + item.id() + '/checkout');
        },
        selectedItems : function() { return [] }
    }

    $scope.bucketSvc = bucketSvc;
    $scope.bucketSvc.fetchUserBuckets();
    $scope.addToBucket = function(item, data, recs) {
        if (recs.length == 0) return;
        var added_count = 0;
        var failed_count = 0;
        var p = [];
        angular.forEach(recs,
            function(rec) {
                var item = new egCore.idl.cubi();
                item.bucket(data.id());
                item.target_user(rec.id());
                p.push(egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.item.create',
                    egCore.auth.token(), 'user', item
                ).then(
                    function(){ added_count++ },
                    function(){ failed_count++ }
                ));
            }
        );

        $q.all(p).then( function () {
            if (added_count) ngToast.create($interpolate(egCore.strings.BUCKET_ADD_SUCCESS)({ count: ''+added_count, name: data.name()} ));
            if (failed_count) ngToast.warning($interpolate(egCore.strings.BUCKET_ADD_FAIL)({ count: ''+failed_count, name: data.name() } ));
        });
    }

    var temp_scope = $scope;
    $scope.openCreateBucketDialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_bucket_create',
            backdrop: 'static',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.name) return;
            bucketSvc.createBucket(args.name, args.desc).then(
                function(id) {
                    if (id) {
                        $scope.bucketSvc.fetchBucket(id).then(function (b) {
                            $scope.addToBucket(
                                null,
                                b,
                                $scope.gridControls.selectedItems()
                            );
                            $scope.bucketSvc.fetchUserBuckets(true);
                        });
                    }
                }
            );
        });
    }

    $scope.$watch(
        function() {return $scope.gridControls.selectedItems()},
        function(list) {
            if (list[0]) 
                patronSvc.setPrimary(null, list[0]);
        },
        true
    );

    $scope.need_one_selected = function() {
        var items = $scope.gridControls.selectedItems();
        return (items.length > 0) ? false : true;
    }
    $scope.need_two_selected = function() {
        var items = $scope.gridControls.selectedItems();
        return (items.length == 2) ? false : true;
    }
    $scope.merge_patrons = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length != 2) return false;

        var patron_ids = [];
        angular.forEach(items, function(i) {
            patron_ids.push(i.id());
        });
        egPatronMerge.do_merge(patron_ids).then(
            function() {
                // ensure that we're not drawing from cached
                // resuts, as a successful merge just deleted a
                // record
                delete patronSvc.lastSearch;
                $scope.gridControls.refresh();
            },
            function(evt) {
                if (evt && evt.textcode == 'MERGE_SELF_NOT_ALLOWED') {
                    ngToast.warning(egCore.strings.MERGE_SELF_NOT_ALLOWED);
                }
            }
        );
    }
   
}])

/**
 * Manages messages
 */
.controller('PatronMessagesCtrl',
       ['$scope','$q','$routeParams','egCore','$uibModal','patronSvc','egCirc',
function($scope , $q , $routeParams,  egCore , $uibModal , patronSvc , egCirc) {
    $scope.initTab('messages', $routeParams.id);
    var usr_id = $routeParams.id;
    var org_ids = egCore.org.fullPath(egCore.auth.user().ws_ou(), true);

    // setup date filters
    var start = new Date(); // now - 1 year
    start.setFullYear(start.getFullYear() - 1),
    $scope.dates = {
        start_date : start,
        end_date : new Date()
    }

    function date_range() {
        var start = $scope.dates.start_date.toISOString().replace(/T.*/,'');
        var end = $scope.dates.end_date.toISOString().replace(/T.*/,'');
        var today = new Date().toISOString().replace(/T.*/,'');
        if (end == today) end = 'now';
        return [start, end];
    }

    // grid queries
   
    var activeGrid = $scope.activeGridControls = {
        setSort : function() {
            return ['set_date'];
        },
        setQuery : function() {
            return {
                usr : usr_id,
                org_unit : org_ids,
                '-or' : [
                    {stop_date : null},
                    {stop_date : {'>' : 'now'}}
                ]
            }
        }
    }

    var archiveGrid = $scope.archiveGridControls = {
        setSort : function() {
            return ['set_date'];
        },
        setQuery : function() {
            return {
                usr : usr_id, 
                org_unit : org_ids,
                stop_date : {'<=' : 'now'},
                set_date : {between : date_range()}
            };
        }
    };

    $scope.removePenalty = function(selected) {
        // the grid stores flattened penalties.  Fetch penalty objects first

        var ids = selected.map(function(s){ return s.id });
        egCore.pcrud.search('ausp', 
            {id : ids}, {}, 
            {atomic : true, authoritative : true}

        // then delete them
        ).then(function(penalties) {
            return egCore.pcrud.remove(penalties);

        // then refresh the grid
        }).then(function() {
            activeGrid.refresh();
        });
    }

    $scope.archivePenalty = function(selected) {
        // the grid stores flattened penalties.  Fetch penalty objects first

        var ids = selected.map(function(s){ return s.id });
        egCore.pcrud.search('ausp', 
            {id : ids}, {}, 
            {atomic : true, authoritative : true}

        // then delete them
        ).then(function(penalties) {
            angular.forEach(penalties, function(p){ p.stop_date('now') });
            return egCore.pcrud.update(penalties);

        // then refresh the grid
        }).then(function() {
            activeGrid.refresh();
            archiveGrid.refresh();
        });
    }

    // leverage egEnv for caching
    function fetchPenaltyTypes() {
        if (egCore.env.csp) 
            return $q.when(egCore.env.csp.list);
        return egCore.pcrud.search(
            // id <= 100 are reserved for system use
            'csp', {id : {'>': 100}}, {}, {atomic : true})
        .then(function(penalties) {
            egCore.env.absorbList(penalties, 'csp');
            return penalties;
        });
    }

    $scope.createPenalty = function() {
        egCirc.create_penalty(usr_id).then(function() {
            activeGrid.refresh();
            // force a refresh of the user, since they may now
            // have blocking penalties, etc.
            patronSvc.setPrimary(patronSvc.current.id(), null, true);
        });
    }

    $scope.editPenalty = function(selected) {
        if (selected.length == 0) return;

        // grab the penalty from the user object
        var penalty = patronSvc.current.standing_penalties().filter(
            function(p) {return p.id() == selected[0].id})[0];

        egCirc.edit_penalty(penalty).then(function() {
            activeGrid.refresh();
            // force a refresh of the user, since they may now
            // have blocking penalties, etc.
            patronSvc.setPrimary(patronSvc.current.id(), null, true);
        });
    }
}])


/**
 * Credentials tester
 */
.controller('PatronVerifyCredentialsCtrl',
       ['$scope','$routeParams','$location','egCore',
function($scope,  $routeParams , $location , egCore) {
    $scope.verified = null;
    $scope.focusMe = true;

    // called with a patron, pre-populate the form args
    $scope.initTab('other', $routeParams.id).then(
        function() {
            if ($routeParams.id && $scope.patron()) {
                $scope.prepop = true;
                $scope.username = $scope.patron().usrname();
                $scope.barcode = $scope.patron().card().barcode();
            } else {
                $scope.username = '';
                $scope.barcode = '';
                $scope.password = '';
            }
        }
    );

    // verify login credentials
    $scope.verify = function() {
        $scope.verified = null;
        $scope.notFound = false;

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.verify_user_password',
            egCore.auth.token(), $scope.barcode,
            $scope.username, hex_md5($scope.password || '')

        ).then(function(resp) {
            $scope.focusMe = true;
            if (evt = egCore.evt.parse(resp)) {
                alert(evt);
            } else if (resp == 1) {
                $scope.verified = true;
            } else {
                $scope.verified = false;
            }
        });
    }

    // load the main patron UI for the provided username or barcode
    $scope.load = function($event) {
        $scope.notFound = false;
        $scope.verified = null;

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.retrieve_id_by_barcode_or_username',
            egCore.auth.token(), $scope.barcode, $scope.username

        ).then(function(resp) {

            if (Number(resp)) {
                $location.path('/circ/patron/' + resp + '/checkout');
                return;
            }

            // something went wrong...
            $scope.focusMe = true;
            if (evt = egCore.evt.parse(resp)) {
                if (evt.textcode == 'ACTOR_USR_NOT_FOUND') {
                    $scope.notFound = true;
                    return;
                }
                return alert(evt);
            } else {
                alert(resp);
            }
        });

        // load() button sits within the verify form.  
        // avoid submitting the verify() form action on load()
        $event.preventDefault();
    }
}])

.controller('PatronAlertsCtrl',
       ['$scope','$routeParams','$location','egCore','patronSvc',
function($scope,  $routeParams , $location , egCore , patronSvc) {

    $scope.initTab('other', $routeParams.id)
    .then(function() {
        $scope.patronExpired = patronSvc.patronExpired;
        $scope.patronExpiresSoon = patronSvc.patronExpiresSoon;
        $scope.retrievedWithInactive = patronSvc.fetchedWithInactiveCard();
        $scope.invalidAddresses = patronSvc.invalidAddresses;
    });

}])

.controller('PatronNotesCtrl',
       ['$scope','$filter','$routeParams','$location','egCore','patronSvc','$uibModal',
        'egConfirmDialog',
function($scope,  $filter , $routeParams , $location , egCore , patronSvc , $uibModal,
         egConfirmDialog) {
    $scope.initTab('other', $routeParams.id);
    var usr_id = $routeParams.id;

    // fetch the notes
    function refreshPage() {
        $scope.notes = [];
        egCore.pcrud.search('aun', 
            {usr : usr_id}, 
            {flesh : 1, flesh_fields : {aun : ['creator']}}, 
            {authoritative : true})
        .then(null, null, function(note) {
            $scope.notes.push(note);
        });
    }

    // open the new-note dialog and create the note
    $scope.newNote = function() {
        $uibModal.open({
            templateUrl: './circ/patron/t_new_note_dialog',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance',
            function($scope, $uibModalInstance) {
                $scope.focusNote = true;
                $scope.args = {};
                $scope.require_initials = egCore.env.aous['ui.staff.require_initials.patron_info_notes'];
                $scope.ok = function(count) { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }],
        }).result.then(
            function(args) {
                if (!args.value) return;
                var note = new egCore.idl.aun();
                note.usr(usr_id);
                note.title(args.title);
                note.value(args.value);
                note.pub(args.pub ? 't' : 'f');
                note.creator(egCore.auth.user().id());
                if (args.initials) 
                    note.value(note.value() + ' [' + args.initials + ']');
                egCore.pcrud.create(note).then(function() {refreshPage()});
            }
        );
    }

    // delete the selected note
    $scope.deleteNote = function(note) {
        egConfirmDialog.open(
            egCore.strings.PATRON_NOTE_DELETE_CONFIRM_TITLE, egCore.strings.PATRON_NOTE_DELETE_CONFIRM,
            {ok : function() {
                egCore.pcrud.remove(note).then(function() {refreshPage()});
            },
            note_title : note.title(),
            create_date : note.create_date()
        });
    }

    // print the selected note
    $scope.printNote = function(note) {
        var hash = egCore.idl.toHash(note);
        hash.usr = egCore.idl.toHash($scope.patron());
        egCore.print.print({
            context : 'default', 
            template : 'patron_note', 
            scope : {note : hash}
        });
    }

    // perform the initial note fetch
    refreshPage();
}])

.controller('PatronGroupCtrl',
       ['$scope','$routeParams','$q','$window','$timeout','$location','egCore',
        'patronSvc','$uibModal','egPromptDialog','egConfirmDialog',
function($scope,  $routeParams , $q , $window , $timeout,  $location , egCore ,
         patronSvc , $uibModal , egPromptDialog , egConfirmDialog) {

    var usr_id = $routeParams.id;

    $scope.totals = {owed : 0, total_out : 0, overdue : 0}

    var grid = $scope.gridControls = {
        activateItem : function(item) {
            $location.path('/circ/patron/' + item.id + '/checkout');
        },
        itemRetrieved : function(item) {

            if (item.id == patronSvc.current.id()) {
                item.stats = patronSvc.patron_stats;

            } else {
                // flesh stats for other group members
                patronSvc.getUserStats(item.id).then(function(stats) {
                    item.stats = stats;
                    $scope.totals.total_out += stats.checkouts.total_out; 
                    $scope.totals.overdue += stats.checkouts.overdue; 
                });
            }
        },
        setSort : function() {
            return ['create_date'];
        },
        watchQuery: function() {
            if (patronSvc.current) {
                return {
                    usrgroup : patronSvc.current.usrgroup(),
                    deleted : 'f'
                };
            }
            return null;
        }
    }

    $scope.initTab('other', $routeParams.id)
    .then(function(redirect) {
        // if we are redirecting to the alerts page, avoid updating the
        // grid query.
        if (redirect) return;
        // let initTab() fetch the user first so we can know the usrgroup
        $scope.totals.owed = patronSvc.patron_stats.fines.group_balance_owed;
    });

    $scope.removeFromGroup = function(selected) {
        var promises = [];
        angular.forEach(selected, function(user) {
            console.debug('removing user ' + user.id + ' from group');

            promises.push(
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.usergroup.new',
                    egCore.auth.token(), user.id, true
                )
            );
        });

        $q.all(promises).then(function() {grid.refresh()});
    }

    function addUserToGroup(user) {
        user.usrgroup(patronSvc.current.usrgroup());
        user.ischanged(true);
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.update',
            egCore.auth.token(), user

        ).then(function() {grid.refresh()});
    }

    // fetch each user ("selected" has flattened users)
    // update the usrgroup, then update the user object
    // After all updates are complete, refresh the grid.
    function moveUsersToGroup(target_user, selected) {
        var promises = [];

        angular.forEach(selected, function(user) {
            promises.push(
                egCore.pcrud.retrieve('au', user.id)
                .then(function(u) {
                    u.usrgroup(target_user.usrgroup());
                    u.ischanged(true);
                    return egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.patron.update',
                        egCore.auth.token(), u
                    );
                })
            );
        });

        $q.all(promises).then(function() {grid.refresh()});
    }

    function showMoveToGroupConfirm(barcode, selected, outbound) {

        // find the user
        egCore.pcrud.search('ac', {barcode : barcode})

        // fetch the fleshed user
        .then(function(card) {

            if (!card) return; // TODO: warn user

            egCore.pcrud.retrieve('au', card.usr())
            .then(function(user) {
                user.card(card);
                $uibModal.open({
                    templateUrl: './circ/patron/t_move_to_group_dialog',
                    backdrop: 'static',
                    controller: [
                                '$scope','$uibModalInstance',
                        function($scope , $uibModalInstance) {
                            $scope.user = user;
                            $scope.selected = selected;
                            $scope.outbound = outbound;
                            $scope.ok = 
                                function(count) { $uibModalInstance.close() }
                            $scope.cancel = 
                                function () { $uibModalInstance.dismiss() }
                        }
                    ]
                }).result.then(function() {
                    if (outbound) {
                        moveUsersToGroup(user, selected);
                    } else {
                        addUserToGroup(user);
                    }
                });
            });
        });
    }

    // selected == move selected patrons to another patron's group
    // !selected == patron from a different group moves into our group
    function moveToGroup(selected, outbound) {
        egPromptDialog.open(
            egCore.strings.GROUP_ADD_USER, '',
            {ok : function(value) {
                if (value) 
                    showMoveToGroupConfirm(value, selected, outbound);
            }}
        );
    }

    $scope.moveToGroup = function() { moveToGroup([], false) };
    $scope.moveToAnotherGroup = function(selected) { moveToGroup(selected, true) };

    $scope.cloneUser = function(selected) {
        if (!selected.length) return;
        var url = $location.absUrl().replace(
            /\/patron\/.*/, 
            '/patron/register/clone/' + selected[0].id);
        $window.open(url, '_blank').focus();
    }

    $scope.retrieveSelected = function(selected) {
        if (!selected.length) return;
        angular.forEach(selected, function(usr) {
            $timeout(function() {
                var url = $location.absUrl().replace(
                    /\/patron\/.*/,
                    '/patron/' + usr.id + '/checkout');
                $window.open(url, '_blank')
            });
        });
    }

}])

.controller('PatronStatCatsCtrl',
       ['$scope','$routeParams','$q','egCore','patronSvc',
function($scope,  $routeParams , $q , egCore , patronSvc) {
    $scope.initTab('other', $routeParams.id)
    .then(function(redirect) {
        // Entries for org-visible stat cats are fleshed.  Any others
        // have to be fleshed within.

        var to_flesh = {};
        angular.forEach(patronSvc.current.stat_cat_entries(), 
            function(entry) {
                if (!angular.isObject(entry.stat_cat())) {
                    to_flesh[entry.stat_cat()] = entry;
                }
            }
        );

        if (!Object.keys(to_flesh).length) return;

        egCore.pcrud.search('actsc', {id : Object.keys(to_flesh)})
        .then(null, null, function(cat) { // stream
            cat.owner(egCore.org.get(cat.owner())); // owner flesh
            to_flesh[cat.id()].stat_cat(cat);
        });
    });
}])

.controller('PatronSurveyCtrl',
       ['$scope','$routeParams','$location','egCore','patronSvc',
function($scope,  $routeParams , $location , egCore , patronSvc) {
    $scope.initTab('other', $routeParams.id);
    var usr_id = $routeParams.id;
    var org_ids = egCore.org.fullPath(egCore.auth.user().ws_ou(), true);

    $scope.surveys = [];
    var svr_responses = {};

    // fetch all survey responses for this user.
    egCore.pcrud.search('asvr',
        {usr : usr_id},
        {flesh : 2, flesh_fields : {asvr : ['survey','question','answer']}}
    ).then(
        function() {
            // All responses collected and deduplicated.
            // Create one collection of responses per survey.

            angular.forEach(svr_responses, function(questions, survey_id) {
                var collection = {responses : []};
                angular.forEach(questions, function(response) {
                    collection.survey = response.survey(); // same for one.
                    collection.responses.push(response);
                });
                $scope.surveys.push(collection);
            });
        },
        null, 
        function(response) {

            // Discard responses for out-of-scope surveys.
            if (org_ids.indexOf(response.survey().owner()) < 0) 
                return;

            // survey_id => question_id => response
            var svr_id = response.survey().id();
            var qst_id = response.question().id();

            if (!svr_responses[svr_id]) 
                svr_responses[svr_id] = [];

            if (!svr_responses[svr_id][qst_id]) {
                svr_responses[svr_id][qst_id] = response;

            } else {
                // We have multiple responses for the same question.
                // For this UI we only care about the most recent response.
                if (response.effective_date() > 
                    svr_responses[svr_id][qst_id].effective_date())
                    svr_responses[svr_id][qst_id] = response;
            }
        }
    );
}])

.controller('PatronFetchLastCtrl',
       ['$scope','$location','egCore',
function($scope , $location , egCore) {

    var ids = egCore.hatch.getLoginSessionItem('eg.circ.recent_patrons') || [];
    if (ids.length) 
        return $location.path('/circ/patron/' + ids[0] + '/checkout');

    $scope.no_last = true;
}])

.controller('PatronTriggeredEventsCtrl',
       ['$scope','$routeParams','$location','egCore','patronSvc',
function($scope,  $routeParams,  $location , egCore , patronSvc) {
    $scope.initTab('other', $routeParams.id);

    var url = $location.absUrl().replace(/\/staff.*/, '/actor/user/event_log');
    url += '?patron_id=' + encodeURIComponent($routeParams.id);

    $scope.triggered_events_url = url;
    $scope.funcs = {};
}])

.controller('PatronMessageCenterCtrl',
       ['$scope','$routeParams','$location','egCore','patronSvc',
function($scope,  $routeParams,  $location , egCore , patronSvc) {
    $scope.initTab('other', $routeParams.id);

    var url = $location.protocol() + '://' + $location.host()
        + egCore.env.basePath.replace(/\/staff.*/,  '/actor/user/message');
    url += '/' + encodeURIComponent($routeParams.id);

    $scope.message_center_url = url;
    $scope.funcs = {};
}])

.controller('PatronPermsCtrl',
       ['$scope','$routeParams','$window','$location','egCore',
function($scope , $routeParams , $window , $location , egCore) {
    $scope.initTab('other', $routeParams.id);

    var url = $location.absUrl().replace(
        /\/eg\/staff.*/, '/xul/server/patron/user_edit.xhtml');

    url += '?usr=' + encodeURIComponent($routeParams.id);

    // user_edit does not load the session via cookie.  It uses URL 
    // params or xulG instead.  Pass via xulG.
    $scope.funcs = {
        ses : egCore.auth.token(),
        on_patron_save : function() {
            $scope.funcs.reload();
        }
    }

    $scope.user_perms_url = url;
}])

