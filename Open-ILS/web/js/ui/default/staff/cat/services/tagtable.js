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
        ff_value_map : { },
        phys_char_type_map : null,
        phys_char_sf_map : { },
        phys_char_value_map : { },
        authority_control_set : {
            _remote_loaded : false,
            _controlsets : [ ]
        },
        _active_control_set : undefined
    };

    service.initialized = function() {
        return service.authority_control_set._remote_loaded;
    }

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
                fields.marcRecordType = service.normalizeRecordType(args.marcRecordType);
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

    var _ffpos_promises = {};
    service.fetchFFPosTable = function(rtype) {
        if (!(rtype in _ffpos_promises)) {
            _ffpos_promises[rtype] = $q.defer();

            var hatch_pos_key = 'FFPosTable_'+rtype;

            egCore.hatch.getItem(hatch_pos_key).then(function(cached_table) {
                if (cached_table) {
                    service.ff_pos_map[rtype] = cached_table;
                    _ffpos_promises[rtype].resolve(cached_table);

                } else {

                    egCore.net.request( // First, get the list of FFs (minus 006)
                        'open-ils.fielder',
                        'open-ils.fielder.cmfpm.atomic',
                        { query : { tag : { '!=' : '006' } } }
                    ).then(function (data)  {
                        service.ff_pos_map[rtype] = data;
                        egCore.hatch.setItem(hatch_pos_key, data);
                        _ffpos_promises[rtype].resolve(data);
                    });
                }
            });
        }

        return _ffpos_promises[rtype].promise;
    };

    var _ffval_promises = {};
    service.fetchFFValueTable = function(rtype) {
        if (!(rtype in _ffval_promises)) {
            _ffval_promises[rtype] = $q.defer();

            var hatch_value_key = 'FFValueTable_'+rtype;

            egCore.hatch.getItem(hatch_value_key).then(function(cached_table) {
                if (cached_table) {
                    service.ff_value_map[rtype] = cached_table;
                    _ffval_promises[rtype].resolve(cached_table);

                } else {

                    egCore.net.request(
                        'open-ils.cat',
                        'open-ils.cat.biblio.fixed_field_values.by_rec_type',
                        rtype
                    ).then(function (data)  {
                        service.ff_value_map[rtype] = data;
                        egCore.hatch.setItem(hatch_value_key, data);
                        _ffval_promises[rtype].resolve(data);
                    });
                }
            });
        }

        return _ffval_promises[rtype].promise;
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

    service.authorityControlSet = function (kwargs) {
    
        kwargs = kwargs || {};

        this._fetch_class = function(hint, cache_key) {
            return egCore.pcrud.retrieveAll(hint, {}, {atomic : true}).then(
                function(list) {
                    egCore.env.absorbList(list, hint);
                    service.authority_control_set[cache_key] = list;
                }
            );
        };

        this._fetch = function(cmap) {
            var deferred = $q.defer();
            var promises = [];
            for (var hint in cmap) {
                promises.push(this._fetch_class(hint, cmap[hint]));
            }
            $q.all(promises).then(function() {
                deferred.resolve();
            });
            return deferred.promise;
        };

        this._parse = function() {
            service.authority_control_set._browse_axis_by_code = {};
            service.authority_control_set._browse_axis_list.forEach(function (ba) {
                ba.maps(
                    service.authority_control_set._browse_field_map_list.filter(
                        function (m) { return m.axis() == ba.code() }
                    )
                );
                service.authority_control_set._browse_axis_by_code[ba.code()] = ba;
            });
    
            // loop over each acs
            service.authority_control_set._control_set_list.forEach(function (cs) {
                service.authority_control_set._controlsets[''+cs.id()] = {
                    id : cs.id(),
                    name : cs.name(),
                    description : cs.description(),
                    authority_tag_map : {},
                    control_map : {},
                    bib_fields : [],
                    raw : cs
                };
    
                // grab the authority fields
                var acsaf_list = service.authority_control_set._authority_field_list.filter(
                    function (af) { return af.control_set() == cs.id() }
                );
    
                var at_list = service.authority_control_set._thesaurus_list.filter(
                    function (at) { return at.control_set() == cs.id() }
                );
    
                service.authority_control_set._controlsets[''+cs.id()].raw.authority_fields( acsaf_list );
                service.authority_control_set._controlsets[''+cs.id()].raw.thesauri( at_list );
    
                // and loop over each
                acsaf_list.forEach(function (csaf) {
                    csaf.axis_maps([]);
    
                    // link the main entry if we're subordinate
                    if (csaf.main_entry()) {
                        csaf.main_entry(
                            acsaf_list.filter(function (x) {
                                return x.id() == csaf.main_entry();
                            })[0]
                        );
                    }
    
                    // link the sub entries if we're main
                    csaf.sub_entries(
                        acsaf_list.filter(function (x) {
                            return x.main_entry() == csaf.id();
                        })
                    );
    
                    // now, bib fields
                    var acsbf_list = service.authority_control_set._bib_field_list.filter(
                        function (b) { return b.authority_field() == csaf.id() }
                    );
                    csaf.bib_fields( acsbf_list );
    
                    service.authority_control_set._controlsets[''+cs.id()].bib_fields = [].concat(
                        service.authority_control_set._controlsets[''+cs.id()].bib_fields,
                        acsbf_list
                    );
    
                    acsbf_list.forEach(function (csbf) {
                        // link the authority field to the bib field
                        if (csbf.authority_field()) {
                            csbf.authority_field(
                                acsaf_list.filter(function (x) {
                                    return x.id() == csbf.authority_field();
                                })[0]
                            );
                        }
    
                    });
    
                    service.authority_control_set._browse_axis_list.forEach(
                        function (ba) {
                            ba.maps().filter(
                                function (m) { return m.field() == csaf.id() }
                            ).forEach(
                                function (fm) { fm.field( csaf ); csaf.axis_maps().push( fm ) } // and set the field
                            )
                        }
                    );
    
                });
    
                // build the authority_tag_map
                service.authority_control_set._controlsets[''+cs.id()].bib_fields.forEach(function (bf) {
    
                    if (!service.authority_control_set._controlsets[''+cs.id()].control_map[bf.tag()])
                        service.authority_control_set._controlsets[''+cs.id()].control_map[bf.tag()] = {};
    
                    bf.authority_field().sf_list().split('').forEach(function (sf_code) {
    
                        if (!service.authority_control_set._controlsets[''+cs.id()].control_map[bf.tag()][sf_code])
                            service.authority_control_set._controlsets[''+cs.id()].control_map[bf.tag()][sf_code] = {};
    
                        service.authority_control_set._controlsets[''+cs.id()].control_map[bf.tag()][sf_code][bf.authority_field().tag()] = sf_code;
                    });
                });
    
            });
    
            if (this.controlSetList().length > 0)
                delete service.authority_control_set._controlsets['-1'];
    
        }
    
        this.controlSetId = function (x) {
            if (x) this._controlset = ''+x;
            return this._controlset;
        }

        this.controlSetList = function () {
            var l = [];
            for (var i in service.authority_control_set._controlsets) {
                l.push(i);
            }
            return l;
        }
    
    
        if (!service.authority_control_set._remote_loaded) {
    
            // TODO -- push the raw tree into the oils cache for later reuse
    
            // fetch everything up front...
            var parent = this;
            this._fetch({
                "acs": "_control_set_list",
                "at": "_thesaurus_list",
                "acsaf": "_authority_field_list",
                "acsbf": "_bib_field_list",
                "aba": "_browse_axis_list",
                "abaafm": "_browse_field_map_list"
            }).then(function() {
                service.authority_control_set._remote_loaded = true;
                parent._parse();
                if (kwargs.controlSet) {
                    parent.controlSetId( kwargs.controlSet );
                } else {
                    parent.controlSetId( parent.controlSetList().sort(function(a,b){return (a - b)}) );
                }
            });
        }

        this.controlSet = function (x) {
            return service.authority_control_set._controlsets[''+this.controlSetId(x)];
        }
    
        this.controlSetByThesaurusCode = function (x) {
            var thes = service.authority_control_set._thesaurus_list.filter(
                function (at) { return at.code() == x }
            )[0];
    
            return this.controlSet(thes.control_set());
        }
    
        this.browseAxisByCode = function(code) {
            return service.authority_control_set._browse_axis_by_code[code];
        }
    
        this.bibFieldByTag = function (x) {
            var me = this;
            return me.controlSet().bib_fields.filter(
                function (bf) { if (bf.tag() == x) return true }
            )[0];
        }
    
        this.bibFields = function (x) {
            return this.controlSet(x).bib_fields;
        }
    
        this.bibFieldBrowseAxes = function (t) {
            var blist = [];
            for (var bcode in service.authority_control_set._browse_axis_by_code) {
                service.authority_control_set._browse_axis_by_code[bcode].maps().forEach(
                    function (m) {
                        if (m.field().bib_fields().filter(
                                function (b) { return b.tag() == t }
                            ).length > 0
                        ) blist.push(bcode);
                    }
                );
            }
            return blist;
        }
    
        this.authorityFields = function (x) {
            return this.controlSet(x).raw.authority_fields();
        }
    
        this.thesauri = function (x) {
            return this.controlSet(x).raw.thesauri();
        }
    
        this.findControlSetsForTag = function (tag) {
            var me = this;
            var old_acs = this.controlSetId();
            var acs_list = me.controlSetList().filter(
                function(acs_id) { return (me.controlSet(acs_id).control_map[tag]) }
            );
            this.controlSetId(old_acs);
            return acs_list;
        }
    
        this.findControlSetsForAuthorityTag = function (tag) {
            var me = this;
            var old_acs = this.controlSetId();
    
            var acs_list = me.controlSetList().filter(
                function(acs_id) {
                    var a = me.controlSet(acs_id);
                    for (var btag in a.control_map) {
                        for (var sf in a.control_map[btag]) {
                            if (a.control_map[btag][sf][tag]) return true;
                        }
                    }
                    return false;
                }
            );
            this.controlSetId(old_acs);
            return acs_list;
        }
    
        this.bibToAuthority = function (field) {
            var b_field = this.bibFieldByTag(field.tag);
    
            if (b_field) { // construct an marc authority record
                var af = b_field.authority_field();
    
                var sflist = [];                
                for (var i = 0; i < field.subfields.length; i++) {
                    if (af.sf_list().indexOf(field.subfields[i][0]) > -1) {
                        if (typeof(field.subfields[i][1]) != 'undefined'
                            && field.subfields[i][1] !== null
                            && field.subfields[i][1].length > 0
                        ) {
                                sflist.push(field.subfields[i]);
                        }
                    }
                }
                if (sflist.length == 0) return null;

                var m = new MARC21.Record ({rtype:'AUT'});
                m.appendFields(
                    new MARC21.Field ({
                        tag : af.tag(),
                        ind1: field.ind1,
                        ind2: field.ind2,
                        subfields: sflist
                    })
                );
    
                return m.toXmlString();
            }
    
            return null;
        }
    
        this.bibToAuthorities = function (field) {
            var auth_list = [];
            var me = this;
    
            var old_acs = this.controlSetId();
            me.controlSetList().forEach(
                function (acs_id) {
                    var acs = me.controlSet(acs_id);
                    var x = me.bibToAuthority(field);
                    if (x) { var foo = {}; foo[acs_id] = x; auth_list.push(foo); }
                }
            );
            this.controlSetId(old_acs);
    
            return auth_list;
        }
    
    }

    service.getAuthorityControlSet = function() {
        if (!service._active_control_set) {
            service.authority_control_set._remote_loaded = false;
            service._active_control_set = new service.authorityControlSet();
        }
        return service._active_control_set;
    }

    // fetches and caches the full set of values from 
    // config.marc21_physical_characteristic_type_map
    service.getPhysCharTypeMap = function() {

        if (service.phys_char_type_map) {
            return $q.when(service.phys_char_type_map);
        }

        return egCore.pcrud.retrieveAll('cmpctm', {}, {atomic : true})
        .then(function(map) {return service.phys_char_type_map = map});
    }

    // Fetch+caches the config.marc21_physical_characteristic_subfield_map
    // values for the requested ptype_key (i.e. type_map.ptype_key).
    // Values are sorted by start_pos
    service.getPhysCharSubfieldMap = function(ptype_key) {

        if (service.phys_char_sf_map[ptype_key]) {
            return $q.when(service.phys_char_sf_map[ptype_key]);
        }

        return egCore.pcrud.search('cmpcsm', 
            {ptype_key : ptype_key},
            {order_by : {cmpcsm : ['start_pos']}},
            {atomic : true}
        ).then(function(maps) {
            return service.phys_char_sf_map[ptype_key] = maps;
        });
    }

    // Fetches + caches the config.marc21_physical_characteristic_value_map
    // for the requested ptype_subfield (subfield_map.id).  
    // Maps are ordered by value.
    service.getPhysCharValueMap = function(ptype_subfield) {
        if (service.phys_char_value_map[ptype_subfield]) {
            return $q.when(service.phys_char_value_map[ptype_subfield]);
        }

        return egCore.pcrud.search('cmpcvm', 
            {ptype_subfield : ptype_subfield},
            {order_by : {cmpcsm : ['value']}},
            {atomic : true}
        ).then(function(maps) {
            return service.phys_char_sf_map[ptype_subfield] = maps;
        });
    }

    return service;
}]);
