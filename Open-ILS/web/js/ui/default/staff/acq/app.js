angular.module('egAcquisitions',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame allow-escape="true" min-height="min_height" url="acq_url" handlers="funcs"></eg-embed-frame>';

    $routeProvider.when('/acq/legacy/:noun/:verb', {
        template: eframe_template,
        controller: 'EmbedAcqCtl',
        resolve : resolver
    });

    $routeProvider.when('/acq/legacy/:noun/:verb/:record', {
        template: eframe_template,
        controller: 'EmbedAcqCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './t_splash',
        resolve : resolver
    });
}])

.controller('EmbedAcqCtl', 
       ['$scope','$routeParams','$location','$window','$timeout','egCore',
function($scope , $routeParams , $location , $window , $timeout , egCore) {

    var relay_url = function(url) {
        if (url.match(/\/eg\/acq/)) {
            var munged_url = egCore.env.basePath + 
                url.replace(/^.*?\/eg\/acq\//, "acq/legacy/");
            $timeout(function() { $window.open(munged_url, '_blank') });
        } else if (url.match(/\/eg\/vandelay/)) {
            var munged_url = egCore.env.basePath + 
                url.replace(/^.*?\/eg\/vandelay\/vandelay/, "cat/catalog/vandelay");
            $timeout(function() { $window.open(munged_url, '_blank') });
        }
    }

    // minimal version sufficient to update copy barcodes
    var volume_item_creator = function(params) {
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {
                copies: params.existing_copies.map(function(acp) { return acp.id(); }),
                raw: [],
                hide_vols : false,
                hide_copies : false
            }
        ).then(function(key) {
            if (key) {
                var url = egCore.env.basePath + 'cat/volcopy/' + key;
                $timeout(function() { $window.open(url, '_blank') });
            } else {
                alert('Could not create anonymous cache key!');
            }
        });
    }

    $scope.funcs = {
        ses : egCore.auth.token(),
        relay_url : relay_url,
        volume_item_creator : volume_item_creator
    }

    var acq_path = '/eg/acq/' + 
        $routeParams.noun + '/' + $routeParams.verb +
        ((typeof $routeParams.record != 'undefined') ? '/' + $routeParams.record : '') +
        location.search;

    $scope.min_height = 2000; // give lots of space to start

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.acq_url = 
        $location.absUrl().replace(/\/eg\/staff.*/, acq_path);

    console.log('Loading Acq URL: ' + $scope.acq_url);

}])

