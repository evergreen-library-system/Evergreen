angular.module('egAdminClosed',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod','ngToast'])

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.controller('ClosedDates',
       ['$scope','$q','$timeout','$location','$window','$uibModal','ngToast',
        'egCore','egGridDataProvider','egConfirmDialog','egProgressDialog','$timeout',
function($scope , $q , $timeout , $location , $window , $uibModal , ngToast ,
         egCore , egGridDataProvider , egConfirmDialog , egProgressDialog , $timeout) {

    egCore.startup.go().then(function () {

        $scope.context_org = egCore.org.get(egCore.auth.user().ws_ou());
        $scope.date_filter = new Date();
    });

    $scope.closings = [];
    var provider = egGridDataProvider.instance({
      get : function(offset, count) {
        $scope.refresh_generation = new Date().getTime();
        $scope.closings = [];
        var deferred = $q.defer();
        egCore.startup.go().then(function(){egCore.pcrud.search(
            'aoucd', 
            { org_unit : $scope.context_org.id(),
              "-or" : [
                { close_end : { ">=" : $scope.date_filter.toISOString() } },
                { "-and" : { emergency_closing : { "!=" : null }, "+aec" : { process_end_time : { "=" : null } } } }
              ]
            },
            {   order_by : { aoucd : 'close_start' },
                limit : count,
                offset: offset,
                join  : { "aec" : { type : "left" } },
                flesh : 2,
                flesh_fields : { aoucd : ['emergency_closing'], aec : ['status'] }
            }
        ).then(function () {
            return $scope.closings;
        }, null, function(cl) {
            if (!cl) return deferred.resolve();

            var i = egCore.idl.toHash(cl);

            function refresh_emergency_status (status) {
                if (status._generation == $scope.refresh_generation) {
                    egCore.pcrud.retrieve('aecs',status.id).then(function(s) {

                        status.circulations = s.circulations();
                        status.circulations_complete = s.circulations_complete();
                        status.holds = s.holds();
                        status.holds_complete = s.holds_complete();
                        status.reservations = s.reservations();
                        status.reservations_complete = s.reservations_complete();

                        if (s.process_start_time() && !s.process_end_time())
                            $timeout(refresh_emergency_status, 2000, true, status);
                    });
                }
            }

            var now = new Date();
            var s = new Date(i.close_start);
            var e = new Date(i.close_end);
            i._duration = ((e - s) / 1000) + 1;
            i._duration = '' + i._duration + ' seconds';
            i._format = $scope.$root.egDateAndTimeFormat;

            if (i.emergency_closing) {
                var x = i.emergency_closing.status.circulations - i.emergency_closing.status.circulations_complete;
                x += i.emergency_closing.status.holds - i.emergency_closing.status.holds_complete;
                x += i.emergency_closing.status.reservations - i.emergency_closing.status.reservations_complete;

                if (i.emergency_closing.process_end_time) {
                    i._text_class = 'rounded bg-success';
                } else { // still work to do!
                    i._text_class = 'rounded bg-primary';
                    i.emergency_closing.status._generation = $scope.refresh_generation;;
                    refresh_emergency_status(i.emergency_closing.status);
                }
            } else {
                i._text_class = 'hidden';
            }

            $scope.closings.push(i);
            return i;
        }).then(deferred.resolve, null, deferred.notify)});

        return deferred.promise;
      }
    });

    $scope.gridDataProvider = provider;

    $scope.refresh_page = function () {
        $scope.closings = [];
        $timeout(function(){provider.refresh()});
    }

    $scope.org_changed = $scope.refresh_page;
    $scope.$watch('date_filter', $scope.refresh_page);

    function spawn_editor(cl, action) {
        var deferred = $q.defer();
        $uibModal.open({
            templateUrl: './admin/local/actor/edit_closed_dates',
            backdrop: 'static',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.args = {};
                $scope.args.create_aec = false;
                $scope.args.apply_to_all = false;
                $scope.args.process_immediately = false;
                $scope.args.type = /^[t1]/.test(cl.multi_day()) ? 'multi' : /^[t1]/.test(cl.full_day()) ? 'full' : 'detailed';
                $scope.args.is_not_detailed = $scope.args.type == 'detailed' ? false : true;
                $scope.args.aoucd = cl;
                $scope.args.aec = cl.emergency_closing();

                $scope.unprocessed = true;
                if ($scope.args.aec) {
                    $scope.args.aoucd.emergency_closing($scope.args.aec.id()); // detatch for now
                    $scope.unprocessed = $scope.args.aec.process_start_time() ? false : true;
                    $scope.args.create_aec = $scope.unprocessed;;
                }

                $scope.org_unit = egCore.org.get(cl.org_unit());
                $scope.args.start = new Date(cl.close_start());
                $scope.args.end = new Date(cl.close_end());
                $scope.args.reason = cl.reason();
                $scope.is_update = action == 'update';

                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                $scope.is_emergency = $scope.aec ? true : false;
                $scope.check_if_emergency = function () {
                    if ($scope.args.aoucd.emergency_closing()) {
                        ngToast.danger(egCore.strings.EMERGENCY_CLOSING);
                        $scope.is_emergency = true;
                        return $scope.is_emergency;
                    }
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.org_unit.closed_date.emergency_test',
                        egCore.auth.token(), $scope.args.aoucd
                    ).then(function (res) {
                        $scope.duration_rule_count = parseInt(res);
                        if ($scope.duration_rule_count) {
                            ngToast.danger(egCore.strings.POSSIBLE_EMERGENCY_CLOSING);
                            $scope.is_emergency = true;
                        } else {
                            $scope.is_emergency = false;
                        }
                    });
                    return $scope.is_emergency;
                }

                $scope.update_org_unit = function () { $scope.args.aoucd.org_unit($scope.org_unit.id()) }

                $scope.$watch('args.create_aec', function (n) {
                    if (n) {
                        if (!$scope.args.aec) $scope.args.aec = new egCore.idl.aec();
                        if (!$scope.args.aec.creator()) $scope.args.aec.creator(egCore.auth.user().id());
                    } else {
                        if (!cl.emergency_closing()) $scope.args.aec = null;
                    }
                });
                $scope.$watch('args.type', function (n) { $scope.args.is_not_detailed = n != 'detailed' });
                $scope.$watch('args.start', function (n) { $scope.args.aoucd.close_start(n.toISOString()); if (n) $scope.check_if_emergency() });
                $scope.$watch('args.end', function (n) { $scope.args.aoucd.close_end(n.toISOString()) });
                $scope.$watch('args.reason', function (n) { $scope.args.aoucd.reason(n) });
             }]
        }).result.then(function(args) {

            var start = args.start;
            var end = args.end;

            args.aoucd.full_day(0);
            args.aoucd.multi_day(0);

            if (args.type == 'full') {
                args.aoucd.full_day(1);
                end = new Date(start);
            }

            if (args.type == 'multi') {
                args.aoucd.full_day(1);
                args.aoucd.multi_day(1);
            }

            if (args.type == 'multi' || args.type == 'full') {

                start.setHours(0);
                start.setMinutes(0);
                start.setSeconds(0);

                end.setHours(23);
                end.setMinutes(59);
                end.setSeconds(59);
            }

            args.aoucd.close_start(start.toISOString());
            args.aoucd.close_end(end.toISOString());

            if (action == 'create') {
                var new_aoucd_list = [];
                var libraries = [args.aoucd.org_unit()];

                if (args.apply_to_all)
                    libraries = egCore.org.descendants(args.aoucd.org_unit(), true);

                egProgressDialog.open({
                    label : egCore.strings.CREATING_CLOSINGS,
                    value : 0,
                    max   : libraries.length
                });

                function make_next () {
                    var l = libraries.shift();

                    if (!l) {
                        egProgressDialog.close();
                        $scope.refresh_page();
                        deferred.resolve([new_aoucd_list,args]);
                    } else {
                        args.aoucd.org_unit(l);
                        egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.org_unit.closed.create',
                            egCore.auth.token(), args.aoucd, args.aec 
                        ).then(function (new_aoucd) {
                            new_aoucd_list.push(new_aoucd);
                            make_next();
                        });
                    }
                }

                make_next();
            } else {
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.org_unit.closed.update',
                    egCore.auth.token(), args.aoucd
                ).then(function(new_aoucd) { deferred.resolve([new_aoucd,args]); });
            }
        });
        return deferred.promise;
    }

    $scope.create_aoucd = function() {
        var cl = new egCore.idl.aoucd();
        cl.isnew(1);
        cl.full_day(1);
        cl.org_unit($scope.context_org.id());
        cl.close_start(new Date().toISOString());
        cl.close_end(cl.close_start());

        spawn_editor(cl, 'create').then(function(content) {
            if (content && content[0] && content[1] && content[1].process_immediately) {

                function process_next () {
                    var new_cl = content[0].shift();

                    if (!new_cl) {
                        $scope.refresh_page();
                    } else {
                        egProgressDialog.open({label : egCore.strings.PROCESSING_EMERGENCY});
                        egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.org_unit.closed.process_emergency',
                            egCore.auth.token(), new_cl
                        ).then(
                            function () {
                                egProgressDialog.close();
                                $scope.gridControls.refresh();
                                process_next();
                            },
                            null,
                            function (status) {
                                if (status.stage != 'start' && status.stage != 'complete') {
                                    egProgressDialog.update({
                                        value : status[status.stage][0],
                                        max   : status[status.stage][1],
                                    });
                                }
                            }
                        );
                    }
                }

                process_next();
            } else {
                $scope.refresh_page();
            }
        });
    }

    $scope.update_aoucd = function(selected) {
        if (!selected || !selected.length) return;

        egCore.pcrud.retrieve('aoucd', selected[0].id, {
            join  : { "aec" : { type : "left" } },
            flesh : 2,
            flesh_fields : { aoucd : ['emergency_closing'], aec : ['status'] }
        }).then(function(cl) {
            spawn_editor(cl, 'update').then(function(content) {
                $scope.gridControls.refresh();
                if (content && content[0] && content[1] && content[1].process_immediately) {
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.org_unit.closed.process_emergency',
                        egCore.auth.token(), content[0]
                    );
                }
            });
        });
    }

    $scope.delete_aoucd = function(selected) {
        if (!selected || !selected.length) return;

        egCore.pcrud.retrieve('aoucd', selected[0].id).then(function(cl) {
            egConfirmDialog.open(
                egCore.strings.CONFIRM_CLOSED_DELETE,
                egCore.strings.CONFIRM_CLOSED_DELETE_BODY,
                { reason : cl.reason(), org : egCore.org.get(cl.org_unit()) }
            ).result.then(function() {
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.org_unit.closed.delete',
                    egCore.auth.token(), cl
                ).then(function() {
                    $scope.gridControls.refresh();
                });
            });            
        });
    }

    $scope.gridControls = {
        activateItem : function (item) {
            $scope.update_aoucd([item]);
        }
    };

}])

