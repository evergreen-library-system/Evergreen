/**
 * Core Service - egStartup
 *
 * Coordinates all startup routines and consolidates them into
 * a single startup promise.  Startup can be launched from multiple
 * controllers, etc., but only one startup routine will be run.
 *
 * If no valid authtoken is found, startup will exit early and 
 * change the page href to the login page.  Otherwise, the global
 * promise returned by startup.go() will be resolved after all
 * async data is arrived.
 */

angular.module('egCoreMod')

.factory('egStartup', 
       ['$q','$rootScope','$location','$window','egIDL','egAuth','egEnv',
function($q,  $rootScope,  $location,  $window,  egIDL,  egAuth,  egEnv) {

    var service = { promise : null }

    // returns true if we are staying on the current page
    // false if we are redirecting to login
    service.expiredAuthHandler = function() {
        console.debug('egStartup.expiredAuthHandler()');
        egAuth.logout(); // clean up

        // no need to redirect if we're on the /login page
        if ($location.path() == '/login') return true;

        // change locations to the login page, using the current page
        // as the 'route_to' destination on /login
        $window.location.href = $location
            .path('/login')
            .search({route_to : 
                $window.location.pathname + $window.location.search})
            .absUrl();

        return false;
    }

    // if during startup or any time in the future we encounter an expired
    // authtoken, call our epired token handler
    // we handle this here instead egAuth, since it affects the flow
    // of the startup routines when no valid token exists during startup.
    $rootScope.$on('egAuthExpired', function() {service.expiredAuthHandler()});

    service.go = function () {
        if (service.promise) {
            // startup already started, return our existing promise
            return service.promise;
        } 

        // create a new promise and fire off startup
        var deferred = $q.defer();
        service.promise = deferred.promise;

        // IDL parsing is sync.  No promises required
        egIDL.parseIDL();
        egAuth.testAuthToken().then(

            // testAuthToken resolved
            function() { 
                egEnv.load().then(
                    function() { deferred.resolve() }, 
                    function() { 
                        deferred.reject('egEnv did not resolve')
                    }
                );
            },

            // testAuthToken rejected
            function() { 
                console.log('egAuth found no valid authtoken');
                if (service.expiredAuthHandler()) deferred.resolve();
            }
        );

        return service.promise;
    }
    
    return service;
}]);

