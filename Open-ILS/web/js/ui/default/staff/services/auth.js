/* Core Sevice - egAuth
 *
 * Manages login and auth session retrieval.
 */

angular.module('egCoreMod')

.factory('egAuth', 
       ['$q','$timeout','$rootScope','$window','$location','egNet','egHatch','$injector',
function($q , $timeout , $rootScope , $window , $location , egNet , egHatch , $injector) {

    var egLovefield = null;

    var service = {
        // the currently active user (au) object
        user : function(u) {
            if (u) {
                this._user = u;
            }
            return this._user;
        },

        // the user hidden by an operator change
        OCuser : function(u) {
            if (u) {
                this._OCuser = u;
            }
            return this._OCuser;
        },

        // the Op Change hidden auth token string
        OCtoken : function() {
            return egHatch.getLoginSessionItem('eg.auth.token.oc');
        },

        // Op Change hidden authtime in seconds
        OCauthtime : function() {
            return egHatch.getLoginSessionItem('eg.auth.time.oc');
        },

        // the currently active auth token string
        token : function() {
            return egHatch.getLoginSessionItem('eg.auth.token');
        },

        // authtime in seconds
        authtime : function() {
            return egHatch.getLoginSessionItem('eg.auth.time');
        },

        // the currently active workstation name
        // For ws_ou or wsid(), see egAuth.user().ws_ou(), etc.
        workstation : function() {
            return this.ws;
        },

        // Is this session provisional?
        provisional : function() {
            return this.prov;
        },

        // Is this session provisional?
        mfaAllowed : function() {
            return this._mfa_allowed ? true : false;
        },

        // Listen for logout events in other tabs
        // Current version of phantomjs (unit tests, etc.) does not 
        // support BroadcastChannel, so just dummy it up.
        authChannel : (typeof BroadcastChannel == 'undefined') ? 
            {} : new BroadcastChannel('eg.auth')
    };

    /* Returns a promise, which is resolved if valid
     * authtoken is found, otherwise rejected */
    service.testAuthToken = function() {
        var deferred = $q.defer();

        // Move legacy cookies from /eg/staff to / before fetching the token.
        egHatch.migrateAuthCookies();

        var token = service.token();

        if (token) {

            if (lf.isOffline && !$location.path().match(/\/session/) ) {
                // Just stop here if we're in the offline interface but not on the session tab
                $timeout(function(){deferred.resolve()});
            } else if (lf.isOffline && $location.path().match(/\/session/) && !$window.navigator.onLine) {
                // Likewise, if we're in the offline interface on the session tab and the network is down.
                // The session tab itself will redirect appropriately due to no network.
                $timeout(function(){deferred.resolve()});
            } else {
                // Otherwise, check the token.  This will freeze all other interfaces, which is what we want.
                egNet.request(
                    'open-ils.auth',
                    'open-ils.auth.session.retrieve', token)
    
                .then(function(user) {
                    egNet.request(
                        'open-ils.auth_mfa',
                        'open-ils.auth_mfa.allowed_for_token',
                        token
                    ).then(function(res) {
                        // cache MFA allowed-ness whenever we have to fetch the session
                        service._mfa_allowed = Number(res) === 1;
                    }).then(function() {
                        if (user && user.classname) {
                            // authtoken test succeeded
                            service.user(user);
                            service.poll();
                            service.check_workstation(deferred);
                        } else {
                            // authtoken test failed
                            egHatch.clearLoginSessionItems();
                            deferred.reject();
                        }
                    });
                });
            }

        } else {
            // no authtoken to test
            deferred.reject('No authtoken found');
        }

        return deferred.promise;
    };

    service.check_workstation = function(deferred) {

        var user = service.user();
        var ws_path = '/admin/workstation/workstations';

        return egHatch.getItem('eg.workstation.all')
        .then(function(workstations) { 
            if (!workstations) workstations = [];

            // If the user is authenticated with a workstation, get the
            // name from the locally registered version of the workstation.

            if (user.wsid()) {

                var ws = workstations.filter(
                    function(w) {return w.id == user.wsid()})[0];

                if (ws) { // success
                    service.ws = ws.name;
                    deferred.resolve();
                    return;
                }
            }

            if ($location.path() == ws_path) {
                // User is on the workstation admin page.  No need
                // to redirect.
                deferred.resolve();
                return;
            }

            // At this point, the user is trying to access a page
            // besides the workstation admin page without a valid
            // registered workstation.  Send them back to the 
            // workstation admin page.

            // NOTE: egEnv also defines basePath, but we cannot import
            // egEnv here becuase it creates a circular reference.
            $window.location.href = '/eg2/staff' + ws_path;
            deferred.resolve();
        });
    }

    /**
     * Returns a promise, which is resolved on successful 
     * login and rejected on failed login.
     */
    service.login = function(args, ops) {
        // avoid modifying the caller's data structure.
        args = angular.copy(args);

        if (!ops) { // only set on redo attempts.
            ops = {deferred : $q.defer()};

            // Clear old LoginSession keys that were left in localStorage
            // when the previous user closed the browser without logging
            // out.  Under normal circumstance, LoginSession data would
            // have been cleared by now, either during logout or cookie
            // expiration.  But, if for some reason the user manually
            // removed the auth token cookie w/o closing the browser
            // (say, for testing), then this serves double duty to ensure
            // LoginSession data cannot persist across logins.
            egHatch.clearLoginSessionItems();
        }

        service.login_api(args).then(function(evt) {
            if (evt.textcode == 'SUCCESS') {
                service.handle_login_ok(args, evt);
                ops.deferred.resolve({
                    invalid_workstation : ops.invalid_workstation
                });

            } else if (evt.textcode == 'WORKSTATION_NOT_FOUND') {
                ops.invalid_workstation = true;
                delete args.workstation;
                service.login(args, ops); // redo w/o workstation

            } else {
                // note: the likely outcome here is a NO_SESION
                // server event, which results in broadcasting an 
                // egInvalidAuth by egNet. 
                console.error('login failed ' + js2JSON(evt));
                ops.deferred.reject();
            }
        });

        return ops.deferred.promise;
    }

    /**
     * Returns a promise, which is resolved on successful 
     * login and rejected on failed login.
     */
    service.opChange = function(args) {
        // avoid modifying the caller's data structure.
        args = angular.copy(args);
        args.workstation = service.workstation();

        var deferred = $q.defer();

        service.login_api(args).then(function(evt) {

            if (evt.textcode == 'SUCCESS') {
                if (args.type != 'persist') {
                    egHatch.setLoginSessionItem('eg.auth.token.oc', service.token());
                    egHatch.setLoginSessionItem('eg.auth.time.oc', service.authtime());
                    service.OCuser(service.user());
                }
                service.handle_login_ok(args, evt);
                service.testAuthToken().then(
                    deferred.resolve,
                    function () { service.opChangeUndo().then(deferred.reject)  }
                );
            } else {
                // note: the likely outcome here is a NO_SESION
                // server event, which results in broadcasting an 
                // egInvalidAuth by egNet. 
                console.error('operator change failed ' + js2JSON(evt));
                deferred.reject();
            }
        });

        return deferred.promise;
    }

    service.opChangeUndo = function() {
        if (service.OCtoken()) {
            service.user(service.OCuser());
            egHatch.setLoginSessionItem('eg.auth.token', service.OCtoken());
            egHatch.setLoginSessionItem('eg.auth.time', service.OCauthtime());
            egHatch.removeLoginSessionItem('eg.auth.token.oc');
            egHatch.removeLoginSessionItem('eg.auth.time.oc');
        }
        return service.testAuthToken();
    }

    service.login_via_auth_proxy = function(args) {
        return egNet.request(
            'open-ils.auth_proxy',
            'open-ils.auth_proxy.login', args);
    }

    service.login_via_auth = function(args) {
        return egNet.request(
            'open-ils.auth',
            'open-ils.auth.authenticate.init', args.username)
        .then(function(seed) {
                // avoid clobbering the bare password in case
                // we need it for a login redo attempt.
                var login_args = angular.copy(args);
                login_args.password = hex_md5(seed + hex_md5(args.password));

                return egNet.request(
                    'open-ils.auth',
                    'open-ils.auth.authenticate.complete', login_args)
            }
        );
    }

    service.login_api = function(args) {

        return egNet.request(
            'open-ils.auth_proxy',
            'open-ils.auth_proxy.enabled')
        .then(
            function(enabled) {
                console.log('proxy check returned ' + enabled);
                if (Number(enabled) === 1) {
                    return service.login_via_auth_proxy(args);
                } else {
                    return service.login_via_auth(args);
                }
            },
            function() {
                // request failed, likely a result of auth_proxy not running.
               return service.login_via_auth(args);
            }
        );
    }

    service.handle_login_ok = function(args, evt) {
        if (!egLovefield) {
            egLovefield = $injector.get('egLovefield');
        }
        service.prov = evt.payload.provisional; 
        service.ws = args.workstation; 
        if (service.prov) {
            egHatch.setLoginSessionItem('eg.auth.token.provisional', evt.payload.authtoken);
            egHatch.setLoginSessionItem('eg.auth.time.provisional', evt.payload.authtime);
        } else {
            egHatch.setLoginSessionItem('eg.auth.token', evt.payload.authtoken);
            egHatch.setLoginSessionItem('eg.auth.time', evt.payload.authtime);
            service.poll();
        }
        egLovefield.destroySettingsCache(); // force refresh of settings cache on login (LP#1848550)
    }

    /**
     * Force-check the validity of the authtoken on occasion. 
     * This allows us to redirect an idle staff client back to the login
     * page after the session times out.  Otherwise, the UI would stay
     * open with potentially sensitive data visible.
     * TODO: What is the practical difference (for a browser) between 
     * checking auth validity and the ui.general.idle_timeout setting?
     * Does that setting serve a purpose in a browser environment?
     */
    service.poll = function() {

        if (!service.authChannel.onmessage) {
            // Now that we have an authtoken, listen for logout events 
            // initiated by other tabs.
            service.authChannel.onmessage = function(e) {
                if (e.data.action == 'logout') {
                    $rootScope.$broadcast(
                        'egAuthExpired', {startedElsewhere : true});
                }
            }
        }

        // Check every 3 minutes. This still won't reset the authtoken timeout
        // but it WILL reset the memcached LRU for the authtoken so staff authtokens
        // are less likely to be evicted.
        var pollTime = 60 * 1000 * 3;

        $timeout(
            function() {
                egNet.request(                                                     
                    'open-ils.auth',                                               
                    'open-ils.auth.session.retrieve', 
                    service.token(),
                    0, // return extra auth details, unneeded here.
                    1  // avoid extending the auth timeout
                ).then(function(user) {
                    if (user && user.classname) { // all good
                        service.poll();
                    } else {
                        // NOTE: we should never get here, since egNet
                        // filters responses for NO_SESSION events.
                        $rootScope.$broadcast('egAuthExpired');
                    }
                })
            },
            pollTime
        );
    }

    service.logout = function(broadcast) {

        if (broadcast && service.authChannel.postMessage) {
            // Tell the other tabs to shut it all down.
            service.authChannel.postMessage({action : 'logout'});
        }

        if (service.token()) {
            egNet.request(
                'open-ils.auth', 
                'open-ils.auth.session.delete', 
                service.token()); // fire and forget
            egHatch.clearLoginSessionItems();
        }
        service._user = null;
    };

    return service;
}])


/**
 * Service for testing user permissions.
 * Note: this cannot live within egAuth, because it creates a circular
 * dependency of egOrg -> egEnv -> egAuth -> egOrg
 */
.factory('egPerm', 
       ['$q','egNet','egAuth','egOrg',
function($q , egNet , egAuth , egOrg) {
    var service = {};

    /*
     * Returns the full list of org unit objects at which the currently
     * logged in user has the selected permissions.
     * @permList - list or string.  If a list, the response object is a
     * hash of perm => orgList maps.  If a string, the response is the
     * org list for the requested perm.
     */
    service.hasPermAt = function(permList, asId) {
        if (!egAuth.token()) { return $q.when([]) };
        var deferred = $q.defer();
        var isArray = true;
        if (!angular.isArray(permList)) {
            isArray = false;
            permList = [permList];
        }
        // as called, this method will return the top-most org unit of the
        // sub-tree at which this user has the selected permission.
        // From there, flesh the descendant orgs locally.
        egNet.request(
            'open-ils.actor',
            'open-ils.actor.user.has_work_perm_at.batch',
            egAuth.token(), permList
        ).then(function(resp) {
            var answer = {};
            angular.forEach(permList, function(perm) {
                var all = [];
                angular.forEach(resp[perm], function(oneOrg) {
                    all = all.concat(egOrg.descendants(oneOrg, asId));
                });
                answer[perm] = all;
            });
            if (!isArray) answer = answer[permList[0]];
            deferred.resolve(answer);
        });
       return deferred.promise;
    };


    /**
     * Returns a hash of perm => hasPermBool for each requested permission.
     * If the authenticated user has no workstation, no checks are made
     * and all permissions return false.
     */
    service.hasPermHere = function(permList) {
        var response = {};

        var isArray = true;
        if (!angular.isArray(permList)) {
            isArray = false;
            permList = [permList];
        }

        // no workstation, all are false
        if (egAuth.user().wsid() === null) {
            console.warn("egPerm.hasPermHere() called with no workstation");
            if (isArray) {
                response = permList.map(function(perm) {
                    return response[perm] = false;
                });
            } else {
                response = false;
            }
            return $q.when(response);
        }

        ws_ou = Number(egAuth.user().ws_ou()); // from string

        return service.hasPermAt(permList, true)
        .then(function(orgMap) {
            angular.forEach(orgMap, function(orgIds, perm) {
                // each permission is mapped to a flat list of org unit ids,
                // including descendants.  See if our workstation org unit
                // is in the list.
                response[perm] = orgIds.indexOf(ws_ou) > -1;
            });
            if (!isArray) response = response[permList[0]];
            return response;
        });
    }

    /*
     * Returns a union of the full org path of each org unit at which the
     * currently logged in user has the selected permissions.
     * @permList - list or string.  Unlike hasPermAt, the response object
     * is always a list of org ids (or an empty list).
     */
    service.hasPermFullPathAt = function(permList) {
        return service.hasPermAt(permList, true)
        .then(function(orgs) {
            var orgHash = {};
            if (permList.constructor != Array) {
                orgHash[permList] = orgs;
            } else {
                orgHash = orgs;
            }
            var org_seen = {};
            angular.forEach(orgHash, function(orgList) {
                angular.forEach(orgList, function(org) {
                    var full_path = egOrg.fullPath(org,true);
                    angular.forEach(full_path, function(org2) {
                        org_seen[org2] = true;
                    });
                });
            });
            return Object.keys(org_seen).map(function(o) { return Number(o); });
        });
    }

    return service;
}])


