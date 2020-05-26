angular.module('egCurbsideAppDep')

.directive('egCurbsideSchedulePickup', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: { },
        templateUrl: './circ/curbside/t_schedule_pickup',
        controller:
       ['$scope','$q','egCurbsideCoreSvc','egCore','patronSvc',
        '$uibModal','$timeout','$location','egConfirmDialog','ngToast',
function($scope , $q , egCurbsideCoreSvc , egCore , patronSvc ,
         $uibModal , $timeout , $location , egConfirmDialog , ngToast) {

    $scope.clear = function() {
        $scope.user_id = undefined;
        $scope.args = {};
        $scope.readyHolds = 0;
        $scope.openAppointments = [];
        $scope.forms = [];
    }
    $scope.clear();

    patron_search_dialog = function() {
        return $uibModal.open({
            templateUrl: './share/t_patron_selector',
            backdrop: 'static',
            size: 'lg',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance','$controller',
            function($scope , $uibModalInstance , $controller) {
                angular.extend(this, $controller('BasePatronSearchCtrl', {$scope : $scope}));
                $scope.clearForm();
                $scope.need_one_selected = function() {
                    var items = $scope.gridControls.selectedItems();
                    return (items.length == 1) ? false : true
                }
                $scope.ok = function() {
                    var items = $scope.gridControls.selectedItems();
                    if (items.length == 1) {
                        $uibModalInstance.close(items[0].card().barcode());
                    } else {
                        $uibModalInstance.close()
                    }
                }
                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

    $scope.patron_search = function() {
        patron_search_dialog().result.then(function(barcode) {
            $scope.args.barcode = barcode;
        });
    }

    // this is blatantly copied from the patron app; if the AngularJS
    // code had a longer life-expectancy, this would have been moved
    // to a service.
    $scope.submitBarcode = function(args) {
        $scope.bcNotFound = null;
        $scope.optInRestricted = false;
        if (!args.barcode) return;
        args.barcode = args.barcode.replace(/\s/g,'');
        // blur so next time it's set to true it will re-apply select()
        $scope.selectMe = false;

        var user_id;

        // given a scanned barcode, this function finds any matching users
        // and handles multiple matches due to barcode completion
        function handleBarcodeCompletion(scanned_barcode) {
            var deferred = $q.defer();

            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.get_barcodes',
                egCore.auth.token(), egCore.auth.user().ws_ou(), 
                'actor', scanned_barcode)

            .then(function(resp) { // get_barcodes

                if (evt = egCore.evt.parse(resp)) {
                    alert(evt); // FIXME
                    deferred.reject();
                    return;
                }

                if (!resp || !resp[0]) {
                    $scope.bcNotFound = args.barcode;
                    $scope.selectMe = true;
                    egCore.audio.play('warning.patron.not_found');
                    deferred.reject();
                    return;
                }

                if (resp.length == 1) {
                    // exactly one matching barcode: return it
                    deferred.resolve();
                    user_id = resp[0].id;
                } else {
                    // multiple matching barcodes: let the user pick one 
                    var barcode_map = {};
                    var matches = [];
                    var promises = [];
                    var selected_barcode;
                    angular.forEach(resp, function(match) {
                        promises.push(
                            egUser.get(match.id, {useFields : ['home_ou']}).then(function(user) {
                                barcode_map[match.barcode] = user.id();
                                matches.push( {
                                    barcode: match.barcode,
                                    title: user.first_given_name() + ' ' + user.family_name(),
                                    org_name: user.home_ou().name(),
                                    org_shortname: user.home_ou().shortname()
                                });
                            })
                        );
                    });
                    return $q.all(promises)
                    .then(function() {
                        $uibModal.open({
                            templateUrl: './circ/share/t_barcode_choice_dialog',
                            controller:
                                ['$scope', '$uibModalInstance',
                                function($scope, $uibModalInstance) {
                                $scope.matches = matches;
                                $scope.ok = function(barcode) {
                                    $uibModalInstance.close();
                                    selected_barcode = barcode;
                                }
                                $scope.cancel = function() {$uibModalInstance.dismiss()}
                            }],
                        }).result.then(function() {
                            deferred.resolve();
                            user_id = barcode_map[selected_barcode];
                        });
                    });
                }
            });
            return deferred.promise;
        }

        // call our function to lookup matching users for the scanned barcode
        handleBarcodeCompletion(args.barcode).then(function() {

            // see if an opt-in request is needed
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.user.org_unit_opt_in.check',
                egCore.auth.token(), user_id
            ).then(function(optInResp) { // opt_in_check

                if (evt = egCore.evt.parse(optInResp)) {
                    alert(evt); // FIXME
                    return;
                }

                if (optInResp == 2) {
                    // opt-in disallowed at this location by patron's home library
                    $scope.optInRestricted = true;
                    $scope.selectMe = true;
                    egCore.audio.play('warning.patron.opt_in_restricted');
                    return;
                }
            
                if (optInResp == 1) {
                    // opt-in handled or not needed
                    return loadPatron(user_id);
                }

                // opt-in needed, show the opt-in dialog
                egUser.get(user_id, {useFields : []})

                .then(function(user) { // retrieve user
                    var org = egCore.org.get(user.home_ou());
                    egConfirmDialog.open(
                        egCore.strings.OPT_IN_DIALOG_TITLE,
                        egCore.strings.OPT_IN_DIALOG,
                        {   family_name : user.family_name(),
                            first_given_name : user.first_given_name(),
                            org_name : org.name(),
                            org_shortname : org.shortname(),
                            ok : function() { createOptIn(user.id()) },
                            cancel : function() {}
                        }
                    );
                })
            })
        })
    }

    function countReadyHolds(user_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.patron.ready_holds_at_lib.count',
            egCore.auth.token(),
            user_id
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                return 0;
            } else {
                return resp;
            }
        });
    }

    function fetchOpenAppointments(user_id) {
        return egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.open_user_appointments_at_lib.atomic',
            egCore.auth.token(),
            user_id
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                return 0;
            } else {
                return resp;
            }
        });
    }

    function mungeAvailableTimes(hash, times) {
        var existing_present = false;
        if (angular.isDefined(hash.slot_time) && hash.slot_time !== null) {
            hash.original_slot_time = hash.slot_time;
        }
        hash.available_times = times.map(function(t) {
            if (angular.isDefined(hash.slot_time) && hash.slot_time !== null && hash.slot_time === t[0]) {
                existing_present = true;
            }
            return {
                time: t[0],
                available: t[1],
                time_fmt: moment(t[0], [moment.ISO_8601, 'HH:mm:ss']).format('LT')
            };
        });
        if (angular.isDefined(hash.slot_time) && hash.slot_time !== null && !existing_present) {
            hash.available_times.unshift({
                time: hash.slot_time,
                available: 0,
                time_fmt: moment(hash.slot_time, [moment.ISO_8601, 'HH:mm:ss']).format('LT')
            });
        }
    }

    function mungeOneAppointment(c, isNew) {
        var hash = egCore.idl.toHash(c);
        if (hash.slot === null) {
            // coerce to today for the purpose of the
            // form if no slot time has been set yet
            hash.slot = new Date().toISOString();
            hash.slot_time = null;
        } else {
            if (!isNew) {
                hash.slot_time = hash.slot.substring(11, 19);
            }
        }
        hash.slot_date = new Date(hash.slot);
        if (!isNew) {
            hash.is_past = (hash.slot_date < new Date());
        }
        hash.available_times = [];
        egCore.net.request (
            'open-ils.curbside',
            'open-ils.curbside.times_for_date.atomic',
            egCore.auth.token(),
            hash.slot.substring(0, 10),
        ).then(function(times) {
            mungeAvailableTimes(hash, times);
        });
        return hash;
    }

    function mungeAppointmentList(list) {
        $scope.openAppointments = list.map(function(c) {
            var hash = mungeOneAppointment(c);
            return hash;
        });
    }

    function loadPatron(user_id) {
        $scope.user_id = user_id;
        patronSvc.getPrimary(user_id);
        countReadyHolds(user_id).then(function(ct) { $scope.readyHolds = ct });        
        fetchOpenAppointments(user_id).then(function(list) {
            mungeAppointmentList(list);
        });
    }


    $scope.minDate = new Date();
    $scope.refreshAvailableTimes = function(hash) {
        var dateStr = (new Date(hash.slot_date)).toISOString().substring(0, 10);
        egCore.net.request (
            'open-ils.curbside',
            'open-ils.curbside.times_for_date.atomic',
            egCore.auth.token(),
            dateStr,
        ).then(function(times) {
            mungeAvailableTimes(hash, times);
        });
    }

    $scope.startNewAppointment = function() {
        var slot = new egCore.idl.acsp();
        slot.slot = new Date().toISOString();
        slot.patron = $scope.user_id;
        slot.org = egCore.auth.user().ws_ou();
        $scope.openAppointments = [ mungeOneAppointment(slot, true) ];
    }

    $scope.updateAppointment = function(appt) {
        var op = angular.isDefined(appt.id) ? 'update' : 'create';
        egCore.net.request(
            'open-ils.curbside',
            'open-ils.curbside.' + op + '_appointment',
            egCore.auth.token(),
            $scope.user_id,
            (new Date(appt.slot_date)).toISOString().substring(0, 10),
            appt.slot_time,
            egCore.auth.user().ws_ou(),
            appt.notes
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                if (evt.textcode === 'CURBSIDE_MAX_FOR_TIME') {
                    ngToast.danger(egCore.strings.$replace(
                        egCore.strings.FAILED_SAVE_APPOINTMENT_TOO_MANY,
                        { evt_code : evt.code }
                    ));
                } else {
                    ngToast.danger(egCore.strings.$replace(
                        egCore.strings.FAILED_SAVE_APPOINTMENT,
                        { evt_code : evt.code }
                    ));
                }
            } else {
                ngToast.success(egCore.strings.$replace(
                    egCore.strings.SUCCESS_SAVE_APPOINTMENT,
                    { slot_id : resp.id() }
                ));
            }
            fetchOpenAppointments($scope.user_id).then(function(list) {
                mungeAppointmentList(list);
            });
        });
    }

    function doCancel(id) {
        egCore.net.request (
            'open-ils.curbside',
            'open-ils.curbside.delete_appointment',
            egCore.auth.token(),
            id
        ).then(function(resp) {
            if (!angular.isDefined(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CANCEL_APPOINTMENT,
                    { slot_id : id, evt_code : 'NO_SUCH_APPOINTMENT' }
                ));
            } else if (evt = egCore.evt.parse(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CANCEL_APPOINTMENT,
                    { slot_id : id, evt_code : evt.code }
                ));
            } else {
                ngToast.success(egCore.strings.$replace(
                    egCore.strings.SUCCESS_CANCEL_APPOINTMENT,
                    { slot_id : id }
                ));
            }
            fetchOpenAppointments($scope.user_id).then(function(list) {
                mungeAppointmentList(list);
            });
        });
    }
    $scope.cancelAppointment = function(id) {
        egConfirmDialog.open(
            egCore.strings.CONFIRM_CANCEL_TITLE,
            egCore.strings.CONFIRM_CANCEL_BODY,
            {   slot_id : id,
                ok : function() { doCancel(id) },
                cancel : function() {}
            }
        );
    }

    $scope.patron = function() {
        return patronSvc.current;
    }

}]}});
