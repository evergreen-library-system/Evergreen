angular.module('egAcqAdmin',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/admin/acq/edi_attr_set', {
        templateUrl: './admin/acq/t_edi_attr_set',
        controller: 'EDIAttrSet',
        resolve : resolver
    });

    var eframe_template = 
        '<eg-embed-frame allow-escape="true" min-height="min_height" url="acq_admin_url" handlers="funcs"></eg-embed-frame>';

    $routeProvider.when('/admin/acq/:noun/:verb/:extra?', {
        template: eframe_template,
        controller: 'EmbedAcqCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/acq/t_splash',
        resolve : resolver
    });
}])

.controller('EmbedAcqCtl',
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }

    var acq_path = '/eg/';

    if ($routeParams.noun == 'conify') {
        acq_path += 'conify/global/acq/' + $routeParams.verb
            + (typeof $routeParams.extra != 'undefined'
                ? '/' + $routeParams.extra
                : '')
            + location.search;
    } else {
        acq_path += 'acq/'
            + $routeParams.noun + '/' + $routeParams.verb
            + (typeof $routeParams.extra != 'undefined'
                ? '/' + $routeParams.extra
                : '')
            + location.search;
    }

    $scope.min_height = 2000; // give lots of space to start

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.acq_admin_url =
        $location.absUrl().replace(/\/eg\/staff.*/, acq_path);

    console.log('Loading Admin Acq URL: ' + $scope.acq_admin_url);

}])

.controller('EDIAttrSet',
       ['$scope','$q','egCore','ngToast','egConfirmDialog',
function($scope , $q , egCore , ngToast , egConfirmDialog) {
    
    $scope.cur_attr_set = null;

    // fetch all the data needed to render the page.
    function load_data() {

        return egCore.pcrud.retrieveAll('aea', {}, 
            {atomic : true, authoritative : true})
        .then(
            function(attrs) { 
                $scope.attrs = attrs 
                return egCore.pcrud.retrieveAll('aeas', 
                    {flesh : 1, flesh_fields : {'aeas' : ['attr_maps']}}, 
                    {atomic : true, authoritative : true}
                )
            }

        ).then(function(sets) { 
            $scope.attr_sets = sets.sort(function(a, b) {
                return a.label() < b.label() ? -1 : 1;
            });

            // create a simple true/false attr_set => attr mapping
            var select_me;
            angular.forEach(sets, function(set) {
                set._local_map = {};
                angular.forEach(set.attr_maps(), function(map) {
                    set._local_map[map.attr()] = true;
                })

                if ($scope.cur_attr_set && set.id() 
                        == $scope.cur_attr_set.id()) {
                    select_me = set;
                }
            });

            $scope.select_set(select_me || $scope.attr_sets[0]);
        });
    }

    function create_sets() {
        var new_sets = $scope.attr_sets.filter(function(set) { 
            if (set.isnew() && set.label()) {
                console.debug('creating new set: ' + set.label());
                return true;
            } 
            return false;
        });

        if (new_sets.length == 0) return $q.when();

        // create the new attrs sets and collect the newly generated 
        // ID in the local data store.
        return egCore.pcrud.apply(new_sets).then(
            null,
            function() { 
                $scope.attr_sets = $scope.attr_sets.filter(
                    function(set) { return (set.label() && !set.isnew()) });
                return $q.reject();
            },
            function(new_set) { 
                var old_set = new_sets.filter(function(s) {
                    return (s.isnew() && s.label() == new_set.label()) })[0];
                old_set.id(new_set.id());
                old_set.isnew(false);
            }
        );
    }

    function modify_maps() {
        var update_maps = [];

        angular.forEach($scope.attr_sets, function(set) {
            console.debug('inspecting attr set ' + set.label());

            if (!set.label()) return; // skip (new) unnamed sets

            // find maps that need deleting
            angular.forEach(set.attr_maps(), function(oldmap) {
                if (!set._local_map[oldmap.attr()]) {
                    console.debug('\tdeleting map for ' + oldmap.attr());
                    oldmap.isdeleted(true);
                    update_maps.push(oldmap);
                }
            });

            // find maps that need creating
            angular.forEach(set._local_map, function(value, key) {
                if (!value) return;

                var existing = set.attr_maps().filter(
                    function(emap) { return emap.attr() == key })[0];

                if (existing) return;

                console.debug('\tcreating map for ' + key);

                var newmap = new egCore.idl.aeasm();
                newmap.isnew(true);
                newmap.attr(key);
                newmap.attr_set(set.id());
                update_maps.push(newmap);
            });
        });

        return egCore.pcrud.apply(update_maps);
    }

    // mark the currently selected attr set as the main display set.
    $scope.select_set = function(set) {
        $scope.cur_attr_set_uses = 0; // how many edi accounts use this set
        if (set.isnew()) {
            $scope.cur_attr_set = set;
        } else {
            egCore.pcrud.search('acqedi', {attr_set : set.id()}, {}, 
                {idlist : true, atomic : true}
            ).then(function(accts) {
                $scope.cur_attr_set_uses = accts.length;
                $scope.cur_attr_set = set;
            });
        }
    }

    $scope.new_set = function() {
        var set = new egCore.idl.aeas();
        set.isnew(true);
        set.attr_maps([]);
        set._local_map = {};
        $scope.select_set(set);
        $scope.attr_sets.push(set);
    }

    $scope.apply = function() {
        $scope.save_in_progress = true;
        create_sets()
            .then(modify_maps)
            .then(
                function() { 
                    ngToast.create(egCore.strings.ATTR_SET_SUCCESS) 
                },
                function() { 
                    ngToast.warning(egCore.strings.ATTR_SET_ERROR);
                    return $q.reject();
                })
            .then(load_data)
            .finally(
                function() { $scope.save_in_progress = false; }
            );
    }

    // Delete the currently selected attr set.
    // Attr set maps will cascade delete.
    $scope.remove = function() {
        egConfirmDialog.open(
            egCore.strings.ATTR_SET_DELETE_CONFIRM, 
            $scope.cur_attr_set.label()
        ).result.then(function() {
            $scope.save_in_progress = true;
            (   // remove from server if necessary
                $scope.cur_attr_set.isnew() ?
                $q.when() :
                egCore.pcrud.remove($scope.cur_attr_set)
            ).then(
                // remove from the local att_sets list
                function() {
                    ngToast.create(egCore.strings.ATTR_SET_SUCCESS);
                    $scope.attr_sets = $scope.attr_sets.filter(
                        function(set) {
                            return set.id() != $scope.cur_attr_set.id() 
                        }
                    );
                    $scope.cur_attr_set = $scope.attr_sets[0];
                },
                function() { ngToast.warning(egCore.strings.ATTR_SET_ERROR) }

            ).finally(
                function() { $scope.save_in_progress = false; }
            );
        });
    }

    $scope.clone_set = function(source_set) {
        var set = new egCore.idl.aeas();
        set.isnew(true);
        set.attr_maps([]);
        set._local_map = {};

        // Copy attr info from cloned attr set. No need to create the
        // maps now, just indicate in the local mapping that attr maps
        // are pending.
        angular.forEach(source_set.attr_maps(), function(map) {
            set._local_map[map.attr()] = true;
        });

        $scope.select_set(set);
        $scope.attr_sets.push(set);
    }

    load_data();
}])


