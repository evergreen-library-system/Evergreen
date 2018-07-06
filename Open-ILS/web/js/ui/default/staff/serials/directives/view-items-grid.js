angular.module('egSerialsAppDep')

.directive('egItemGrid', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            bibId  : '=',
            ssubId : '='
        },
        templateUrl: './serials/t_view_items_grid',
        controller:
       ['$scope','$q','egSerialsCoreSvc','egCore','egGridDataProvider','orderByFilter',
        '$uibModal','ngToast','egConfirmDialog','egPromptDialog','$timeout',
function($scope , $q , egSerialsCoreSvc , egCore , egGridDataProvider , orderByFilter ,
         $uibModal , ngToast , egConfirmDialog , egPromptDialog , $timeout) {

    $scope.svc = egSerialsCoreSvc;

    var _paging_filter;
    function reload(ssubId,filter) {
        _paging_filter = filter;
        return egSerialsCoreSvc.fetchItemsForSub(ssubId,filter).then(function() {
            $scope.itemGridProvider.refresh();
        });
    }

    $scope.filter_items_all = function () { return reload($scope.ssubId) }
    $scope.filter_items_have = function () { return reload($scope.ssubId,{status:['Received','Bindery','Bound']}) }
    $scope.filter_items_dont_have = function () { return reload($scope.ssubId,{'-not':{status:['Received','Bindery','Bound']}}) }
    $scope.filter_items_by_status = function (item,status) { return reload($scope.ssubId,{status:status.name}) }

    $scope.$watch('ssubId', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) return reload(newVal);
    });

    $scope.itemGridControls = {
        activateItem : function (item) { } // TODO
    };

    function compileSort(sort) {
        if (sort && angular.isArray(sort) && sort.length == 1) {
            if (angular.isObject(sort[0])) {
                for (key in sort[0]) {
                    return {
                        'class'   : 'sitem',
                        field     :  key,
                        direction : sort[0][key]
                    };
                }
            } else {
                return { 'class': 'sitem', field: sort[0] };
            }
        }
    }
    var current_sort = [];
    $scope.itemGridProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            var self = this;
            if (angular.equals(current_sort, self.sort) && egSerialsCoreSvc.itemList.length >= offset + count) { // if there's anything on the requested page, notify
                return self.arrayNotifier(egSerialsCoreSvc.itemList, offset, count);
            } else { // else try to fetch another page
                if (angular.equals(current_sort, self.sort)) {
                    return egSerialsCoreSvc.fetchItemsForSubPaged(
                        $scope.ssubId,
                        _paging_filter,
                        egSerialsCoreSvc.itemList.length,
                        count + offset - egSerialsCoreSvc.itemList.length,
                        compileSort(self.sort)
                    ).then(function() {
                        return self.arrayNotifier(egSerialsCoreSvc.itemList, offset, count);
                    });
                } else {
                    current_sort = self.sort;
                    return egSerialsCoreSvc.fetchItemsForSub(
                        $scope.ssubId,
                        _paging_filter,
                        null,
                        compileSort(self.sort)
                    ).then(function() {
                        return self.arrayNotifier(egSerialsCoreSvc.itemList, offset, count);
                    });
                }
            }
        }
    });

    $scope.delete_items = function (items) {
        var list = [];

        angular.forEach(items, function (i) {
            var obj = egSerialsCoreSvc.itemMap[i.id];
            obj.isdeleted(1);
            list.push(obj);
        });

        egConfirmDialog.open(
            egCore.strings.CONFIRM_CHANGE_ITEMS.delete,
            egCore.strings.CONFIRM_CHANGE_ITEMS_MESSAGE.delete,
            {items : list.length}
        ).result.then(function () {
            return egCore.net.request(
                'open-ils.serial',
                'open-ils.serial.item.fleshed.batch.update',
                egCore.auth.token(),
                list
            ).then( function(resp) {
                var evt = egCore.evt.parse(resp);
                if (evt) {
                    ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                } else {
                    ngToast.success(egCore.strings.SERIALS_ISSUANCE_SUCCESS_SAVE);
                    return reload($scope.ssubId,_paging_filter);
                }
            });
        });
    }

    $scope.edit_issuance_holding_code = function (items) {
        var promises = [];
        var edits = [];
        angular.forEach(items.reverse(), function (item) {
            promises.push( egSerialsCoreSvc.new_holding_code({
                    title    : egCore.strings.SERIALS_EDIT_SISS_HC,
                    curr_iss : egCore.idl.fromHash('siss',item.issuance),
                    label    : item.issuance.label,
                    type     : item.issuance.type ? item.issuance.type : 'basic',
                    can_change_adhoc : true
                }).then(function(result) {
                    if (!result.adhoc) {
                        item.issuance.holding_code = JSON.stringify(result.holding_code);
                        item.issuance.holding_type = result.type;
                    } else {
                        item.issuance.label = result.label;
                        item.issuance.holding_type = result.type;
                    }

                    item.issuance.date_published = result.date.toISOString();
                    item.issuance.editor = egCore.auth.user();
                    item.issuance.edit_date = 'now';

                    var iss = egCore.idl.fromHash('siss',item.issuance);
                    if (!result.adhoc) { // not an ad hoc issuance, get predicted label
                        return egCore.net.request(
                            'open-ils.serial',
                            'open-ils.serial.make_prediction_values',
                            egCore.auth.token(),
                            { ssub_id : $scope.ssubId,
                              num_to_predict : 0,
                              include_base_issuance : 1,
                              base_issuance : iss
                            }
                        ).then( function(resp) {
                            var evt = egCore.evt.parse(resp);
                            if (evt) {
                                ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                            } else {
                                iss.label(resp[0].label);
                                edits.push(iss);
                            }
                        });
                    }

                    return $q.when(edits.push(iss));
                })
            );
        });
        return $q.all(promises)
            .finally(function() {
                if (edits.length) return update_issuances(edits);
            });
    }


    function update_issuances (list) {
        if (!angular.isArray(list)) list = [list];

        return egCore.net.request(
            'open-ils.serial',
                'open-ils.serial.issuance.fleshed.batch.update',
                egCore.auth.token(),
                list
            ).then(
                function(resp) {
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                    } else {
                        ngToast.success(egCore.strings.SERIALS_ISSUANCE_SUCCESS_SAVE);
                        return reload($scope.ssubId,_paging_filter);
                    }
                },
                function(resp) {
                    ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                }
            );
    }


    $scope.following_issuance = function (items) {
        return egSerialsCoreSvc.new_holding_code({
            title : egCore.strings.SERIALS_ISSUANCE_ADD,
            prev_iss : egCore.idl.fromHash('siss',items[0].issuance),
            can_change_adhoc : true
        }).then(function(hc) {
            if (hc.adhoc) {
                var new_iss = new egCore.idl.siss();
                new_iss.creator( egCore.auth.user().id() );
                new_iss.editor( egCore.auth.user().id() );
                new_iss.date_published( hc.date.toISOString() );
                new_iss.subscription( $scope.ssubId );
                new_iss.label( hc.label );
                new_iss.holding_type( hc.type );

                return egCore.pcrud.create(new_iss).then(function(issuance) {
                    var new_item = new egCore.idl.sitem();
                    new_item.creator( egCore.auth.user().id() );
                    new_item.editor( egCore.auth.user().id() );
                    new_item.issuance( issuance.id() );
                    new_item.stream( items[0].stream.id );
                    new_item.date_expected( hc.date.toISOString() ); // XXX do we have interval math?

                    return egCore.pcrud.create(new_item).then(function() {
                        ngToast.success(egCore.strings.SERIALS_ISSUANCE_SUCCESS_SAVE);
                        return reload($scope.ssubId,_paging_filter);
                    },function (error) {
                        ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                    });
                },function (error) {
                    ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                });
            }

            return egCore.net.request(
                'open-ils.serial',
                'open-ils.serial.make_predictions',
                egCore.auth.token(),
                { ssub_id : $scope.ssubId,
                  num_to_predict : 1,
                  base_issuance : egCore.idl.fromHash('siss',items[0].issuance)
                }
            ).then(
                function(resp) {
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                    } else {
                        ngToast.success(egCore.strings.SERIALS_ISSUANCE_SUCCESS_SAVE);
                        return reload($scope.ssubId,_paging_filter);
                    }
                },
                function(resp) {
                    ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                }
            );
        });
    }

    $scope.add_special_issuance = function() {
        return egSerialsCoreSvc.new_holding_code({
            title : egCore.strings.SERIALS_SPECIAL_ISSUANCE_ADD,
            can_change_adhoc : false,
            adhoc       : true
        }).then(function(hc) {
            // perforce add hoc
            var new_iss = new egCore.idl.siss();
            new_iss.creator( egCore.auth.user().id() );
            new_iss.editor( egCore.auth.user().id() );
            new_iss.date_published( hc.date.toISOString() );
            new_iss.subscription( $scope.ssubId );
            new_iss.label( hc.label );
            new_iss.holding_type( hc.type );

            return egCore.pcrud.create(new_iss).then(function(issuance) {
                var new_items = [];
                var sub = egSerialsCoreSvc.get_ssub($scope.ssubId);
                angular.forEach(sub.distributions(), function(dist) {
                    angular.forEach(dist.streams(), function(stream) {
                        var new_item = new egCore.idl.sitem();
                        new_item.creator( egCore.auth.user().id() );
                        new_item.editor( egCore.auth.user().id() );
                        new_item.issuance( issuance.id() );
                        new_item.stream( stream.id() );
                        new_item.date_expected( hc.date.toISOString() ); // XXX do we have interval math?
                        new_items.push(new_item);
                    });
                });
                var promises = [];
                angular.forEach(new_items, function(item) {
                    promises.push(egCore.pcrud.create(item));
                });

                $q.all(promises).then(function() {
                    ngToast.success(egCore.strings.SERIALS_ISSUANCE_SUCCESS_SAVE);
                    return reload($scope.ssubId,_paging_filter);
                },function (error) {
                    ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                });
            });
        });
    }

    $scope.do_print_routing_lists = false;
    egCore.hatch.getItem('eg.serials.items.do_print_routing_lists').then(function(val) {
        $scope.do_print_routing_lists = val;
    });

    $scope.receive_and_barcode = false;
    egCore.hatch.getItem('eg.serials.items.receive_and_barcode').then(function(val) {
        $scope.receive_and_barcode = val;
    });

    $scope.checkbox_handler = function(item) {
        $scope[item.checkbox] = item.checked;
        egCore.hatch.setItem('eg.serials.items.'+item.checkbox, item.checked);
    }

    $scope.receive_next = function () {
        var list = [];
        var next_per_stream = {};
        angular.forEach(egSerialsCoreSvc.itemTree, function (item) {
            if (next_per_stream[item.stream().id()]) return;
            if (item.status() == 'Expected') {
                next_per_stream[item.stream().id()] = item;
                list.push(egCore.idl.Clone(item));
            }
        });

        return egSerialsCoreSvc.process_items('receive', $scope.bibId, list, $scope.receive_and_barcode, false, $scope.do_print_routing_lists, function(){reload($scope.ssubId,_paging_filter)});
    }

    $scope.receive_selected = function (list) {
        var items = list.filter(function(i){
            return i.status == 'Expected';
        });
        return egSerialsCoreSvc.process_items('receive', $scope.bibId, items.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        }), $scope.receive_and_barcode, false, $scope.do_print_routing_lists, function(){reload($scope.ssubId,_paging_filter)});
    }

    $scope.reset_selected = function (list) {
        return egSerialsCoreSvc.process_items('reset', $scope.bibId, list.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        }), false, false, false, function(){reload($scope.ssubId,_paging_filter)});
    }

    $scope.bind_selected = function (list) {
        return egSerialsCoreSvc.process_items('bind', $scope.bibId, list.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        }), true, true, $scope.do_print_routing_lists, function(){reload($scope.ssubId,_paging_filter)});
    }

    $scope.set_selected_as_claimed = function(list) {
        return egSerialsCoreSvc.set_item_status('Claimed', $scope.bibId, list.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        }), function(){reload($scope.ssubId,_paging_filter)});
    }
    $scope.set_selected_as_discarded = function(list) {
        return egSerialsCoreSvc.set_item_status('Discarded', $scope.bibId, list.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        }), function(){reload($scope.ssubId,_paging_filter)});
    }
    $scope.set_selected_as_not_published = function(list) {
        return egSerialsCoreSvc.set_item_status('Not Published', $scope.bibId, list.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        }), function(){reload($scope.ssubId,_paging_filter)});
    }
    $scope.set_selected_as_not_held = function(list) {
        return egSerialsCoreSvc.set_item_status('Not Held', $scope.bibId, list.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        }), function(){reload($scope.ssubId,_paging_filter)});
    }

    $scope.menu_print_routing_lists = function (items) {
        items = items.map(function(item) {
            return egCore.idl.Clone(egSerialsCoreSvc.itemMap[item.id]);
        });
        return egSerialsCoreSvc.print_routing_lists($scope.bibId, items, false, true, $scope.do_print_routing_lists);
    }

    $scope.add_issuances = function () {
        egSerialsCoreSvc.add_issuances($scope.ssubId).then(function() {
            return reload($scope.ssubId,_paging_filter);
        });
    }

    $scope.need_one_selected = function() {
        var items = $scope.itemGridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.need_many_selected = function() {
        var items = $scope.itemGridControls.selectedItems();
        if (items.length > 1) return false;
        return true;
    };

    $scope.need_expected = function() {
        var items = $scope.itemGridControls.selectedItems().filter(function(i){
            return i.status == 'Expected';
        });
        if (items.length) return false;
        return true;
    };

    $scope.item_notes = function(rows) {
        return $scope.notes('item',rows);
    }
    // TODO - refactor this, it's duplicated in subscription_manager.js
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
                egCore.pcrud.apply(notes).then(
                    function(a) { ngToast.success(egCore.strings.SERIALS_ITEM_NOTE_SUCCESS_SAVE) },
                    function(a) { ngToast.danger(egCore.strings.SERIALS_ITEM_NOTE_FAIL_SAVE) }
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
                    search_hash.item = rows[0]['id'];
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

// TODO - refactor this; it's duplicated in subscription_manager.js
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
                        n.item(r['id']);
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
        $uibModalInstance.close(return_notes);
    }

    $scope.cancel = function($event) {
        $uibModalInstance.dismiss();
        $event.preventDefault();
    }
}])
