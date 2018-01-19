angular.module('egAcquisitions',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod','egMarcMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
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
       ['$scope','$routeParams','$location','$window','$timeout','egCore','$uibModal',
function($scope , $routeParams , $location , $window , $timeout , egCore , $uibModal) {

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

    var edit_marc_order_record = function(li, callback) {
        var args = {
            'marc_xml' : li.marc()
        };
        $uibModal.open({
            templateUrl: './acq/t_edit_marc_order_record',
            size: 'lg',
            backdrop: 'static',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.args = args;
                $scope.dirty_flag = false;
                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            li.marc(args.marc_xml);
            egCore.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem.update',
                egCore.auth.token(),
                li
            ).then(function() {
                callback(li);
            });
        });
    }

    $scope.funcs = {
        ses : egCore.auth.token(),
        relay_url : relay_url,
        volume_item_creator : volume_item_creator,
        edit_marc_order_record : edit_marc_order_record
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

