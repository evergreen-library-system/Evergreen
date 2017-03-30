angular.module('egFmRecordEditorMod',
    ['egCoreMod', 'egUiMod', 'ui.bootstrap'])

.directive('egEditFmRecord', function() {
    return {
        restrict : 'AE',
        transclude : true,
        scope : {
            // IDL class hint (e.g. "aou")
            idlClass : '@',

            // mode: 'create' for creating a new record,
            //       'update' for editing an existing record
            mode : '@',

            // record ID to update
            recordId : '=',

            // comma-separated list of fields that should not be
            // displayed
            hiddenFields : '@',

            // comma-separated list of fields that should always
            // be read-only
            readonlyFields : '@',

            // comma-separated list of required fields; this
            // supplements what the IDL considers required
            requiredFields : '@',

            // hash, keyed by field name, of functions to invoke
            // to check whether a field is required.  Each
            // callback is passed the field name and the record
            // and should return a boolean value. This supports
            // cases where whether a field is required or not
            // depends on the current value of another field.
            isRequiredOverride : '@',

            // reference to handler to run upon saving
            // record. The handler will be passed the
            // record ID and a parameter indicating whether
            // the save did a create or an update. Note that
            // even if the mode of the egEditFmRecord is
            // 'create', the onSave handler may still get
            // 'update' if the user is permitted to create a
            // record, then update it
            onSave : '=',

            // reference to handler to run if the user
            // cancels the dialog
            onCancel : '='

        },

        templateUrl : '/eg/staff/share/t_fm_record_editor',

        controller : [
                    '$scope','egCore',
            function($scope , egCore) {

            function list_to_hash(str) {
                var hash = {};
                if (angular.isString(str)) {
                    str.split(/,/).map(function(s) {
                        hash[s.trim()] = true;
                    });
                }
                return hash;
            }

            $scope.required = list_to_hash($scope.requiredFields);
            $scope.readonly = list_to_hash($scope.readonlyFields);
            $scope.hidden = list_to_hash($scope.hiddenFields);

            $scope.record_label = egCore.idl.classes[$scope.idlClass].label;
            $scope.rec_orgs = {};
            $scope.rec_org_values = {};

            if ($scope.mode == 'update') {
                egCore.pcrud.retrieve($scope.idlClass, $scope.recordId).then(function(r) {
                    $scope.rec = r;
                    convert_datatypes_to_js($scope.rec);
                    $scope.fields = get_field_list();
                });
            } else {
                $scope.rec = new egCore.idl[$scope.idlClass]();
                $scope.fields = get_field_list();
            }

            function convert_datatypes_to_js(rec) {
                var fields = egCore.idl.classes[$scope.idlClass].fields;
                angular.forEach(fields, function(field) {
                    if (field.datatype == 'bool') {
                        if (rec[field.name]() == 't') {
                            rec[field.name](true);
                        } else if (rec[field.name]() == 'f') {
                            rec[field.name](false);
                        }
                    }
                });
            }

            function convert_datatypes_to_idl(rec) {
                var fields = egCore.idl.classes[$scope.idlClass].fields;
                angular.forEach(fields, function(field) {
                    if (field.datatype == 'bool') {
                        if (rec[field.name]() == true) {
                            rec[field.name]('t');
                        } else if (rec[field.name]() == false) {
                            rec[field.name]('f');
                        }
                    }
                });
            }

            function flatten_linked_values(cls, list) {
                var results = [];
                var fields = egCore.idl.classes[cls].fields;
                var id_field;
                var selector;
                angular.forEach(fields, function(fld) {
                    if (fld.datatype == 'id') {
                        id_field = fld.name;
                        selector = fld.selector ? fld.selector : id_field;
                        return;
                    }
                });
                angular.forEach(list, function(item) {
                    var rec = egCore.idl.toHash(item);
                    results.push({
                        id : rec[id_field],
                        name : rec[selector]
                    });
                });
                return results;
            }

            function get_field_list() {
                var fields = egCore.idl.classes[$scope.idlClass].fields;

                angular.forEach(fields, function(field) {
                    field.readonly = (field.name in $scope.readonly);
                    if (angular.isObject($scope.isRequiredOverride) &&
                        field.name in $scope.isRequiredOverride) {
                        field.is_required = function() {
                            return $scope.isRequiredOverride[field.name](field.name, $scope.rec);
                        }
                    } else {
                        field.is_required = function() {
                            return field.required || (field.name in $scope.required);
                        }
                    }
                    if (field.datatype == 'link') {
                    egCore.pcrud.retrieveAll(
                            field.class, {}, {atomic : true}
                        ).then(function(list) {
                            field.linked_values = flatten_linked_values(field.class, list);
                        });
                    }
                    if (field.datatype == 'org_unit') {
                        $scope.rec_orgs[field.name] = function(org) {
                            if (arguments.length == 1) $scope.rec[field.name](org.id());
                            return egCore.org.get($scope.rec[field.name]());
                        }
                        if ($scope.rec[field.name]()) {
                            $scope.rec_org_values[field.name] = $scope.rec_orgs[field.name]();
                        }
                    }
                });
                return fields.filter(function(field) { return !(field.name in $scope.hidden) });
            }

            $scope.ok = function($event) {
                var recToSave = egCore.idl.Clone($scope.rec)
                convert_datatypes_to_idl(recToSave);
                if ($scope.mode == 'update') {
                    egCore.pcrud.update(recToSave).then(function() {
                        $scope.onSave($event);
                    });
                } else {
                    egCore.pcrud.create(recToSave).then(function() {
                        $scope.onSave($event);
                    });
                }
            }
            $scope.cancel = function($event) {
                $scope.onCancel($event);
            }
        }]
    };
})
