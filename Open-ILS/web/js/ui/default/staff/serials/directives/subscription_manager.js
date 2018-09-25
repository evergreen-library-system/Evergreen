angular.module('egSerialsAppDep')

.directive('egSubscriptionManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            bibId : '='
        },
        templateUrl: './serials/t_subscription_manager',
        controller:
       ['$scope','$q','egSerialsCoreSvc','egCore','egGridDataProvider',
        '$uibModal','ngToast','egConfirmDialog',
function($scope , $q , egSerialsCoreSvc , egCore , egGridDataProvider ,
         $uibModal , ngToast , egConfirmDialog ) {

    $scope.selected_owning_ou = null;
    $scope.owning_ou_changed = function(org) {
        $scope.selected_owning_ou = org.id();
        reload();
    }

    function reload() {
        egSerialsCoreSvc.fetch($scope.bibId, $scope.selected_owning_ou).then(function() {
            $scope.subscriptions = egCore.idl.toTypedHash(egSerialsCoreSvc.subTree);
            // un-flesh receive unit template so that we can use
            // it as a model of a select
            angular.forEach($scope.subscriptions, function(ssub) {
                angular.forEach(ssub.distributions, function(sdist) {
                    if (angular.isObject(sdist.receive_unit_template)) {
                        sdist.receive_unit_template = sdist.receive_unit_template.id;
                    }
                });
            });
            $scope.distStreamGridDataProvider.refresh();
        });
    }
    reload();

    $scope.localStreamNames = [];
    egCore.hatch.getItem('eg.serials.stream_names')
    .then(function(list) {
        if (list) $scope.localStreamNames = list;
    });

    $scope.distStreamGridControls = {
        activateItem : function (item) { } // TODO
    };
    $scope.distStreamGridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier(egSerialsCoreSvc.subList, offset, count);
        }
    });

    $scope.need_one_selected = function() {
        var items = $scope.distStreamGridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.receiving_templates = {};
    angular.forEach(egCore.org.list(), function(org) {
        egSerialsCoreSvc.fetch_templates(org.id()).then(function(list){
            $scope.receiving_templates[org.id()] = egCore.idl.toTypedHash(list);
        });
    });

    $scope.add_subscription = function() {
        var new_ssub = egCore.idl.toTypedHash(new egCore.idl.ssub());
        new_ssub._isnew = true;
        new_ssub.record_entry = $scope.bibId;
        new_ssub._focus_me = true;
        $scope.subscriptions.push(new_ssub);
        $scope.add_distribution(new_ssub); // since we know we want at least one distribution
    }
    $scope.add_distribution = function(ssub, grab_focus) {
        egCore.org.settings([
            'serial.default_display_grouping'
        ]).then(function(set) {
            var new_sdist = egCore.idl.toTypedHash(new egCore.idl.sdist());
            new_sdist._isnew = true;
            new_sdist.subscription = ssub.id;
            new_sdist.display_grouping = set['serial.default_display_grouping'] || 'chron';
            if (!angular.isArray(ssub.distributions)){
                ssub.distributions = [];
            }
            if (grab_focus) {
                new_sdist._focus_me = true;
                ssub._focus_me = false;
            }
            ssub.distributions.push(new_sdist);
            $scope.add_stream(new_sdist); // since we know we want at least one stream
        });
    }
    $scope.remove_pending_distribution = function(ssub, sdist) {
        var to_remove = -1;
        for (var i = 0; i < ssub.distributions.length; i++) {
            if (ssub.distributions[i] === sdist) {
                to_remove = i;
                break;
            }
        }
        if (to_remove > -1) {
            ssub.distributions.splice(to_remove, 1);
        }
    }
    $scope.add_stream = function(sdist, grab_focus) {
        var new_sstr = egCore.idl.toTypedHash(new egCore.idl.sstr());
        new_sstr.distribution = sdist.id;
        new_sstr._isnew = true;
        if (grab_focus) {
            new_sstr._focus_me = true;
            sdist._has_focus = false; // and take focus away from a newly created sdist
        }
        if (!angular.isArray(sdist.streams)){
            sdist.streams = [];
        }
        sdist.streams.push(new_sstr);
        $scope.dirtyForm();
    }
    $scope.remove_pending_stream = function(sdist, sstr) {
        var to_remove = -1;
        for (var i = 0; i < sdist.streams.length; i++) {
            if (sdist.streams[i] === sstr) {
                to_remove = i;
                break;
            }
        }
        if (to_remove > -1) {
            sdist.streams.splice(to_remove, 1);
        }
    }

    $scope.abort_changes = function(form) {
        reload();
        form.$setPristine();
    }
    function updateLocalStreamNames (new_name) {
        if (new_name && $scope.localStreamNames.filter(function(x){ return x == new_name}).length == 0) {
            $scope.localStreamNames.push(new_name);
            egCore.hatch.setItem('eg.serials.stream_names', $scope.localStreamNames)
        }
    }

    $scope.dirtyForm = function () {
        $scope.ssubform.$dirty = true;
    }

    $scope.save_subscriptions = function(form) {
        // traverse through structure and set _ischanged
        // TODO add more granular dirty input detection
        angular.forEach($scope.subscriptions, function(ssub) {
            if (!ssub._isnew) ssub._ischanged = true;
            angular.forEach(ssub.distributions, function(sdist) {
                if (!sdist._isnew) sdist._ischanged = true;
                angular.forEach(sdist.streams, function(sstr) {
                    if (!sstr._isnew) sstr._ischanged = true;
                    updateLocalStreamNames(sstr.routing_label);
                });
            });
        });

        var obj = egCore.idl.fromTypedHash($scope.subscriptions);

        // create a bunch of promises that each get resolved upon each
        // CUD update; that way, we can know when the entire save
        // operation is completed
        var promises = [];
        angular.forEach(obj, function(ssub) {
            ssub._cud_done = $q.defer();
            promises.push(ssub._cud_done.promise);
            angular.forEach(ssub.distributions(), function(sdist) {
                sdist._cud_done = $q.defer();
                promises.push(sdist._cud_done.promise);
                angular.forEach(sdist.streams(), function(sstr) {
                    sstr._cud_done = $q.defer();
                    promises.push(sstr._cud_done.promise);
                });
            });
        });

        angular.forEach(obj, function(ssub) {
            ssub.owning_lib(ssub.owning_lib().id()); // deflesh
            egCore.pcrud.apply(ssub).then(function(res) {
                var ssub_id = (ssub.isnew() && angular.isObject(res)) ? res.id() : ssub.id();
                angular.forEach(ssub.distributions(), function(sdist) {
                    // set subscription ID just in case it's new
                    sdist.holding_lib(sdist.holding_lib().id()); // deflesh
                    sdist.subscription(ssub_id);
                    egCore.pcrud.apply(sdist).then(function(res) {
                        var sdist_id = (sdist.isnew() && angular.isObject(res)) ? res.id() : sdist.id();
                        angular.forEach(sdist.streams(), function(sstr) {
                            // set distribution ID just in case it's new
                            sstr.distribution(sdist_id);
                            egCore.pcrud.apply(sstr).then(function(res) {
                                sstr._cud_done.resolve();
                            });
                        });
                    });
                    sdist._cud_done.resolve();
                });
                ssub._cud_done.resolve();
            });
        });
        $q.all(promises).then(function(resolutions) {
            reload();
            form.$setPristine();
        });
    }
    $scope.delete_subscription = function(rows) {
        if (rows.length == 0) { return; }
        var s_rows = rows.filter(function(el) {
            return typeof el['id'] != 'undefined';
        });
        if (s_rows.length == 0) { return; }
        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_SUBSCRIPTION,
            egCore.strings.CONFIRM_DELETE_SUBSCRIPTION_MESSAGE,
            {count : s_rows.length}
        ).result.then(function () {
            var promises = [];
            angular.forEach(s_rows, function(el) {
                promises.push(
                    egCore.net.request(
                        'open-ils.serial',
                        'open-ils.serial.subscription.safe_delete',
                        egCore.auth.token(),
                        el['id']
                    ).then(function(resp){
                        var evt = egCore.evt.parse(resp);
                        if (evt) {
                            ngToast.danger(egCore.strings.SERIALS_SUBSCRIPTION_FAIL_DELETE + ' : ' + evt.desc);
                        } else {
                            ngToast.success(egCore.strings.SERIALS_SUBSCRIPTION_SUCCESS_DELETE);
                        }
                    })
                );
            });
            $q.all(promises).then(function() {
                reload();
            });
        });
    }
    $scope.delete_distribution = function(rows) {
        if (rows.length == 0) { return; }
        var d_rows = rows.filter(function(el) {
            return typeof el['sdist.id'] != 'undefined';
        });
        if (d_rows.length == 0) { return; }
        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_DISTRIBUTION,
            egCore.strings.CONFIRM_DELETE_DISTRIBUTION_MESSAGE,
            {count : d_rows.length}
        ).result.then(function () {
            var promises = [];
            angular.forEach(d_rows, function(el) {
                promises.push(
                    egCore.net.request(
                        'open-ils.serial',
                        'open-ils.serial.distribution.safe_delete',
                        egCore.auth.token(),
                        el['sdist.id']
                    ).then(function(resp){
                        var evt = egCore.evt.parse(resp);
                        if (evt) {
                            ngToast.danger(egCore.strings.SERIALS_DISTRIBUTION_FAIL_DELETE + ' : ' + evt.desc);
                        } else {
                            ngToast.success(egCore.strings.SERIALS_DISTRIBUTION_SUCCESS_DELETE);
                        }
                    })
                );
            });
            $q.all(promises).then(function() {
                reload();
            });
        });
    }
    $scope.delete_stream = function(rows) {
        if (rows.length == 0) { return; }
        var s_rows = rows.filter(function(el) {
            return typeof el['sstr.id'] != 'undefined';
        });
        if (s_rows.length == 0) { return; }
        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_STREAM,
            egCore.strings.CONFIRM_DELETE_STREAM_MESSAGE,
            {count : s_rows.length}
        ).result.then(function () {
            var promises = [];
            angular.forEach(s_rows, function(el) {
                promises.push(
                    egCore.net.request(
                        'open-ils.serial',
                        'open-ils.serial.stream.safe_delete',
                        egCore.auth.token(),
                        el['sstr.id']
                    ).then(function(resp){
                        var evt = egCore.evt.parse(resp);
                        if (evt) {
                            ngToast.danger(egCore.strings.SERIALS_STREAM_FAIL_DELETE + ' : ' + evt.desc);
                        } else {
                            ngToast.success(egCore.strings.SERIALS_STREAM_SUCCESS_DELETE);
                        }
                    })
                );
            });
            $q.all(promises).then(function() {
                reload();
            });
        });
    }
    $scope.additional_routing = function(rows) {
        if (!rows) { return; }
        var row = rows[0];
        if (!row) { row = $scope.distStreamGridControls.selectedItems()[0]; }
        if (row && row['sstr.id']) {
            egCore.pcrud.search('srlu', {
                    stream : row['sstr.id']
                }, {
                    flesh : 2,
                    flesh_fields : {
                        'srlu' : ['reader'],
                        'au'  : ['mailing_address','billing_address','home_ou']
                    },
                    order_by : { srlu : 'pos' }
                },
                { atomic : true }
            ).then(function(list) {
                $uibModal.open({
                    templateUrl: './serials/t_routing_list',
                    backdrop: 'static',
                    controller: 'RoutingCtrl',
                    resolve : {
                        rowInfo : function() {
                            return row;
                        },
                        routes : function() {
                            return egCore.idl.toHash(list);
                        }
                    }
                }).result.then(function(routes) {
                    // delete all of the routes first;
                    // it's easiest given the constraints
                    var deletions = [];
                    var creations = [];
                    angular.forEach(routes, function(r) {
                        var srlu = new egCore.idl.srlu();
                        srlu.stream(r.stream);
                        srlu.pos(r.pos);
                        if (r.reader) {
                            srlu.reader(r.reader.id);
                        }
                        srlu.department(r.department);
                        srlu.note(r.note);
                        if (r.id) {
                            srlu.id(r.id);
                            var srlu_copy = angular.copy(srlu);
                            srlu_copy.isdeleted(true);
                            deletions.push(srlu_copy);
                        }
                        if (!r.delete_me) {
                            srlu.isnew(true);
                            creations.push(srlu);
                        }
                    });
                    egCore.pcrud.apply(deletions.concat(creations)).then(function(){
                        reload();
                    });
                });
            });
        }
    }
    $scope.clone_subscription = function(rows) {
        if (!rows) { return; }
        var row = rows[0];
        $uibModal.open({
            templateUrl: './serials/t_clone_subscription',
            controller: 'CloneCtrl',
            resolve : {
                subs : function() {
                    return rows;
                }
            },
            windowClass: 'app-modal-window',
            backdrop: 'static',
            keyboard: false
        }).result.then(function(args) {
            var promises = [];
            var some_failure = false;
            var some_success = false;
            var seen = {};
            angular.forEach(rows, function(row) { 
                //console.log(row);
                if (!seen[row.id]) {
                    seen[row.id] = 1;
                    promises.push(
                        egCore.net.request(
                            'open-ils.serial',
                            'open-ils.serial.subscription.clone',
                            egCore.auth.token(),
                            row.id,
                            args.bib_id
                        ).then(
                            function(resp) {
                                var evt = egCore.evt.parse(resp);
                                if (evt) { // any way to just throw or return this to the error handler?
                                    console.log('failure',resp);
                                    some_failure = true;
                                    ngToast.danger(egCore.strings.SERIALS_SUBSCRIPTION_FAIL_CLONE);
                                } else {
                                    console.log('success',resp);
                                    some_success = true;
                                    ngToast.success(egCore.strings.SERIALS_SUBSCRIPTION_SUCCESS_CLONE);
                                }
                            },
                            function(resp) {
                                console.log('failure',resp);
                                some_failure = true;
                                ngToast.danger(egCore.strings.SERIALS_SUBSCRIPTION_FAIL_CLONE);
                            }
                        )
                    );
                }
            });
            $q.all(promises).then(function() {
                reload();
            });
        });
    }
    $scope.link_mfhd = function(rows) {
        if (!rows) { return; }
        var row = rows[0];
        if (!row['sdist.id']) { return; }
        $uibModal.open({
            templateUrl: './serials/t_link_mfhd',
            controller: 'LinkMFHDCtrl',
            resolve : {
                row : function() {
                    return rows[0];
                },
                bibId : function() {
                    return $scope.bibId;
                }
            },
            windowClass: 'app-modal-window',
            backdrop: 'static',
            keyboard: false
        }).result.then(function(args) {
            console.log('modal done', args);
            egCore.pcrud.search('sdist', {
                    id: rows[0]['sdist.id']
                }, {}, { atomic : true }
            ).then(function(resp){
                var evt = egCore.evt.parse(resp);
                if (evt) { // any way to just throw or return this to the error handler?
                    console.log('failure',resp);
                    ngToast.danger(egCore.strings.SERIALS_DISTRIBUTION_FAIL_LINK_MFHD);
                }
                var sdist = resp[0];
                sdist.ischanged(true);
                sdist.summary_method( args.summary_method );
                sdist.record_entry( args.which_mfhd );
                egCore.pcrud.apply(sdist).then(
                    function(resp) { // maybe success
                        console.log('apply',resp);
                        var evt = egCore.evt.parse(resp);
                        if (evt) { // any way to just throw or return this to the error handler?
                            console.log('failure',resp);
                            ngToast.danger(egCore.strings.SERIALS_DISTRIBUTION_FAIL_LINK_MFHD);
                        } else {
                            console.log('success',resp);
                            ngToast.success(egCore.strings.SERIALS_DISTRIBUTION_SUCCESS_LINK_MFHD);
                            reload();
                        }
                    },
                    function(resp) {
                        console.log('failure',resp);
                        ngToast.danger(egCore.strings.SERIALS_DISTRIBUTION_FAIL_LINK_MFHD);
                    }
                );
            });
        });
    }
    $scope.apply_binding_template = function(rows) {
        if (rows.length == 0) { return; }
        var d_rows = rows.filter(function(el) {
            return typeof el['sdist.id'] != 'undefined';
        });
        if (d_rows.length == 0) { return; }
        var libs = []; var seen_lib = {};
        angular.forEach(d_rows, function(el) {
            if (el['sdist.holding_lib.id'] && !seen_lib[el['sdist.holding_lib.id']]) {
                seen_lib[el['sdist.holding_lib.id']] = 1;
                libs.push({
                      id: el['sdist.holding_lib.id'],
                    name: el['sdist.holding_lib.name'],
                });
            }
        });
        $uibModal.open({
            templateUrl: './serials/t_apply_binding_template',
            controller: 'ApplyBindingTemplateCtrl',
            resolve : {
                rows : function() {
                    return d_rows;
                },
                libs : function() {
                    return libs;
                }
            },
            windowClass: 'app-modal-window',
            backdrop: 'static',
            keyboard: false
        }).result.then(function(args) {
            console.log(args);
            egCore.pcrud.search('sdist', {
                    id: d_rows.map(function(el) { return el['sdist.id']; })
                }, {}, { atomic : true }
            ).then(function(resp){
                var evt = egCore.evt.parse(resp);
                if (evt) { // any way to just throw or return this to the error handler?
                    console.log('failure',resp);
                    ngToast.danger(egCore.strings.SERIALS_DISTRIBUTION_FAIL_BINDING_TEMPLATE);
                }
                var promises = [];
                angular.forEach(resp,function(sdist) {
                    var promise = $q.defer();
                    promises.push(promise.promise);
                    sdist.ischanged(true);
                    sdist.bind_unit_template(
                        typeof args.bind_unit_template[sdist.holding_lib()] == 'undefined'
                        ? null
                        : args.bind_unit_template[sdist.holding_lib()]
                    );
                    egCore.pcrud.apply(sdist).then(
                        function(resp2) { // maybe success
                            console.log('apply',resp2);
                            var evt = egCore.evt.parse(resp2);
                            if (evt) { // any way to just throw or return this to the error handler?
                                console.log('failure',resp2);
                                ngToast.danger(egCore.strings.SERIALS_DISTRIBUTION_FAIL_BINDING_TEMPLATE);
                            } else {
                                console.log('success',resp2);
                                ngToast.success(egCore.strings.SERIALS_DISTRIBUTION_SUCCESS_BINDING_TEMPLATE);
                            }
                            promise.resolve();
                        },
                        function(resp2) {
                            console.log('failure',resp2);
                            ngToast.danger(egCore.strings.SERIALS_DISTRIBUTION_FAIL_BINDING_TEMPLATE);
                            promise.resolve();
                        }
                    );
                });
                $q.all(promises).then(function() {
                    reload();
                });
            });
        });
    }
    $scope.subscription_notes = function(rows) {
        return $scope.notes('subscription',rows);
    }
    $scope.distribution_notes = function(rows) {
        return $scope.notes('distribution',rows);
    }
    $scope.notes = function(note_type,rows) {
        if (!rows) { return; }

        function modal(existing_notes) {
            $uibModal.open({
                templateUrl: './serials/t_notes',
                animation: true,
                controller: 'NotesCtrl',
                resolve : {
                    note_type : function() { return note_type; },
                    rows : function() {
                        return rows;
                    },
                    notes : function() {
                        return existing_notes;
                    }
                },
                windowClass: 'app-modal-window',
                backdrop: 'static',
                keyboard: false
            }).result.then(function(notes) {
                console.log('results',notes);
                egCore.pcrud.apply(notes).then(
                    function(a) { console.log('toast here 1',a); },
                    function(a) { console.log('toast here 2',a); }
                );
            });
        }

        if (rows.length == 1) {
            var fm_hint;
            var search_hash = {};
            var search_opt = {};
            switch(note_type) {
                case 'subscription':
                    fm_hint = 'ssubn';
                    search_hash.subscription = rows[0]['id'];
                    search_opt.order_by = { ssubn : 'create_date' };
                break;
                case 'distribution':
                    fm_hint = 'sdistn';
                    search_hash.distribution = rows[0]['sdist.id'];
                    search_opt.order_by = { sdistn : 'create_date' };
                break;
                case 'item': default:
                    fm_hint = 'sin';
                    search_hash.item = rows[0]['si.id'];
                    search_opt.order_by = { sin : 'create_date' };
                break;
            }
            egCore.pcrud.search(fm_hint, search_hash, search_opt,
                { atomic : true }
            ).then(function(list) {
                modal(list);
            });
        } else {
                // support batch creation of notes across selections,
                // but not editing
                modal([]);
        }
    }

}]
    }
})

.controller('ApplyBindingTemplateCtrl',
       ['$scope','$q','$uibModalInstance','egCore','egSerialsCoreSvc',
        'rows','libs',
function($scope , $q , $uibModalInstance , egCore , egSerialsCoreSvc ,
         rows , libs ) {
    $scope.ok = function(count) { $uibModalInstance.close($scope.args) }
    $scope.cancel = function () { $uibModalInstance.dismiss() }
    $scope.libs = libs;
    $scope.rows = rows;
    $scope.args = { bind_unit_template : {} };
    $scope.templates = {};
    angular.forEach(libs, function(org) {
        egSerialsCoreSvc.fetch_templates(org.id).then(function(list){
            $scope.templates[org.id] = egCore.idl.toTypedHash(list);
        });
    });
}])

.controller('LinkMFHDCtrl',
       ['$scope','$q','$uibModalInstance','egCore','row','bibId',
function($scope , $q , $uibModalInstance , egCore , row , bibId ) {
    console.log('row',row);
    console.log('bibId',bibId);
    $scope.args = {
        summary_method: row['sdist.summary_method'] || 'add_to_sre',
    };
    if (row['sdist.record_entry']) {
        $scope.args.which_mfhd = row['sdist.record_entry'].id;
    }
    $scope.ok = function(count) { $uibModalInstance.close($scope.args) }
    $scope.cancel = function () { $uibModalInstance.dismiss() }
    $scope.legacies = {};
    egCore.pcrud.search('sre', {
            record: bibId, owning_lib : row['sdist.holding_lib.id'], active: 't', deleted: 'f'
        }, {}, { atomic : true }
    ).then(
        function(resp) { // maybe success
            var evt; if (evt = egCore.evt.parse(resp)) { console.error(evt.toString()); return; }
            if (!resp) { return; }

            var promises = [];
            var seen = {};

            angular.forEach(resp, function(sre) {
                console.log('sre',sre);
                if (!seen[sre.record()]) {
                    seen[sre.record()] = 1;
                    $scope.legacies[sre.record()] = { mvr: null, svrs: [] };
                    promises.push(
                        egCore.net.request(
                            'open-ils.search',
                            'open-ils.search.biblio.record.mods_slim.retrieve.authoritative',
                            sre.record()
                        ).then(function(resp2) {
                            var evt; if (evt = egCore.evt.parse(resp2)) { console.error(evt.toString()); return; }
                            if (!resp2) { return; }
                            $scope.legacies[sre.record()].mvr = egCore.idl.toHash(resp2);
                        })
                    );
                    promises.push(
                        egCore.net.request(
                            'open-ils.search',
                            'open-ils.search.serial.record.bib.retrieve',
                            sre.record(),
                            row['owning_lib.id']
                        ).then(function(resp2) {
                            angular.forEach(resp2,function(r) {
                                if (r.sre_id() > 0) {
                                    console.log('svr',egCore.idl.toHash(r));
                                    $scope.legacies[sre.record()].svrs.push( egCore.idl.toHash(r) );
                                }
                            });
                        })
                    );
                }
                if (typeof $scope.legacies[sre.record()].sres == 'undefined') {
                    $scope.legacies[sre.record()].sres = {};
                }
                $scope.legacies[sre.record()].sres[sre.id()] = egCore.idl.toHash(sre);
            });

            $q.all(promises).then(function(){
                console.log('done',$scope.legacies);
            });
        },
        function(resp) { // outright failure
            console.error('failure',resp);
        }
    )
}])

.controller('CloneCtrl',
       ['$scope','$uibModalInstance','egCore','subs',
function($scope , $uibModalInstance , egCore , subs ) {
    $scope.args = {};
    $scope.ok = function(count) { $uibModalInstance.close($scope.args) }
    $scope.cancel = function () { $uibModalInstance.dismiss() }
    $scope.subs = subs;
    $scope.find_bib = function () {

        $scope.bibNotFound = null;
        $scope.mvr = null;
        if (!$scope.args.bib_id) return;

        return egCore.net.request(
            'open-ils.search',
            'open-ils.search.biblio.record.mods_slim.retrieve.authoritative',
            $scope.args.bib_id
        ).then(
            function(resp) { // maybe success 

                if (evt = egCore.evt.parse(resp)) {
                    $scope.bibNotFound = $scope.args.bib_id;
                    console.error(evt.toString());
                    return;
                }

                if (!resp) {
                    $scope.bibNotFound = $scope.args.bib_id;
                    return;
                }

                $scope.mvr = egCore.idl.toHash(resp);
                //console.log($scope.mvr);
            },
            function(resp) { // outright failure
                console.error(resp);
                $scope.bibNotFound = $scope.args.bib_id;
                return;
            }
        );
    }
    $scope.$watch("args.bib_id", function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.find_bib();
        }
    });
}])

.controller('RoutingCtrl',
       ['$scope','$uibModalInstance','egCore','rowInfo','routes',
function($scope , $uibModalInstance , egCore , rowInfo , routes ) {
    $scope.args = {
         which_radio_button: 'reader'
        ,reader: ''
        ,department: ''
        ,delete_me: false
    };
    $scope.stream_id = rowInfo['sstr.id'];
    $scope.stream_label = rowInfo['sstr.routing_label'];
    $scope.routes = routes;
    $scope.readerInFocus = true;
    $scope.ok = function(count) { $uibModalInstance.close($scope.routes) }
    $scope.cancel = function () { $uibModalInstance.dismiss() }
    $scope.model_has_changed = false;
    $scope.find_user = function () {

        $scope.readerNotFound = null;
        $scope.reader_obj = null;
        if (!$scope.args.reader) return;

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            egCore.auth.token(), egCore.auth.user().ws_ou(),
            'actor', $scope.args.reader)

        .then(function(resp) { // get_barcodes

            if (evt = egCore.evt.parse(resp)) {
                console.error(evt.toString());
                return;
            }

            if (!resp || !resp[0]) {
                $scope.readerNotFound = $scope.args.reader;
                return;
            }

            egCore.pcrud.search('au', {
                    id : resp[0].id
                }, {
                    flesh : 1,
                    flesh_fields : {
                        'au'  : ['mailing_address','billing_address','home_ou']
                    }
                },
                { atomic : true }
            ).then(function(usr) {
                $scope.reader_obj = egCore.idl.toHash(usr[0]);
            });
        });
    }
    $scope.add_route = function () {
        var new_route = {
             stream: $scope.stream_id
            ,pos: $scope.routes.length
            ,note: $scope.args.note
        }
        if ($scope.args.which_radio_button == 'reader') {
            new_route.reader = $scope.reader_obj;
        } else {
            new_route.department = $scope.args.department;
        }
        $scope.routes.push(new_route);
        $scope.model_has_changed = true;
    }
    function adjust_pos_field() {
        var idx = 0;
        for (var i = 0; i < $scope.routes.length; i++) {
            $scope.routes[i].pos = $scope.routes[i].delete_me ? idx : idx++;
        }
        $scope.model_has_changed = true;
    }
    $scope.move_route_up = function(r) {
        var pos = r.pos;
        if (pos > 0) {
            var temp = $scope.routes[ pos - 1 ];
            $scope.routes[ pos - 1 ] = $scope.routes[ pos ];
            $scope.routes[ pos ] = temp;
            adjust_pos_field();
        }
    }
    $scope.move_route_down = function(r) {
        var pos = r.pos;
        if (pos < $scope.routes.length - 1) {
            var temp = $scope.routes[ pos + 1 ];
            $scope.routes[ pos + 1 ] = $scope.routes[ pos ];
            $scope.routes[ pos ] = temp;
            adjust_pos_field();
        }
    }
    $scope.toggle_delete = function(r) {
        r.delete_me = ! r.delete_me;
        adjust_pos_field();
    }
    $scope.$watch("args.reader", function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.find_user();
        }
    });
}])

.controller('NotesCtrl',
       ['$scope','$uibModalInstance','egCore','note_type','rows','notes',
function($scope , $uibModalInstance , egCore , note_type , rows , notes ) {
    $scope.note_type = note_type;
    $scope.focusNote = true;
    $scope.note = {
        creator : egCore.auth.user().id(),
        title   : '',
        value   : '',
        pub     : false,
        'alert' : false,
    };

    $scope.note_list = notes;

    $scope.ok = function(note) {

        var return_notes = [];
        if (note.initials) note.value += ' [' + note.initials + ']';
        if (   (typeof note.title != 'undefined' && note.title != '')
            || (typeof note.value != 'undefined' && note.value != '')) {
            angular.forEach(rows, function (r) {
                console.log('r',r);
                window.my_r = r;
                var n;
                switch(note_type) {
                    case 'subscription':
                        n = new egCore.idl.ssubn();
                        n.subscription(r['id']);
                        break;
                    case 'distribution':
                        n = new egCore.idl.sdistn();
                        n.distribution(r['sdist.id']);
                        break;
                    case 'item':
                    default:
                        n = new egCore.idl.sin();
                        n.item(r['si.id']);
                }
                n.isnew(true);
                n.creator(note.creator);
                n.pub(note.pub);
                n['alert'](note['alert']);
                n.title(note.title);
                n.value(note.value);
                return_notes.push( n );
            });
        }
        angular.forEach(notes, function(n) {
            if (n.ischanged() || n.isdeleted()) {
                return_notes.push( n );
            }
        });
        window.return_notes = return_notes;
        $uibModalInstance.close(return_notes);
    }

    $scope.cancel = function($event) {
        $uibModalInstance.dismiss();
        $event.preventDefault();
    }
}])
