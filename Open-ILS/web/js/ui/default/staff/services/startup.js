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

.config(['$locationProvider','$compileProvider',
 function($locationProvider , $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/);
}])

.factory('egStartup', 
       ['$q','$rootScope','$location','$window','egIDL','egAuth','egEnv','egOrg',
        '$cookies',
function($q,  $rootScope,  $location,  $window,  egIDL,  egAuth,  egEnv , egOrg ,
         $cookies) {

    var service = { promise : null }

    // Some org settings affect every page.  Load them during startup.  
    // Other startup data loaders can be added by appending to egEnv.loaders.
    // egEnv.loaders functions must return a promise.
    egEnv.loaders.push(
        function() {
            return egOrg.settings([
                'webstaff.format.dates',
                'webstaff.format.date_and_time',
                'ui.staff.max_recent_patrons', // affects navbar
                'ui.staff.angular_catalog.enabled', // affects navbar
                'lib.timezone'
            ]).then(
                function(set) {
                    $rootScope.egDateFormat = 
                        set['webstaff.format.dates'] || 'shortDate';
                    $rootScope.egDateAndTimeFormat = 
                        set['webstaff.format.date_and_time'] || 'short';

                    // default to 1 for backwards compat.
                    if (set['ui.staff.max_recent_patrons'] === null)
                        set['ui.staff.max_recent_patrons'] = 1
                }
            );
        }
    );

    // returns true if we are staying on the current page
    // false if we are redirecting to login
    service.expiredAuthHandler = function(data) {
        if (lf.isOffline) return true; // Only set by the offline UI

        console.debug('egStartup.expiredAuthHandler()');

        // Only notify other tabs the auth session has expired 
        // when this tab was the first tab to know it.
        var broadcast = !(data && data.startedElsewhere);

        egAuth.logout(broadcast); // clean up

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

        // Apply the locale from the cookie before any network 
        // calls are made.
        var locale = $cookies.get('eg_locale');
        if (locale) {
            // Cookie is stored aa_bb.  OpenSRF wants aa-BB
            var parts = locale.split(/_/);
            OpenSRF.locale = parts[0] + '-' + parts[1].toUpperCase();
            console.debug('Applying locale ' + OpenSRF.locale);
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

