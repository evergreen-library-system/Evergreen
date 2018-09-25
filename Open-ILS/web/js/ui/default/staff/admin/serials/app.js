angular.module('egSerialsAdmin',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/admin/serials/templates', {
        templateUrl: './admin/serials/t_templates',
        controller: 'TemplatesCtrl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/serials/t_splash',
        resolve : resolver
    });
}])

// cheating
.factory("sharedScope",function(){
    return {};
})

.factory('templateSvc', 
       ['egCore','$q','$uibModal','ngToast',
function(egCore , $q , $uibModal , ngToast ) {

    var service = {
    };

    service.create_or_edit_template = function(id,ou,cb) {
        $uibModal.open({
            template: '<eg-serials-template template_id="' + id + '" owning_lib="' + ou + '"></eg-serials-template>',
            backdrop: 'static',
            controller:
                   ['sharedScope','$uibModalInstance',
            function(sharedScope , $uibModalInstance ) {
                sharedScope.close_modal = function(count) { $uibModalInstance.close({}) }
            }],
            windowClass: 'app-modal-window',
            backdrop: 'static',
            keyboard: false
        }).result.then(
            function(args) {
                if (cb) { cb(); }
            }
        );
    }

    service.delete_template = function(id,cb) {
        return egCore.pcrud.search('act',
            {id : id},
            null, {atomic : true}
        ).then(function(resp) {
            var evt = egCore.evt.parse(resp);
            if (evt) { console.log(evt); }
            if (!evt && resp && resp.length > 0) {
                return resp[0];
            }
        }).then(function(resp) {
            resp.isdeleted(true); // needed?
            return egCore.pcrud.remove(resp);
        }).then(
            function(resp) {
                console.log(resp);
                ngToast.success(egCore.strings.SERIALS_TEMPLATE_SUCCESS_DELETE);
            },function(resp) {
                console.log(resp);
                ngToast.danger(egCore.strings.SERIALS_TEMPLATE_FAIL_DELETE);
            }
        ).finally(function() {
            if (cb) { cb(); }
        });
    }

    return service;
}])

.factory('itemSvc', 
       ['egCore','$q',
function(egCore , $q) {

    var service = {
    };

    service.get_locations = function(orgs) {
        return egCore.pcrud.search('acpl',
            {
                owning_lib : orgs,
                deleted    : 'f'
            },
            {
                flesh : 1,
                flesh_fields : {
                    'acpl' : ['owning_lib']
                },
                order_by : { acpl : 'name' }
            }, {atomic : true}
        );
    };

    service.get_statuses = function() {
        if (egCore.env.ccs)
            return $q.when(egCore.env.ccs.list);

        return egCore.pcrud.retrieveAll('ccs', {order_by : { ccs : 'name' }}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'ccs');
                return list;
            }
        );

    };

    service.get_circ_mods = function() {
        if (egCore.env.ccm)
            return $q.when(egCore.env.ccm.list);

        return egCore.pcrud.retrieveAll('ccm', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'ccm');
                return list;
            }
        );

    };

    service.get_circ_types = function() {
        if (egCore.env.citm)
            return $q.when(egCore.env.citm.list);

        return egCore.pcrud.retrieveAll('citm', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'citm');
                return list;
            }
        );

    };

    service.get_age_protects = function() {
        if (egCore.env.crahp)
            return $q.when(egCore.env.crahp.list);

        return egCore.pcrud.retrieveAll('crahp', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'crahp');
                return list;
            }
        );

    };

    service.get_floating_groups = function() {
        if (egCore.env.cfg)
            return $q.when(egCore.env.cfg.list);

        return egCore.pcrud.retrieveAll('cfg', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'cfg');
                return list;
            }
        );

    };

    service.bmp_parts = {};
    service.get_parts = function(rec) {
        if (service.bmp_parts[rec])
            return $q.when(service.bmp_parts[rec]);

        return egCore.pcrud.search('bmp',
            {record : rec, deleted : 'f'},
            null, {atomic : true}
        ).then(function(list) {
            service.bmp_parts[rec] = list;
            return list;
        });

    };

    return service;
}])

.controller('TemplatesCtrl', 
       ['$scope','$q','$window','$routeParams','$location','$timeout','egCore','egNet','itemSvc','templateSvc',
        'egGridDataProvider',
function($scope , $q , $window , $routeParams , $location , $timeout , egCore , egNet , itemSvc , templateSvc ,
         egGridDataProvider ) {

    function current_query() {
        var filter = {
            'owning_lib' : egCore.org.descendants($scope.context_ou.id(), true)
        };
        return filter;
    }

    function refresh_page() {
        $scope.grid_controls.setQuery(current_query());
    }

    $scope.grid_actions = {
        create_template : function() {
            templateSvc.create_or_edit_template(null,$scope.context_ou.id(),refresh_page);
        },
        edit_template : function(items) {
            templateSvc.create_or_edit_template(items[0].id,$scope.context_ou.id(),refresh_page);
        },
        delete_template : function(items) {
            var promises = [];
            angular.forEach(items,function(item) {
                promises.push(templateSvc.delete_template(item.id));
            });
            $q.all(promises).then(function() {
                refresh_page();
            });
        }
    }
    $scope.grid_controls = {
        activateItem : function(item) {
            templateSvc.create_or_edit_template(item.id,$scope.context_ou.id(),refresh_page);
        },
        setQuery : function(x) { return x || current_query(); },
        setSort : function() { return ['name','id'] }
    }

    $scope.need_one_selected = function() {
        var items = $scope.grid_controls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    // called after any egGridActions action occurs
    $scope.grid_actions.refresh = refresh_page;

    // re-draw the grid when user changes the org selector
    $scope.context_ou = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.$watch('context_ou', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) 
            refresh_page();
    });

    refresh_page();

}])

.directive("egSerialsTemplate", function () {
    return {
        restrict: 'E',
        replace: true,
        template: '<div ng-include="'+"'/eg/staff/admin/serials/t_attr_edit'"+'"></div>',
        scope: {
            templateId: '=',
             owningLib: '='
        },
        controller : ['$scope','$q','$window','itemSvc','egCore','ngToast','sharedScope',
            function ( $scope , $q , $window , itemSvc , egCore , ngToast , sharedScope ) {

                $scope.close_modal = function() {
                    if ($scope.dirty && !window.confirm(egCore.strings.CONFIRM_DIRTY_EXIT)) {
                        return;
                    }
                    //console.log('unsetting dirty for close_modal');
                    $scope.dirty = false;
                    sharedScope.close_modal();
                };

                $scope.defaults = { // If defaults are not set at all, allow everything
                    attributes : {
                        status : true,
                        loan_duration : true,
                        fine_level : true,
                        alerts : true,
                        deposit : true,
                        deposit_amount : true,
                        opac_visible : true,
                        price : true,
                        circulate : true,
                        mint_condition : true,
                        circ_lib : true,
                        ref : true,
                        circ_modifier : true,
                        circ_as_type : true,
                        location : true,
                        holdable : true,
                        age_protect : true,
                        floating : true
                    }
                };

                $scope.fetchDefaults = function () {
                    egCore.hatch.getItem('serials.copy.defaults').then(function(t) {
                        if (t) {
                            $scope.defaults = t;
                        }
                    });
                }
                $scope.fetchDefaults();

                //console.log('unsetting dirty by default');
                $scope.dirty = false;
                $scope.$watch('dirty',
                    function(newVal, oldVal) {
                        //console.log('watching dirty');
                        //console.log('...oldVal',oldVal);
                        //console.log('...newVal',newVal);
                        //console.log('...fetching',$scope.fetching);
                        if (newVal && $scope.fetching) {
                            // KLUDGY
                            // so after fetchTemplate -> applyTemplate
                            // the working watches will fire and set
                            // dirty to true.  We'll undo that at this
                            // point.
                            //console.log('unsetting dirty via kludge');
                            $scope.fetching = false;
                            $scope.dirty = false;
                            newVal = false;
                        }
                        if (newVal && newVal != oldVal) {
                            $($window).on('beforeunload.template', function(){
                                return 'There is unsaved template data!'
                            });
                        } else {
                            $($window).off('beforeunload.template');
                        }
                    }
                );

                $scope.applyTemplate = function() {
                    //console.log('applying...');
                    angular.forEach($scope.hashed_template, function (v,k) {
                        //console.log(k,v);
                        if (k == 'circ_lib') {
                            $scope.working[k] = egCore.org.get(v);
                        } else if (!angular.isObject(v)) {
                            $scope.working[k] = angular.copy(v);
                        } else {
                            angular.forEach(v, function (sv,sk) {
                                if (!(k in $scope.working))
                                    $scope.working[k] = {};
                                $scope.working[k][sk] = angular.copy(sv);
                            });
                        }
                    });
                    //console.log('unsetting dirty via applyTemplate');
                    $scope.dirty = false;
                }

                $scope.fetching = false;
                $scope.fetchTemplate = function () {
                    $scope.fetching = true;
                    return egCore.pcrud.search('act',
                        {id : $scope.templateId},
                        null, {atomic : true}
                    ).then(function(resp) {
                        var evt = egCore.evt.parse(resp);
                        if (evt) { console.log(evt); }
                        if (!evt && resp && resp.length > 0) {
                            $scope.fm_template =  resp[0];
                            $scope.hashed_template = egCore.idl.toHash(resp[0]); 
                            $scope.applyTemplate();
                        } else {
                            console.log('new template');
                        }
                    });
                }
 
                $scope.saveTemplate = function() {
                    var tmpl = {};
        
                    angular.forEach($scope.working, function (v,k) {
                        if (angular.isObject(v)) { // we'll use the pkey
                            if (v.id) v = v.id();
                            else if (v.code) v = v.code();
                        }
        
                        tmpl[k] = v;
                    });
        
                    $scope.hashed_template = tmpl;

                    var act_obj = $scope.fm_template || new egCore.idl.act() ;
                    //console.log('consuming...');
                    angular.forEach($scope.hashed_template, function (v,k) {
                        //console.log(k,v);
                        if (typeof act_obj[k] == 'function') {
                            act_obj[k](v);
                        } else {
                            console.log('something wrong here',k,act_obj[k]);
                        }
                    });
                    if ($scope.fm_template) {
                        console.log('edit');
                        act_obj.ischanged('t');
                        act_obj.editor( egCore.auth.user().id() );
                        act_obj.edit_date( new Date() );
                    } else {
                        console.log('create');
                        act_obj.isnew('t');
                        act_obj.creator( egCore.auth.user().id() );
                        act_obj.owning_lib( $scope.owningLib );
                        act_obj.create_date( new Date() );
                    }
                    var some_failure = false;
                    var some_success = false;
                    egCore.net.request(
                        'open-ils.cat', // worth replacing with pcrud?
                        'open-ils.cat.asset.copy_template.create_or_update',
                        egCore.auth.token(),
                        act_obj
                    ).then(
                        function(resp) {
                            var evt = egCore.evt.parse(resp);
                            if (evt) { // any way to just throw or return this to the error handler?
                                console.log('failure',resp);
                                some_failure = true;
                                ngToast.danger(egCore.strings.SERIALS_TEMPLATE_FAIL_SAVE);
                            } else {
                                console.log('success',resp);
                                some_success = true;
                                ngToast.success(egCore.strings.SERIALS_TEMPLATE_SUCCESS_SAVE);
                            }
                        },
                        function(resp) {
                            console.log('failure',resp);
                            some_failure = true;
                            ngToast.danger(egCore.strings.SERIALS_TEMPLATE_FAIL_SAVE);
                        }
                    ).then(function(){
                        if (some_success && !some_failure) {
                            //console.log('unsetting dirty for save');
                            $scope.dirty = false;
                            $scope.close_modal();
                        }
                    });
                }
            
                $scope.hashed_template = {};
                $scope.imported_template = { data : '' };
                $scope.fetchTemplate();

                // FIXME - leaving this for now
                $scope.$watch('imported_template.data', function(newVal, oldVal) {
                    if (newVal && newVal != oldVal) {
                        try {
                            var newTemplate = JSON.parse(newVal);
                            if (!Object.keys(newTemplate).length) return;
                            $scope.hashed_template = newTemplate;
                        } catch (E) {
                            console.log('tried to import an invalid serials template file');
                        }
                    }
                });

                $scope.orgById = function (id) { return egCore.org.get(id) }
                $scope.statusById = function (id) {
                    return $scope.status_list.filter( function (s) { return s.id() == id } )[0];
                }
                $scope.locationById = function (id) {
                    return $scope.location_cache[''+id];
                }
            
                createSimpleUpdateWatcher = function (field) {
                    $scope.$watch('working.' + field, function () {
                        var newval = $scope.working[field];
            
                        if (typeof newval != 'undefined') {
                            //console.log('setting dirty for field',field);
                            $scope.dirty = true;
                            if (angular.isObject(newval)) { // we'll use the pkey
                                if (newval.id) $scope.working[field] = newval.id();
                                else if (newval.code) $scope.working[field] = newval.code();
                            }
            
                            if (""+newval == "" || newval == null) {
                                $scope.working[field] = undefined;
                            }
            
                        }
                    });
                }

                $scope.clearWorking = function () {
                    angular.forEach($scope.working, function (v,k,o) {
                        if (!angular.isObject(v)) {
                            if (typeof v != 'undefined')
                                $scope.working[k] = undefined;
                        } else if (k != 'circ_lib') {
                            angular.forEach(v, function (sv,sk) {
                                $scope.working[k][sk] = undefined;
                            });
                        }
                    });
                    $scope.working.circ_lib = undefined; // special
                    $scope.working.loan_duration = 2;
                    $scope.working.fine_level    = 2;
                    //console.log('unsetting dirty for clearWorking');
                    $scope.dirty = false;
                }

                $scope.working = {
                    loan_duration : 2,
                    fine_level    : 2
                };
                $scope.location_orgs = [];
                $scope.location_cache = {};

                $scope.i18n = egCore.i18n;
                $scope.location_list = [];
                itemSvc.get_locations(
                    egCore.org.fullPath( egCore.auth.user().ws_ou(), true )
                ).then(function(list){
                    $scope.location_list = list;
                });
                createSimpleUpdateWatcher('location');

                $scope.status_list = [];
                itemSvc.get_statuses().then(function(list){
                    $scope.status_list = list;
                });
                createSimpleUpdateWatcher('status');
            
                $scope.circ_modifier_list = [];
                itemSvc.get_circ_mods().then(function(list){
                    $scope.circ_modifier_list = list;
                });
                createSimpleUpdateWatcher('circ_modifier');
            
                $scope.circ_type_list = [];
                itemSvc.get_circ_types().then(function(list){
                    $scope.circ_type_list = list;
                });
                createSimpleUpdateWatcher('circ_as_type');
            
                $scope.age_protect_list = [];
                itemSvc.get_age_protects().then(function(list){
                    $scope.age_protect_list = list;
                });
                createSimpleUpdateWatcher('age_protect');
            
                createSimpleUpdateWatcher('circulate');
                createSimpleUpdateWatcher('holdable');

                $scope.loan_duration_options = [
                    {
                        v: function(){return 1;},
                        l: function(){return egCore.strings.LOAN_DURATION_SHORT;}
                    },
                    {
                        v: function(){return 2;},
                        l: function(){return egCore.strings.LOAN_DURATION_NORMAL;}
                    },
                    {
                        v: function(){return 3;},
                        l: function(){return egCore.strings.LOAN_DURATION_EXTENDED;}
                    }
                ];
                createSimpleUpdateWatcher('loan_duration');

                $scope.fine_level_options = [
                    {
                        v: function(){return 1;},
                        l: function(){return egCore.strings.FINE_LEVEL_LOW;}
                    },
                    {
                        v: function(){return 2;},
                        l: function(){return egCore.strings.FINE_LEVEL_NORMAL;}
                    },
                    {
                        v: function(){return 3;},
                        l: function(){return egCore.strings.FINE_LEVEL_HIGH;}
                    }
                ];
                createSimpleUpdateWatcher('fine_level');

                createSimpleUpdateWatcher('name');
                createSimpleUpdateWatcher('price');
                createSimpleUpdateWatcher('deposit');
                createSimpleUpdateWatcher('deposit_amount');
                createSimpleUpdateWatcher('mint_condition');
                createSimpleUpdateWatcher('opac_visible');
                createSimpleUpdateWatcher('ref');
            }
        ]
    }
})


