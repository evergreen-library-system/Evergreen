/*
 * Retrieve, cache, and query MARC tag tables
 */
angular.module('egCoreMod')
.factory('egTagTable', 
       ['$q', 'egCore', 'egAuth',
function($q,   egCore,   egAuth) {

    var service = {
        defaultTagTableSelector : {
            marcFormat     : 'marc21',
            marcRecordType : 'biblio',
        },
        fields : { },
        ff_pos_map : { },
        ff_value_map : { }
    };

    // allow 'bre' and 'biblio' to be synonyms, etc.
    service.normalizeRecordType = function(recordType) {
        if (recordType === 'sre') {
            return 'serial';
        } else if (recordType === 'bre') {
            return 'biblio';
        } else if (recordType === 'are') {
            return 'authority';
        } else {
            return recordType;
        }
    };

    service.loadTagTable = function(args) {
        var fields = service.defaultTagTableSelector;
        if (args) {
            if (args.marcFormat) {
                fields.marcFormat = args.marcFormat;
            }
            if (args.marcRecordType) {
                fields.marcFormat = service.normalizeRecordType(args.marcFormat);
            }
        }
        var tt_key = 'current_tag_table_' + fields.marcFormat + '_' +
                     fields.marcRecordType;
        egCore.hatch.getItem(tt_key).then(function(tt) {
            if (tt) {
                service.fields = tt;
            } else {
                service.loadRemoteTagTable(fields, tt_key);
            }
        });
    };

    service.fetchFFPosTable = function(rtype) {
        var deferred = $q.defer();

        if (service.ff_pos_map[rtype]) {
            deferred.resolve(service.ff_pos_map[rtype]);
            return deferred.promise;
        }

        egCore.net.request( // First, get the list of FFs (minus 006)
            'open-ils.fielder',
            'open-ils.fielder.cmfpm.atomic',
            { query : { tag : { '!=' : '006' } } }
        ).then(function (data)  {
            service.ff_pos_map[rtype] = data;
        }).then(function() { // Then, get the value maps
            return egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.biblio.fixed_field_values.by_rec_type',
                rtype
            );
        }).then(function (data)  {
            service.ff_value_map[rtype] = data;
            deferred.resolve(service.ff_pos_map[rtype]);
        });

        return deferred.promise;
    };

    service.loadRemoteTagTable = function(fields, tt_key) {
        egCore.net.request(
            'open-ils.cat',
            'open-ils.cat.tag_table.all.retrieve.local',
            egAuth.token(), fields.marcFormat, fields.marcRecordType
        ).then(
            function (data)  {
                egCore.hatch.setItem(tt_key, service.fields);
            },
            function (err)   { console.err('error fetch tag table: ' + err) }, 
            function (field) {
                if (!field) return;
                service.fields[field.tag] = field;
            }
        );
    };

    service.getFieldTags = function() {
        var list = [];
        angular.forEach(service.fields, function(value, key) {
            this.push({ 
                value: key,
                label: key + ': ' + value.name
            });
        }, list);
        return list;
    }

    service.getSubfieldCodes = function(tag) {
        var list = [];
        if (!tag) return;
        if (!service.fields[tag]) return;
        angular.forEach(service.fields[tag].subfields, function(value) {
            this.push({
                value: value.code,
                label: value.code + ': ' + value.description
            });
        }, list);
        return list;
    }

    service.getIndicatorValues = function(tag, pos) {
        var list = [];
        if (!tag) return list;
        if (!service.fields[tag]) return;
        if (!service.fields[tag]["ind" + pos]) return;
        angular.forEach(service.fields[tag]["ind" + pos], function(value) {
            this.push({
                value: value.code,
                label: value.code + ': ' + value.description
            });
        }, list);
        return list;
    }

    return service;
}]);
