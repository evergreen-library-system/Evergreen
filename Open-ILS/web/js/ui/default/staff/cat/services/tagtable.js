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

        var hatch_pos_key = 'FFPosTable_'+rtype;

        egCore.hatch.getItem(hatch_pos_key).then(function(cached_table) {
            if (cached_table) {
                service.ff_pos_map[rtype] = cached_table;
                deferred.resolve(cached_table);

            } else {

                egCore.net.request( // First, get the list of FFs (minus 006)
                    'open-ils.fielder',
                    'open-ils.fielder.cmfpm.atomic',
                    { query : { tag : { '!=' : '006' } } }
                ).then(function (data)  {
                    service.ff_pos_map[rtype] = data;
                    egCore.hatch.setItem(hatch_pos_key, data);
                    deferred.resolve(data);
                });
            }
        });

        return deferred.promise;
    };

    service.fetchFFValueTable = function(rtype) {
        var deferred = $q.defer();

        var hatch_value_key = 'FFValueTable_'+rtype;

        egCore.hatch.getItem(hatch_value_key).then(function(cached_table) {
            if (cached_table) {
                service.ff_value_map[rtype] = cached_table;
                deferred.resolve(cached_table);

            } else {

                egCore.net.request(
                        'open-ils.cat',
                        'open-ils.cat.biblio.fixed_field_values.by_rec_type',
                        rtype
                ).then(function (data)  {
                    service.ff_value_map[rtype] = data;
                    egCore.hatch.setItem(hatch_value_key, data);
                    deferred.resolve(data);
                });
            }
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

    service.getSubfieldValues = function(tag, sf_code) {
        var list = [];
        if (!tag) return list;
        if (!service.fields[tag]) return;
        if (!service.fields[tag]) return;
        angular.forEach(service.fields[tag].subfields, function(sf) {
            if (sf.code == sf_code && sf.hasOwnProperty('value_list')) {
                angular.forEach(sf.value_list, function(value) {
                    var label = (value.code == value.description) ?
                                value.code :
                                value.code + ': ' + value.description;
                    this.push({
                        value: value.code,
                        label: label
                    });
                }, this);
            }
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
