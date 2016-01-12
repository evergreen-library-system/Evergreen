/**
 * Patron App
 *
 * Search, checkout, items out, holds, bills, edit, etc.
 */

angular.module('egPatronApp', ['ngRoute', 'ui.bootstrap', 
    'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

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

        return egCore.startup.go().then(function() {

            // This call requires orgs to be loaded, because it
            // calls egCore.org.ancestors(), so call it after startup
            return egCore.pcrud.search('actsc', 
                {owner : egCore.org.ancestors(
                    egCore.auth.user().ws_ou(), true)},
                {}, {atomic : true}
            ).then(function(cats) {
                egCore.env.absorbList(cats, 'actsc');
            });
        });
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

    $routeProvider.when('/circ/patron/:id/bill/:xact_id', {
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

    $routeProvider.otherwise({redirectTo : '/circ/patron/search'});
})

/**
 * Patron service
 */
.factory('patronSvc',
       ['$q','$timeout','$location','egCore','egUser','$locale',
function($q , $timeout , $location , egCore,  egUser , $locale) {

    var service = {
        // cached patron search results
        patrons : [],

        // currently selected patron object
        current : null, 

        // patron circ stats (overdues, fines, holds)
        patron_stats : null,

        // event types manually overridden, which should always be
        // overridden for checkouts to this patron for this instance of
        // the interface.
        checkout_overrides : {},
    };

    // when we change the default patron, we need to clear out any
    // data collected on that patron
    service.resetPatronLists = function() {
        service.checkouts = [];
        service.items_out = []
        service.items_out_ids = [];
        service.holds = [];
        service.hold_ids = [];
        service.checkout_overrides = {};
        service.patron_stats = null;
        service.noncat_ids = [];
        service.hasAlerts = false;
        service.alertsShown = false;
        service.patronExpired = false;
        service.patronExpiresSoon = false;
        service.retrievedWithInactive = false;
        service.invalidAddresses = false;
    }
    service.resetPatronLists();  // initialize

    // shortcut to force-reload the current primary
    service.refreshPrimary = function() {
        if (!service.current) return $q.when();
        return service.setPrimary(service.current.id(), null, true);
    }

    // clear the currently focused user
    service.clearPrimary = function() {
        // reset with no patron
        service.resetPatronLists();
        service.current = null;
        service.patron_stats = null;
        return $q.when();
    }

    // sets the primary display user, fetching data as necessary.
    service.setPrimary = function(id, user, force) {
        var user_id = id ? id : (user ? user.id() : null);

        console.debug('setting primary user to: ' + user_id);

        if (!user_id) return $q.reject();

        // when loading a new patron, update the last patron setting
        if (!service.current || service.current.id() != user_id)
            egCore.hatch.setLocalItem('eg.circ.last_patron', user_id);

        // avoid running multiple retrievals for the same patron, which
        // can happen during dbl-click by maintaining a single running
        // data retrieval promise
        if (service.primaryUserPromise) {
            if (service.primaryUserId == user_id) {
                return service.primaryUserPromise.promise;
            } else {
                service.primaryUserPromise = null;
            }
        }

        service.primaryUserPromise = $q.defer();
        service.primaryUserId = user_id;

        service.getPrimary(id, user, force)
        .then(function() {
            var p = service.primaryUserPromise;
            service.primaryUserId = null;
            // clear before resolution just to be safe.
            service.primaryUserPromise = null;
            p.resolve();
        });

        return service.primaryUserPromise.promise;
    }

    service.getPrimary = function(id, user, force) {

        if (user) {
            if (!force && service.current && 
                service.current.id() == user.id()) {
                if (service.patron_stats) {
                    return $q.when();
                } else {
                    return service.fetchUserStats();
                }
            }

            service.resetPatronLists();
            service.current = user;
            service.localFlesh(user);
            return service.fetchUserStats();

        } else if (id) {
            if (!force && service.current && service.current.id() == id) {
                if (service.patron_stats) {
                    return $q.when();
                } else {
                    return service.fetchUserStats();
                }
            }

            service.resetPatronLists();

            return egUser.get(id).then(
                function(user) {
                    service.current = user;
                    service.localFlesh(user);
                    return service.fetchUserStats();
                },
                function(err) {
                    console.error(
                        "unable to fetch user "+id+': '+js2JSON(err))
                }
            );
        } else {

            // fetching a null user clears the primary user.
            // NOTE: this should probably reject() and log an error, 
            // but calling clear for backwards compat for now.
            return service.clearPrimary();
        }
    }

    // flesh some additional user fields locally
    service.localFlesh = function(user) {
        if (!angular.isObject(typeof user.home_ou()))
            user.home_ou(egCore.org.get(user.home_ou()));

        angular.forEach(
            user.standing_penalties(),
            function(penalty) {
                if (!angular.isObject(penalty.org_unit()))
                    penalty.org_unit(egCore.org.get(penalty.org_unit()));
            }
        );

        // stat_cat_entries == stat_cat_entry_user_map
        angular.forEach(user.stat_cat_entries(), function(map) {
            if (angular.isObject(map.stat_cat())) return;
            // At page load, we only retrieve org-visible stat cats.
            // For the common case, ignore entries for remote stat cats.
            var cat = egCore.env.actsc.map[map.stat_cat()];
            if (cat) {
                map.stat_cat(cat);
                cat.owner(egCore.org.get(cat.owner()));
            }
        });
    }

    // resolves to true if the patron account has expired or will
    // expire soon, based on YAOUS circ.patron_expires_soon_warning
    // note: returning a promise is no longer strictly necessary
    // (no more async activity) if the calling function is changed too.
    service.testExpire = function() {

        var expire = Date.parse(service.current.expire_date());
        if (expire < new Date()) {
            return $q.when(service.patronExpired = true);
        }

        var soon = egCore.env.aous['circ.patron_expires_soon_warning'];
        if (Number(soon)) {
            var preExpire = new Date();
            preExpire.setDate(preExpire.getDate() + Number(soon));
            if (expire < preExpire) 
                return $q.when(service.patronExpiresSoon = true);
        }

        return $q.when(false);
    }

    // resolves to true if the patron account has any invalid addresses.
    service.testInvalidAddrs = function() {

        if (service.invalidAddresses)
            return $q.when(true);

        var fail = false;

        angular.forEach(
            service.current.addresses(), 
            function(addr) { if (addr.valid() == 'f') fail = true }
        );

        return $q.when(fail);
    }

    // resolves to true if there is any aspect of the patron account
    // which should produce a message in the alerts panel
    service.checkAlerts = function() {

        if (service.hasAlerts) // already checked
            return $q.when(true); 

        var deferred = $q.defer();
        var p = service.current;

        if (service.alert_penalties.length ||
            p.alert_message() ||
            p.active() == 'f' ||
            p.barred() == 't' ||
            service.patron_stats.holds.ready) {

            service.hasAlerts = true;
        }

        // see if the user was retrieved with an inactive card
        if (bc = $location.search().card) {
            var card = p.cards().filter(
                function(c) { return c.barcode() == bc })[0];

            if (card && card.active() == 'f') {
                service.hasAlerts = true;
                service.retrievedWithInactive = true;
            }
        }

        // regardless of whether we know of alerts, we still need 
        // to test/fetch the expire data for display
        service.testExpire().then(function(bool) {
            if (bool) service.hasAlerts = true;
            deferred.resolve(service.hasAlerts);
        });

        service.testInvalidAddrs().then(function(bool) {
            if (bool) service.invalidAddresses = true;
            deferred.resolve(service.invalidAddresses);
        });

        return deferred.promise;
    }

    service.fetchGroupFines = function() {
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.usergroup.members.balance_owed',
            egCore.auth.token(), service.current.usrgroup()
        ).then(function(list) {
            var total = 0;
            angular.forEach(list, function(u) { 
                total += 100 * Number(u.balance_owed)
            });
            service.patron_stats.fines.group_balance_owed = total / 100;
        });
    }

    service.getUserStats = function(id) {
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.opac.vital_stats.authoritative', 
            egCore.auth.token(), id
        ).then(
            function(stats) {
                // force numeric to ensure correct boolean handling in templates
                stats.fines.balance_owed = Number(stats.fines.balance_owed);
                stats.checkouts.overdue = Number(stats.checkouts.overdue);
                stats.checkouts.claims_returned = 
                    Number(stats.checkouts.claims_returned);
                stats.checkouts.lost = Number(stats.checkouts.lost);
                stats.checkouts.out = Number(stats.checkouts.out);
                stats.checkouts.total_out = 
                    stats.checkouts.out + stats.checkouts.overdue;

                if (!egCore.env.aous['circ.do_not_tally_claims_returned'])
                    stats.checkouts.total_out += stats.checkouts.claims_returned;

                if (egCore.env.aous['circ.tally_lost'])
                    stats.checkouts.total_out += stats.checkouts.lost

                return stats;
            }
        );
    }

    // Fetches the IDs of any active non-cat checkouts for the current
    // user.  Also sets the patron_stats non_cat count value to match.
    service.getUserNonCats = function(id) {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.open_non_cataloged_circulation.user.authoritative',
            egCore.auth.token(), id
        ).then(function(noncat_ids) {
            service.noncat_ids = noncat_ids;
            service.patron_stats.checkouts.noncat = noncat_ids.length;
        });
    }

    // grab additional circ info
    service.fetchUserStats = function() {
        return service.getUserStats(service.current.id())
        .then(function(stats) {
            service.patron_stats = stats
            service.alert_penalties = service.current.standing_penalties()
                .filter(function(pen) { 
                return pen.standing_penalty().staff_alert() == 't' 
            });

            service.summary_stat_cats = [];
            angular.forEach(service.current.stat_cat_entries(), 
                function(map) {
                    if (angular.isObject(map.stat_cat()) &&
                        map.stat_cat().usr_summary() == 't') {
                        service.summary_stat_cats.push(map);
                    }
                }
            );

            // run these two in parallel
            var p1 = service.getUserNonCats(service.current.id());
            var p2 = service.fetchGroupFines();
            return $q.all([p1, p2]);
        });
    }

    // Avoid using parens [e.g. (1.23)] to indicate negative numbers, 
    // which is the Angular default.
    // http://stackoverflow.com/questions/17441254/why-angularjs-currency-filter-formats-negative-numbers-with-parenthesis
    // FIXME: This change needs to be moved into a project-wide collection
    // of locale overrides.
    $locale.NUMBER_FORMATS.PATTERNS[1].negPre = '-';
    $locale.NUMBER_FORMATS.PATTERNS[1].negSuf = '';

    return service;
}])

/**
 * Manages tabbed patron view.
 * This is the parent scope of all patron tab scopes.
 *
 * */
.controller('PatronCtrl',
       ['$scope','$q','$location','$filter','egCore','egUser','patronSvc',
function($scope,  $q,  $location , $filter,  egCore,  egUser,  patronSvc) {

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

        if (patronSvc.alertsShown) return false;
        patronSvc.alertsShown = true;

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

        if (patron_id) {
            $scope.patron_id = patron_id;
            return patronSvc.setPrimary($scope.patron_id)
            .then(function() {return patronSvc.checkAlerts()})
            .then(redirectToAlertPanel);
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

    egCore.hatch.getItem('eg.circ.patron.summary.collapse')
    .then(function(val) {$scope.collapsePatronSummary = Boolean(val)});
}])

.controller('PatronBarcodeSearchCtrl',
       ['$scope','$location','egCore','egConfirmDialog','egUser','patronSvc',
function($scope , $location , egCore , egConfirmDialog , egUser , patronSvc) {
    $scope.selectMe = true; // focus text input
    patronSvc.clearPrimary(); // clear the default user

    // jump to the patron checkout UI
    function loadPatron(user_id) {
        $location
        .path('/circ/patron/' + user_id + '/checkout')
        .search('card', $scope.args.barcode);
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

        // blur so next time it's set to true it will re-apply select()
        $scope.selectMe = false;

        var user_id;

        // lookup barcode
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            egCore.auth.token(), egCore.auth.user().ws_ou(), 
            'actor', args.barcode)

        .then(function(resp) { // get_barcodes

            if (evt = egCore.evt.parse(resp)) {
                alert(evt); // FIXME
                return;
            }

            if (!resp || !resp[0]) {
                $scope.bcNotFound = args.barcode;
                $scope.selectMe = true;
                return;
            }

            // see if an opt-in request is needed
            user_id = resp[0].id;
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.user.org_unit_opt_in.check',
                egCore.auth.token(), user_id);

        }).then(function(optInResp) { // opt_in_check

            if (evt = egCore.evt.parse(optInResp)) {
                alert(evt); // FIXME
                return;
            }

            if (optInResp == 2) {
                // opt-in disallowed at this location by patron's home library
                $scope.optInRestricted = true;
                $scope.selectMe = true;
                return;
            }
           
            if (optInResp == 1) {
                // opt-in handled or not needed
                return loadPatron(user_id);
            }

            // opt-in needed, show the opt-in dialog
            egUser.get(user_id, {useFields : []})

            .then(function(user) { // retrieve user
                egConfirmDialog.open(
                    egCore.strings.OPT_IN_DIALOG, '',
                    {   org : egCore.org.get(user.home_ou()),
                        user : user,
                        ok : function() { createOptIn(user.id()) },
                        cancel : function() {}
                    }
                );
            })
        });
    }
}])


/**
 * Manages patron search
 */
.controller('PatronSearchCtrl',
       ['$scope','$q','$routeParams','$timeout','$window','$location','egCore',
       '$filter','egUser', 'patronSvc','egGridDataProvider','$document',
function($scope,  $q,  $routeParams,  $timeout,  $window,  $location,  egCore,
        $filter,  egUser,  patronSvc , egGridDataProvider , $document) {

    $scope.initTab('search');
    $scope.focusMe = true;
    $scope.searchArgs = {
        // default to searching globally
        home_ou : egCore.org.tree()
    };

    // last used patron search form element
    var lastFormElement;

    $scope.gridControls = {
        activateItem : function(item) {
            $location.path('/circ/patron/' + item.id() + '/checkout');
        },
        selectedItems : function() {return []}
    }

    // Handle URL-encoded searches
    if ($location.search().search) {
        console.log('URL search = ' + $location.search().search);
        patronSvc.urlSearch = {search : JSON2js($location.search().search)};

        // why the double-JSON encoded sort?
        if (patronSvc.urlSearch.search.search_sort) {
            patronSvc.urlSearch.sort = 
                JSON2js(patronSvc.urlSearch.search.search_sort);
        } else {
            patronSvc.urlSearch.sort = [];
        }
        delete patronSvc.urlSearch.search.search_sort;
    }

    var propagate;
    if (patronSvc.lastSearch) {
        propagate = patronSvc.lastSearch.search;
    } else if (patronSvc.urlSearch) {
        propagate = patronSvc.urlSearch.search;
    }

    if (egCore.env.pgt) {
        $scope.profiles = egCore.env.pgt.list;
    } else {
        egCore.pcrud.search('pgt', {parent : null}, 
            {flesh : -1, flesh_fields : {pgt : ['children']}}
        ).then(
            function(tree) {
                egCore.env.absorbTree(tree, 'pgt')
                $scope.profiles = egCore.env.pgt.list;
            }
        );
    }

    if (propagate) {
        // populate the search form with our cached / preexisting search info
        angular.forEach(propagate, function(val, key) {
            if (key == 'profile')
                val.value = $scope.profiles.filter(function(p) { p.id() == val.value })[0];
            if (key == 'home_ou')
                val.value = egCore.org.get(val.value);
            $scope.searchArgs[key] = val.value;
        });
    }

    var provider = egGridDataProvider.instance({});

    $scope.$watch(
        function() {return $scope.gridControls.selectedItems()},
        function(list) {
            if (list[0]) 
                patronSvc.setPrimary(null, list[0]);
        },
        true
    );
        
    provider.get = function(offset, count) {
        var deferred = $q.defer();

        var fullSearch;
        if (patronSvc.urlSearch) {
            fullSearch = patronSvc.urlSearch;
            // enusre the urlSearch only runs once.
            delete patronSvc.urlSearch;

        } else {

            var search = compileSearch($scope.searchArgs);
            if (Object.keys(search) == 0) return $q.when();

            var home_ou = search.home_ou;
            delete search.home_ou;
            var inactive = search.inactive;
            delete search.inactive;

            fullSearch = {
                search : search,
                sort : compileSort(),
                inactive : inactive,
                home_ou : home_ou,
            };
        }

        fullSearch.count = count;
        fullSearch.offset = offset;

        if (patronSvc.lastSearch) {
            // search repeated, return the cached results
            if (angular.equals(fullSearch, patronSvc.lastSearch)) {
                console.log('patron search returning ' + 
                    patronSvc.patrons.length + ' cached results');
                
                // notify has to happen after returning the promise
                $timeout(
                    function() {
                        angular.forEach(patronSvc.patrons, function(user) {
                            deferred.notify(user);
                        });
                        deferred.resolve();
                    }
                );
                return deferred.promise;
            }
        }

        patronSvc.lastSearch = fullSearch;

        if (fullSearch.search.id) {
            // search by user id performs a direct ID lookup
            var userId = fullSearch.search.id.value;
            $timeout(
                function() {
                    egUser.get(userId).then(function(user) {
                        patronSvc.localFlesh(user);
                        patronSvc.patrons = [user];
                        deferred.notify(user);
                        deferred.resolve();
                    });
                }
            );
            return deferred.promise;
        }

        patronSvc.patrons = [];
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.search.advanced.fleshed',
            egCore.auth.token(), 
            fullSearch.search, 
            fullSearch.count,
            fullSearch.sort,
            fullSearch.inactive,
            fullSearch.home_ou,
            egUser.defaultFleshFields,
            fullSearch.offset

        ).then(
            function() { deferred.resolve() },
            null, // onerror
            function(user) {
                patronSvc.localFlesh(user); // inline
                patronSvc.patrons.push(user);
                deferred.notify(user);
            }
        );

        return deferred.promise;
    };

    $scope.patronSearchGridProvider = provider;

    // determine the tree depth of the profile group
    $scope.pgt_depth = function(grp) {
        var d = 0;
        while (grp = egCore.env.pgt.map[grp.parent()]) d++;
        return d;
    }

    $scope.clearForm = function () {
        $scope.searchArgs={};
        if (lastFormElement) lastFormElement.focus();
    }

    $scope.applyShowExtras = function($event, bool) {
        if (bool) {
            $scope.showExtras = true;
            egCore.hatch.setItem('eg.circ.patron.search.show_extras', true);
        } else {
            $scope.showExtras = false;
            egCore.hatch.removeItem('eg.circ.patron.search.show_extras');
        }
        if (lastFormElement) lastFormElement.focus();
        $event.preventDefault();
    }

    egCore.hatch.getItem('eg.circ.patron.search.show_extras')
    .then(function(val) {$scope.showExtras = val});

    // map form arguments into search params
    function compileSearch(args) {
        var search = {};
        angular.forEach(args, function(val, key) {
            if (!val) return;
            if (key == 'profile' && args.profile) {
                search.profile = {value : args.profile.id(), group : 0};
            } else if (key == 'home_ou' && args.home_ou) {
                search.home_ou = args.home_ou.id(); // passed separately
            } else if (key == 'inactive') {
                search.inactive = val;
            } else {
                search[key] = {value : val, group : 0};
            }
            if (key.match(/phone|ident/)) {
                search[key].group = 2;
            } else {
                if (key.match(/street|city|state|post_code/)) {
                    search[key].group = 1;
                } else if (key == 'card') {
                    search[key].group = 3
                }
            }
        });

        return search;
    }

    function compileSort() {

        if (!provider.sort.length) {
            return [ // default
                "family_name ASC",
                "first_given_name ASC",
                "second_given_name ASC",
                "dob DESC"
            ];
        }

        var sort = [];
        angular.forEach(
            provider.sort,
            function(sortdef) {
                if (angular.isObject(sortdef)) {
                    var name = Object.keys(sortdef)[0];
                    var dir = sortdef[name];
                    sort.push(name + ' ' + dir);
                } else {
                    sort.push(sortdef);
                }
            }
        );

        return sort;
    }

    $scope.setLastFormElement = function() {
        lastFormElement = $document[0].activeElement;
    }

    // search form submit action; tells the results grid to
    // refresh itself.
    $scope.search = function(args) { // args === $scope.searchArgs
        if (args && Object.keys(args).length) 
            $scope.gridControls.refresh();
        if (lastFormElement) lastFormElement.focus();
    }

    // TODO: move this into the (forthcoming) grid row activate action
    $scope.onPatronDblClick = function($event, user) {
        $location.path('/circ/patron/' + user.id() + '/checkout');
    }

    if (patronSvc.urlSearch) {
        // force the grid to load the url-based search on page load
        provider.refresh();
    }
   
}])

/**
 * Manages messages
 */
.controller('PatronMessagesCtrl',
       ['$scope','$q','$routeParams','egCore','$modal','patronSvc','egCirc',
function($scope , $q , $routeParams,  egCore , $modal , patronSvc , egCirc) {
    $scope.initTab('messages', $routeParams.id);
    var usr_id = $routeParams.id;

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
        $scope.retrievedWithInactive = patronSvc.retrievedWithInactive;
        $scope.invalidAddresses = patronSvc.invalidAddresses;
    });

}])

.controller('PatronNotesCtrl',
       ['$scope','$routeParams','$location','egCore','patronSvc','$modal',
function($scope,  $routeParams , $location , egCore , patronSvc , $modal) {
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
        $modal.open({
            templateUrl: './circ/patron/t_new_note_dialog',
            controller: 
                ['$scope', '$modalInstance',
            function($scope, $modalInstance) {
                $scope.focusNote = true;
                $scope.args = {};
                $scope.ok = function(count) { $modalInstance.close($scope.args) }
                $scope.cancel = function () { $modalInstance.dismiss() }
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
                egCore.pcrud.create(note).then(function() {refreshPage()});
            }
        );
    }

    // delete the selected note
    $scope.deleteNote = function(note) {
        egCore.pcrud.remove(note).then(function() {refreshPage()});
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
        'patronSvc','$modal','egPromptDialog','egConfirmDialog',
function($scope,  $routeParams , $q , $window , $timeout,  $location , egCore ,
         patronSvc , $modal , egPromptDialog , egConfirmDialog) {

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
        }
    }

    $scope.initTab('other', $routeParams.id)
    .then(function(redirect) {
        // if we are redirecting to the alerts page, avoid updating the
        // grid query.
        if (redirect) return;
        // let initTab() fetch the user first so we can know the usrgroup

        grid.setQuery({
            usrgroup : patronSvc.current.usrgroup(),
            deleted : 'f'
        });
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
                $modal.open({
                    templateUrl: './circ/patron/t_move_to_group_dialog',
                    controller: [
                                '$scope','$modalInstance',
                        function($scope , $modalInstance) {
                            $scope.user = user;
                            $scope.selected = selected;
                            $scope.outbound = outbound;
                            $scope.ok = 
                                function(count) { $modalInstance.close() }
                            $scope.cancel = 
                                function () { $modalInstance.dismiss() }
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

.controller('PatronFetchLastCtrl',
       ['$scope','$location','egCore',
function($scope , $location , egCore) {

    var id = egCore.hatch.getLocalItem('eg.circ.last_patron');
    if (id) return $location.path('/circ/patron/' + id + '/checkout');

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

