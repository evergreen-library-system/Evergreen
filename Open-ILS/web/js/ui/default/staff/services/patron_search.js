/**
 * Patron Search module
 */

angular.module('egPatronSearchMod', ['ngRoute', 'ui.bootstrap', 
    'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod'])

/**
 * Patron service
 */
.factory('patronSvc',
       ['$q','$timeout','$location','egCore','egUser','egConfirmDialog','$locale',
function($q , $timeout , $location , egCore,  egUser , egConfirmDialog , $locale) {

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
        //holds the searched barcode
        search_barcode : null,      
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
        service.patronExpired = false;
        service.patronExpiresSoon = false;
        service.invalidAddresses = false;
    }
    service.resetPatronLists();  // initialize

    egCore.startup.go().then(
        function() {
            // Max recents setting is loaded and scrubbed during egStartup.
            // Copy it to a local variable here for ease of local access
            // after startup has run.
            egCore.org.settings('ui.staff.max_recent_patrons')
            .then(function(s) {
                service.maxRecentPatrons = s['ui.staff.max_recent_patrons'];
            });

            // This call requires orgs to be loaded, because it
            // calls egCore.org.ancestors(), so call it after startup
            egCore.pcrud.search('actsc',
                {owner : egCore.org.ancestors(
                    egCore.auth.user().ws_ou(), true)},
                {}, {atomic : true}
            ).then(function(cats) {
                egCore.env.absorbList(cats, 'actsc');
            });
        }
    );

    // Returns true if the last alerted patron matches the current
    // patron.  Otherwise, the last alerted patron is set to the 
    // current patron and false is returned.
    service.alertsShown = function() {
        var key = 'eg.circ.last_alerted_patron';
        var last_id = egCore.hatch.getSessionItem(key);
        if (last_id && last_id == service.current.id()) return true;
        egCore.hatch.setSessionItem(key, service.current.id());
        return false;
    }

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

    service.getRecentPatrons = function() {
        // avoid getting stuck in a show-recent loop
        service.showRecent = false;

        if (service.maxRecentPatrons < 1) return $q.when();
        var patrons = 
            egCore.hatch.getLoginSessionItem('eg.circ.recent_patrons') || [];

        // Ensure the cached list is no bigger than the current config.
        // This can happen if the setting changes while logged in.
        patrons = patrons.slice(0, service.maxRecentPatrons);

        // add home_ou to the list of fleshed fields for recent patrons
        var fleshFields = egUser.defaultFleshFields.slice(0);
        fleshFields.push('home_ou');

        var deferred = $q.defer();
        function getNext() {
            if (patrons.length == 0) {
                deferred.resolve();
                return;
            }
            egUser.get(patrons[0], {useFields : fleshFields}).then(
                function(usr) { // fetch first user
                    deferred.notify(usr);
                    patrons.splice(0, 1); // remove first user from list
                    getNext();
                }
            );
        }

        getNext();
        return deferred.promise;
    }

    service.addRecentPatron = function(user_id) {
        if (service.maxRecentPatrons < 1) return;

        // ensure ID is a number if pulled from route data
        user_id = Number(user_id);

        // no need to re-track same user
        if (service.current && service.current.id() == user_id) return;

        var patrons = 
            egCore.hatch.getLoginSessionItem('eg.circ.recent_patrons') || [];

        // remove potential existing duplicates
        patrons = patrons.filter(function(id) {
            return user_id !== id
        });
        patrons.splice(0, 0, user_id);  // put this user at front
        patrons.splice(service.maxRecentPatrons); // remove excess

        egCore.hatch.setLoginSessionItem('eg.circ.recent_patrons', patrons);
    }

    // sets the primary display user, fetching data as necessary.
    service.setPrimary = function(id, user, force) {
        var user_id = id ? id : (user ? user.id() : null);

        console.debug('setting primary user to: ' + user_id);

        if (!user_id) return $q.reject();

        service.addRecentPatron(user_id);

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
            service.checkAlerts();
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

            return service.checkOptIn(user).then(
                function() {
                    service.current = user;
                    service.localFlesh(user);
                    return service.fetchUserStats();
                },
                function() {
                    return $q.reject();
                }
            );

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
                    return service.checkOptIn(user).then(
                        function() {
                            service.current = user;
                            service.localFlesh(user);
                            return service.fetchUserStats();
                        },
                        function() {
                            return $q.reject();
                        }
                    );
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
                    // clone the org unit IDL object and set children to an empty array
                    org_unit = egCore.idl.Clone(egCore.org.get(penalty.org_unit()));
                    org_unit.children([])
                    penalty.org_unit(org_unit);
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
    //resolves to true if the patron was fetched with an inactive card
    service.fetchedWithInactiveCard = function() {
        var bc = service.search_barcode
        var cards = service.current.cards();
        var card = cards.filter(function(c) { return c.barcode() == bc })[0];
        return (card && card.active() == 'f');
    }   
    // resolves to true if there is any aspect of the patron account
    // which should produce a message in the alerts panel
    service.checkAlerts = function() {

        if (service.hasAlerts) // already checked
            return $q.when(true); 

        var deferred = $q.defer();
        var p = service.current;

        if (service.alert_penalties.length ||
            p.active() == 'f' ||
            p.barred() == 't' ||
            service.patron_stats.holds.ready) {

            service.hasAlerts = true;
        }

        // see if the user was retrieved with an inactive card
        if(service.fetchedWithInactiveCard()){
            service.hasAlerts = true;
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

                stats.checkouts.total_out += Number(stats.checkouts.long_overdue);

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

    service.createOptIn = function(user_id) {
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.org_unit_opt_in.create',
            egCore.auth.token(), user_id);
    }

    service.checkOptIn = function(user) {
        var deferred = $q.defer();
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.org_unit_opt_in.check',
            egCore.auth.token(), user.id())
        .then(function(optInResp) {
            if (eg_evt = egCore.evt.parse(optInResp)) {
                deferred.reject();
                console.log('error on opt-in check: ' + eg_evt);
            } else if (optInResp == 2) {
                // opt-in disallowed at this location by patron's home library
                deferred.reject();
                alert(egCore.strings.OPT_IN_RESTRICTED);
            } else if (optInResp == 1) {
                // opt-in handled or not needed, do nothing
                deferred.resolve();
            } else {
                // opt-in needed, show the opt-in dialog
                var org = egCore.org.get(user.home_ou());
                egConfirmDialog.open(
                    egCore.strings.OPT_IN_DIALOG_TITLE,
                    egCore.strings.OPT_IN_DIALOG,
                    {   family_name : user.family_name(),
                        first_given_name : user.first_given_name(),
                        org_name : org.name(),
                        org_shortname : org.shortname(),
                        ok : function() {
                            service.createOptIn(user.id())
                            .then(function(resp) {
                                if (evt = egCore.evt.parse(resp)) {
                                    deferred.reject();
                                    alert(evt);
                                } else {
                                    deferred.resolve();
                                }
                            });
                        },
                        cancel : function() { deferred.reject(); }
                    }
                );
            }
        });
        return deferred.promise;
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
 * Manages patron search
 */
.controller('BasePatronSearchCtrl',
       ['$scope','$q','$routeParams','$timeout','$window','$location','egCore',
       '$filter','egUser', 'patronSvc','egGridDataProvider','$document',
       'egProgressDialog',
function($scope,  $q,  $routeParams,  $timeout,  $window,  $location,  egCore,
        $filter,  egUser,  patronSvc , egGridDataProvider , $document,
        egProgressDialog) {

    $scope.focusMe = true;
    $scope.searchArgs = {
        // default to searching globally
        home_ou : egCore.org.tree()
    };

    // last used patron search form element
    var lastFormElement;

    $scope.gridControls = {
        selectedItems : function() {return []}
    }

    // The first time we encounter the show-recent CGI param, put the
    // service into show-recent mode.  The first time recents are shown,
    // the service is taken out of show-recent mode so the page does not
    // get stuck in a show-recent loop.
    if (patronSvc.showRecent === undefined 
        && Boolean($location.path().match(/search/))
        && Boolean($location.search().show_recent)) {
        patronSvc.showRecent = true;
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

        // include inactive patrons if "inactive" param
        if ($location.search().inactive) {
            patronSvc.urlSearch.inactive = $location.search().inactive;
        }
    }

    var propagate;
    var propagate_inactive;
    if (patronSvc.lastSearch && !patronSvc.showRecent) {
        propagate = patronSvc.lastSearch.search;
        // home_ou needs to be treated specially
        propagate.home_ou = {
            value : patronSvc.lastSearch.home_ou,
            group : 0
        };
    } else if (patronSvc.urlSearch) {
        propagate = patronSvc.urlSearch.search;
        if (patronSvc.urlSearch.inactive) {
            propagate_inactive = patronSvc.urlSearch.inactive;
        }
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
                val.value = $scope.profiles.filter(function(p) { return p.id() == val.value })[0];
            if (key == 'home_ou')
                val.value = egCore.org.get(val.value);
            $scope.searchArgs[key] = val.value;
        });
        if (propagate_inactive) {
            $scope.searchArgs.inactive = propagate_inactive;
        }
    }

    var provider = egGridDataProvider.instance({});

    provider.get = function(offset, count) {
        var deferred = $q.defer();

        if (patronSvc.showRecent) {
            // avoid getting stuck in show-recent mode
            return patronSvc.getRecentPatrons();
        }

        var fullSearch;
        if (patronSvc.urlSearch) {
            fullSearch = patronSvc.urlSearch;
            // enusre the urlSearch only runs once.
            delete patronSvc.urlSearch;

        } else {
            patronSvc.search_barcode = $scope.searchArgs.card;
            
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

        if (!Object.keys(fullSearch.search).length) {
            // Empty searches are rejected by the server.  Avoid 
            // running the the empty search that runs on page load. 
            return $q.when();
        }

        var fleshFields = egUser.defaultFleshFields.slice(0);
        if (fleshFields.indexOf('profile') == -1)
            fleshFields.push('profile');

        egProgressDialog.open(); // Indeterminate

        patronSvc.patrons = [];
        var which_sound = 'success';
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.search.advanced.fleshed',
            egCore.auth.token(), 
            fullSearch.search, 
            fullSearch.count,
            fullSearch.sort,
            fullSearch.inactive,
            fullSearch.home_ou,
            fleshFields,
            fullSearch.offset

        ).then(
            function() {
                deferred.resolve();
            },
            function() { // onerror
                which_sound = 'error';
            },
            function(user) {
                // hide progress bar as soon as the first result appears.
                egProgressDialog.close();
                patronSvc.localFlesh(user); // inline
                patronSvc.patrons.push(user);
                deferred.notify(user);
            }
        )['finally'](function() { // close on 0-hits or error
            if (which_sound == 'success' && patronSvc.patrons.length == 0) {
                which_sound = 'warning';
            }
            egCore.audio.play(which_sound + '.patron.by_search');
            egProgressDialog.close();
        });

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
        var inactive = $scope.searchArgs.inactive;
        var home_ou = egCore.org.tree();
        $scope.searchArgs = {
            home_ou: home_ou,
            inactive: inactive
        };
        egCore.hatch.setItem('eg.circ.patron.search.ou', home_ou);
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

    // check searchArgs.inactive setting
    egCore.hatch.getItem('eg.circ.patron.search.include_inactive')
                .then(function(searchInactive){
                    if (searchInactive) $scope.searchArgs.inactive = searchInactive;
                });

    egCore.hatch.getItem('eg.circ.patron.search.ou').then(function(cachedHomeOu) {
        $scope.searchArgs.home_ou = cachedHomeOu || egCore.org.tree();
        // Once done, mark ourselves as ready
        $scope.initialized = true;
        });

     $scope.onSearchInactiveChanged = function() {
        egCore.hatch.setItem('eg.circ.patron.search.include_inactive', $scope.searchArgs.inactive);
    }

    // Then watch the home_ou for actual user changes
    $scope.$watch('searchArgs.home_ou', function(newVal, oldVal) {
        // If not initialized, ignore. The first assignment is from the cached value.
        if (!$scope.initialized) return;
        if (newVal !== oldVal) {
        egCore.hatch.setItem(
            'eg.circ.patron.search.ou',
            $scope.searchArgs.home_ou
        );
        }
    });

    // map form arguments into search params
    function compileSearch(args) {
        var search = {};
        angular.forEach(args, function(val, key) {
            if (!val) return;
            if (key == 'profile' && args.profile) {
                search.profile = {value : args.profile.id(), group : 5};
            } else if (key == 'home_ou' && args.home_ou) {
                search.home_ou = args.home_ou.id();
            } else if (key == 'inactive') {
                search.inactive = val;
            } else if (key == 'name') { // name keywords search
                search.name = {value: val};
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
                } else if (key.match(/dob_/)) {
                    // DOB should always be numeric
                    search[key].value = search[key].value.replace(/\D/g,'');
                    if (search[key].value.length == 0) {
                        delete search[key];
                    }
                    else {
                        if (!key.match(/year/)) {
                            search[key].value = ('0'+search[key].value).slice(-2);
                        }
                        search[key].group = 4;
                    }
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

    $scope.need_two_selected = function() {
        var items = $scope.gridControls.selectedItems();
        return (items.length == 2) ? false : true;
    }
   
}])

