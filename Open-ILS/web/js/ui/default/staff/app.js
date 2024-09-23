/**
 * App to drive the base page. 
 * Login Form
 * Splash Page
 */

angular.module('egHome', ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod'])

.config(
       ['$routeProvider','$locationProvider',
function($routeProvider , $locationProvider) {
    $locationProvider.html5Mode(true);

    /**
     * Route resolvers allow us to run async commands
     * before the page controller is instantiated.
     */
    var resolver = {delay : ['egCore', 
        function(egCore) {return egCore.startup.go()}]};

    $routeProvider.when('/login', {
        templateUrl: './t_login',
        controller: 'LoginCtrl',
        resolve : resolver
    });

    $routeProvider.when('/about', {
        templateUrl: './t_about',
        controller: 'AboutCtrl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './t_splash',
        controller : 'SplashCtrl',
        resolve : resolver
    });
}])

/**
 * Login controller.  
 * Reads the login form and submits the login request
 */
.controller('LoginCtrl', 
    /* inject services into our controller.  Spelling them
     * out like this allows the auto-magic injector to work
     * even if the code has been minified */
           ['$scope','$location','$window','egCore','egLovefield',
    function($scope , $location , $window , egCore , egLovefield) {
        egLovefield.havePendingOfflineXacts() .then(
            function(eh){ $scope.pendingXacts = eh; },
            function() {} // SharedWorker not supported
        );

        $scope.focusMe = true;
        $scope.args = {};
        $scope.workstations = [];
		
		egCore.strings.setPageTitle(
            egCore.strings['PAGE_TITLE_LOGIN']);
			
        // if the user is already logged in, jump to splash page
        if (egCore.auth.user()) $location.path('/');

        egCore.hatch.getWorkstations()
        .then(function(all) {
            if (all && all.length) {
                $scope.workstations = all.map(function(a) { return a.name });

                if (ws = $location.search().ws) {
                    // user requested a workstation via URL
                    var match = all.filter(
                        function(w) {return ws == w.name} )[0];

                    if (match) {
                        // requested WS registered on this client
                        $scope.args = {workstation : match.name};
                    } else {
                        // the requested WS is not registered on this client
                        $scope.wsNotRegistered = true;
                    }
                } else {
                    // no workstation requested; use the default
                    egCore.hatch.getDefaultWorkstation()
                    .then(function(ws) {
                        $scope.args = {workstation : ws}
                    });
                }
            } 
        })

        $scope.login = function(args) {
            $scope.loginFailed = false;

            if (!args) args = {}; // see FF note below

            if (!args.username) {
                /* 
                 Issues with form autofill / auto-complete                          
                 https://github.com/angular/angular.js/issues/1460                  
                 http://timothy.userapp.io/post/63412334209/form-autocomplete-and-remember-password-with-angularjs
                 For now, since FF will save the values, we should 
                 honor them, even if it's hacky. */
                args.username = document.getElementById("login-username").value;
                args.password = document.getElementById("login-password").value;
            }

            if (! (args.username && args.password) ) return;

            // if at least one workstation exists, it must be used.
            if (!args.workstation && $scope.workstations.length > 0) return;

            args.type = 'staff';
            egCore.auth.login(args).then(

                function(result) { 
                    // After login, send the user to:
                    // 1. The WS admin page for WS maintenance.
                    // 2. The page originally requested by the caller
                    // 3. Home page.

                    // NOTE: using $location.path(...) results in
                    // confusing intermediate page loads, since
                    // path(...) is a setter function.  Build the URL by
                    // hand instead from the configured base path.
                    route_to = '/eg2/staff/splash';

                    // First, check for MFA
                    if (egCore.auth.provisional()) {
                        route_to = "/eg2/staff/mfa";
                    } else if (result.invalid_workstation) {
                        // route to WS admin page to delete the offending
                        // WS and create a new one.
                        route_to += 
                            'admin/workstation/workstations?remove=' 
                                + encodeURIComponent(args.workstation);

                    } else if ($location.search().route_to && $location.search().route_to !== '/eg/staff/') {
                        // Route to the originally requested page.
                        route_to = $location.search().route_to;
                    }

                    $window.location.href = route_to;
                },
                function() {
                    $scope.args.password = '';
                    $scope.loginFailed = true;
                    $scope.focusMe = true;
                }
            );
        }
    }
])

/**
 * Splash page dynamic content.
 */
.controller('SplashCtrl', ['$scope', '$window','egCore', 
    function($scope, $window,egCore) {

    $window.location.href = '/eg2/staff/';
}])

.controller('AboutCtrl', [
            '$scope','$location','egCore', 
    function($scope , $location , egCore) {

    $scope.context = {
        server : $location.host()
    }; 

    egCore.net.request(
        'open-ils.actor','opensrf.open-ils.system.ils_version')
        .then(function(version) {
            $scope.context.version = version;
        }
    );

	egCore.strings.setPageTitle(
        egCore.strings['PAGE_TITLE_ABOUT']);

}])

