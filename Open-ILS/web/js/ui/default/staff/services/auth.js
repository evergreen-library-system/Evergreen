/* Core Sevice - egAuth
 *
 * Manages login and auth session retrieval.
 */

angular.module('egCoreMod')

.factory('egAuth', 
       ['$q','$timeout','$rootScope','egNet','egHatch', 
function($q , $timeout , $rootScope , egNet , egHatch) {

    var service = {
        // the currently active user (au) object
        user : function() {
            return this._user;
        },

        // the currently active auth token string
        token : function() {
            return egHatch.getLocalItem('eg.auth.token');
        },

        // authtime in seconds
        authtime : function() {
            return egHatch.getLocalItem('eg.auth.time');
        },

        // the currently active workstation name
        // For ws_ou or wsid(), see egAuth.user().ws_ou(), etc.
        workstation : function() {
            return this.ws;
        }
    };

    /* Returns a promise, which is resolved if valid
     * authtoken is found, otherwise rejected */
    service.testAuthToken = function() {
        var deferred = $q.defer();
        var token = service.token();

        if (token) {

            egNet.request(
                'open-ils.auth',
                'open-ils.auth.session.retrieve', token)

            .then(function(user) {
                if (user && user.classname) {
                    // authtoken test succeeded
                    service._user = user;
                    service.poll();
                   
                    if (user.wsid()) {
                        // user previously logged in with a workstation. 
                        // Find the workstation name from the list 
                        // of configured workstations
                        egHatch.getItem('eg.workstation.all')
                        .then(function(all) { 
                            if (all) {
                                var ws = all.filter(
                                    function(w) {return w.id == user.wsid()})[0];
                                if (ws) service.ws = ws.name;
                            }
                            deferred.resolve(); // found WS
                        });
                    } else {
                        deferred.resolve(); // no WS
                    }
                } else {
                    // authtoken test failed
                    egHatch.removeLocalItem('eg.auth.token');
                    deferred.reject(); 
                }
            });

        } else {
            // no authtoken to test
            deferred.reject();
        }

        return deferred.promise;
    };

    /**
     * Returns a promise, which is resolved on successful 
     * login and rejected on failed login.
     */
    service.login = function(args) {
        var deferred = $q.defer();
        egNet.request(
            'open-ils.auth',
            'open-ils.auth.authenticate.init', args.username).then(
            function(seed) {
                args.password = hex_md5(seed + hex_md5(args.password))
                egNet.request(
                    'open-ils.auth',
                    'open-ils.auth.authenticate.complete', args).then(
                    function(evt) {
                        if (evt.textcode == 'SUCCESS') {
                            service.ws = args.workstation; 
                            service.poll();
                            egHatch.setLocalItem(
                                'eg.auth.token', evt.payload.authtoken);
                            egHatch.setLocalItem(
                                'eg.auth.time', evt.payload.authtime);
                            deferred.resolve();
                        } else {
                            // note: the likely outcome here is a NO_SESION
                            // server event, which results in broadcasting an 
                            // egInvalidAuth by egNet. 
                            console.error('login failed ' + js2JSON(evt));
                            deferred.reject();
                        }
                    }
                )
            }
        );

        return deferred.promise;
    };

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
        if (!service.authtime()) return;

        $timeout(
            function() {
                if (!service.authtime()) return;
                egNet.request(                                                     
                    'open-ils.auth',                                               
                    'open-ils.auth.session.retrieve', service.token())   
                .then(function(user) {
                    if (user && user.classname) { // all good
                        service.poll();
                    } else {
                        $rootScope.$broadcast('egAuthExpired') 
                    }
                })
            },
            // add a 5 second delay to give the token plenty of time
            // to expire on the server.
            service.authtime() * 1000 + 5000
        );
    }

    service.logout = function() {
        if (service.token()) {
            egNet.request(
                'open-ils.auth', 
                'open-ils.auth.session.delete', 
                service.token()); // fire and forget
            egHatch.removeLocalItem('eg.auth.token');
            egHatch.removeLocalItem('eg.auth.time');
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

    return service;
}])


