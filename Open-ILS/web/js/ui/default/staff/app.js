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
           ['$scope','$location','$window','egCore',
    function($scope , $location , $window , egCore) {
        $scope.focusMe = true;

        // if the user is already logged in, jump to splash page
        if (egCore.auth.user()) $location.path('/');

        egCore.hatch.getItem('eg.workstation.all')
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
                    egCore.hatch.getItem('eg.workstation.default')
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

            args.type = 'staff';
            egCore.auth.login(args).then(

                function() { 
                    // after login, send the user back to the originally
                    // requested page or, if none, the home page.
                    // TODO: this is a little hinky because it causes 2 
                    // redirects if no route_to is defined.  Improve.
                    $window.location.href = 
                        $location.search().route_to || 
                        $location.path('/').absUrl()
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
.controller('SplashCtrl', ['$scope',
    function($scope) {
        console.log('SplashCtrl');
    }
]);

