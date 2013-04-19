/* vim: et:sw=4:ts=4:
 * ---------------------------------------------------------------------------
 * Copyright (C) 2011  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

if(!dojo._hasResource["openils.AuthorityControlSet"]) {
    dojo.require('MARC.FixedFields');

    dojo._hasResource["openils.AuthorityControlSet"] = true;
    dojo.provide("openils.AuthorityControlSet");
    dojo.declare('openils.AuthorityControlSet', null, {

        _controlset : null,

        constructor : function(kwargs) {

            kwargs = kwargs || {};

            if (!openils.AuthorityControlSet._remote_loaded) {

                // TODO -- push the raw tree into the oils cache for later reuse

                // fetch everything up front...
                this._preFetchWithFielder({
                    "acs": "_control_set_list",
                    "at": "_thesaurus_list",
                    "acsaf": "_authority_field_list",
                    "acsbf": "_bib_field_list",
                    "aba": "_browse_axis_list",
                    "abaafm": "_browse_field_map_list"
                });

                openils.AuthorityControlSet._browse_axis_by_code = {};
                dojo.forEach( openils.AuthorityControlSet._browse_axis_list, function (ba) {
                    ba.maps(
                        dojo.filter(
                            openils.AuthorityControlSet._browse_field_map_list,
                            function (m) { return m.axis() == ba.code() }
                        )
                    );
                    openils.AuthorityControlSet._browse_axis_by_code[ba.code()] = ba;
                });

                // loop over each acs
                dojo.forEach( openils.AuthorityControlSet._control_set_list, function (cs) {
                    openils.AuthorityControlSet._controlsets[''+cs.id()] = {
                        id : cs.id(),
                        name : cs.name(),
                        description : cs.description(),
                        authority_tag_map : {},
                        control_map : {},
                        bib_fields : [],
                        raw : cs
                    };

                    // grab the authority fields
                    var acsaf_list = dojo.filter(
                        openils.AuthorityControlSet._authority_field_list,
                        function (af) { return af.control_set() == cs.id() }
                    );

                    var at_list = dojo.filter(
                        openils.AuthorityControlSet._thesaurus_list,
                        function (at) { return at.control_set() == cs.id() }
                    );

                    openils.AuthorityControlSet._controlsets[''+cs.id()].raw.authority_fields( acsaf_list );
                    openils.AuthorityControlSet._controlsets[''+cs.id()].raw.thesauri( at_list );

                    // and loop over each
                    dojo.forEach( acsaf_list, function (csaf) {
                        csaf.axis_maps([]);

                        // link the main entry if we're subordinate
                        if (csaf.main_entry()) {
                            csaf.main_entry(
                                dojo.filter(acsaf_list, function (x) {
                                    return x.id() == csaf.main_entry();
                                })[0]
                            );
                        }

                        // link the sub entries if we're main
                        csaf.sub_entries(
                            dojo.filter(acsaf_list, function (x) {
                                return x.main_entry() == csaf.id();
                            })
                        );

                        // now, bib fields
                        var acsbf_list = dojo.filter(
                            openils.AuthorityControlSet._bib_field_list,
                            function (b) { return b.authority_field() == csaf.id() }
                        );
                        csaf.bib_fields( acsbf_list );

                        openils.AuthorityControlSet._controlsets[''+cs.id()].bib_fields = [].concat(
                            openils.AuthorityControlSet._controlsets[''+cs.id()].bib_fields,
                            acsbf_list
                        );

                        dojo.forEach( acsbf_list, function (csbf) {
                            // link the authority field to the bib field
                            if (csbf.authority_field()) {
                                csbf.authority_field(
                                    dojo.filter(acsaf_list, function (x) {
                                        return x.id() == csbf.authority_field();
                                    })[0]
                                );
                            }
    
                        });

                        dojo.forEach( // for each axis
                            openils.AuthorityControlSet._browse_axis_list,
                            function (ba) {
                                dojo.forEach( // loop over the maps
                                    dojo.filter( // filtering to just this field's mapps
                                        ba.maps(),
                                        function (m) { return m.field() == csaf.id() }
                                    ),
                                    function (fm) { fm.field( csaf ); csaf.axis_maps().push( fm ) } // and set the field
                                )
                            }
                        );

                    });

                    // build the authority_tag_map
                    dojo.forEach( openils.AuthorityControlSet._controlsets[''+cs.id()].bib_fields, function (bf) {

                        if (!openils.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()])
                            openils.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()] = {};

                        dojo.forEach( bf.authority_field().sf_list().split(''), function (sf_code) {

                            if (!openils.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()][sf_code])
                                openils.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()][sf_code] = {};

                            openils.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()][sf_code][bf.authority_field().tag()] = sf_code;
                        });
                    });

                });

                if (this.controlSetList().length > 0)
                    delete openils.AuthorityControlSet._controlsets['-1'];

                openils.AuthorityControlSet._remote_loaded = true;
            }

            if (kwargs.controlSet) {
                this.controlSetId( kwargs.controlSet );
            } else {
                this.controlSetId( this.controlSetList().sort(function(a,b){return (a - b)}) );
            }
        },

        _preFetchWithFielder: function(cmap) {
            for (var hint in cmap) {
                var cache_key = cmap[hint];
                var method = "open-ils.fielder." + hint + ".atomic";
                var pkey = fieldmapper.IDL.fmclasses[hint].pkey;

                var query = {};
                query[pkey] = {"!=": null};

                openils.AuthorityControlSet[cache_key] = dojo.map(
                    fieldmapper.standardRequest(
                        ["open-ils.fielder", method],
                        [{"cache": 1, "query" : query}]
                    ),
                    function(h) { return new fieldmapper[hint]().fromHash(h); }
                );
            }
        },

        controlSetId: function (x) {
            if (x) this._controlset = ''+x;
            return this._controlset;
        },

        controlSet: function (x) {
            return openils.AuthorityControlSet._controlsets[''+this.controlSetId(x)];
        },

        controlSetByThesaurusCode: function (x) {
            var thes = dojo.filter(
                openils.AuthorityControlSet._thesaurus_list,
                function (at) { return at.code() == x }
            )[0];

            return this.controlSet(thes.control_set());
        },

        browseAxisByCode: function(code) {
            return openils.AuthorityControlSet._browse_axis_by_code[code];
        },

        bibFieldByTag: function (x) {
            var me = this;
            return dojo.filter(
                me.controlSet().bib_fields,
                function (bf) { if (bf.tag() == x) return true }
            )[0];
        },

        bibFields: function (x) {
            return this.controlSet(x).bib_fields;
        },

        bibFieldBrowseAxes : function (t) {
            var blist = [];
            for (var bcode in openils.AuthorityControlSet._browse_axis_by_code) {
                dojo.forEach(
                    openils.AuthorityControlSet._browse_axis_by_code[bcode].maps(),
                    function (m) {
                        if (dojo.filter(
                                m.field().bib_fields(),
                                function (b) { return b.tag() == t }
                            ).length > 0
                        ) blist.push(bcode);
                    }
                );
            }
            return blist;
        },

        authorityFields: function (x) {
            return this.controlSet(x).raw.authority_fields();
        },

        thesauri: function (x) {
            return this.controlSet(x).raw.thesauri();
        },

        controlSetList : function () {
            var l = [];
            for (var i in openils.AuthorityControlSet._controlsets) {
                l.push(i);
            }
            return l;
        },

        findControlSetsForTag : function (tag) {
            var me = this;
            var old_acs = this.controlSetId();
            var acs_list = dojo.filter(
                me.controlSetList(),
                function(acs_id) { return (me.controlSet(acs_id).control_map[tag]) }
            );
            this.controlSetId(old_acs);
            return acs_list;
        },

        findControlSetsForAuthorityTag : function (tag) {
            var me = this;
            var old_acs = this.controlSetId();

            var acs_list = dojo.filter(
                me.controlSetList(),
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
        },

        bibToAuthority : function (field) {
            var b_field = this.bibFieldByTag(field.tag);

            if (b_field) { // construct an marc authority record
                var af = b_field.authority_field();

                var sflist = [];                
                for (var i = 0; i < field.subfields.length; i++) {
                    if (af.sf_list().indexOf(field.subfields[i][0]) > -1) {
                        sflist.push(field.subfields[i]);
                    }
                }

                var m = new MARC.Record ({rtype:'AUT'});
                m.appendFields(
                    new MARC.Field ({
                        tag : af.tag(),
                        ind1: field.ind1,
                        ind2: field.ind2,
                        subfields: sflist
                    })
                );

                return m.toXmlString();
            }

            return null;
        },

        bibToAuthorities : function (field) {
            var auth_list = [];
            var me = this;

            var old_acs = this.controlSetId();
            dojo.forEach(
                me.controlSetList(),
                function (acs_id) {
                    var acs = me.controlSet(acs_id);
                    var x = me.bibToAuthority(field);
                    if (x) { var foo = {}; foo[acs_id] = x; auth_list.push(foo); }
                }
            );
            this.controlSetId(old_acs);

            return auth_list;
        },

        findMatchingAuthorities : function (field) {
            return fieldmapper.standardRequest(
                [ 'open-ils.search', 'open-ils.search.authority.simple_heading.from_xml.batch.atomic' ],
                this.bibToAuthorities(field)
            );
        }

    });

    openils.AuthorityControlSet._remote_loaded = false;

    openils.AuthorityControlSet._controlsets = {
        // static sorta-LoC setup ... to be overwritten with server data 
        '-1' : {
            id : -1,
            name : 'Static LoC legacy mapping',
            description : 'Legacy mapping provided as a default',
            control_map : {
                100 : {
                    'a' : { 100 : 'a' },
                    'd' : { 100 : 'd' },
                    'e' : { 100 : 'e' },
                    'q' : { 100 : 'q' }
                },
                110 : {
                    'a' : { 110 : 'a' },
                    'd' : { 110 : 'd' }
                },
                111 : {
                    'a' : { 111 : 'a' },
                    'd' : { 111 : 'd' }
                },
                130 : {
                    'a' : { 130 : 'a' },
                    'd' : { 130 : 'd' }
                },
                240 : {
                    'a' : { 130 : 'a' },
                    'd' : { 130 : 'd' }
                },
                400 : {
                    'a' : { 100 : 'a' },
                    'd' : { 100 : 'd' }
                },
                410 : {
                    'a' : { 110 : 'a' },
                    'd' : { 110 : 'd' }
                },
                411 : {
                    'a' : { 111 : 'a' },
                    'd' : { 111 : 'd' }
                },
                440 : {
                    'a' : { 130 : 'a' },
                    'n' : { 130 : 'n' },
                    'p' : { 130 : 'p' }
                },
                700 : {
                    'a' : { 100 : 'a' },
                    'd' : { 100 : 'd' },
                    'q' : { 100 : 'q' },
                    't' : { 100 : 't' }
                },
                710 : {
                    'a' : { 110 : 'a' },
                    'd' : { 110 : 'd' }
                },
                711 : {
                    'a' : { 111 : 'a' },
                    'c' : { 111 : 'c' },
                    'd' : { 111 : 'd' }
                },
                730 : {
                    'a' : { 130 : 'a' },
                    'd' : { 130 : 'd' }
                },
                800 : {
                    'a' : { 100 : 'a' },
                    'd' : { 100 : 'd' }
                },
                810 : {
                    'a' : { 110 : 'a' },
                    'd' : { 110 : 'd' }
                },
                811 : {
                    'a' : { 111 : 'a' },
                    'd' : { 111 : 'd' }
                },
                830 : {
                    'a' : { 130 : 'a' },
                    'd' : { 130 : 'd' }
                },
                600 : {
                    'a' : { 100 : 'a' },
                    'd' : { 100 : 'd' },
                    'q' : { 100 : 'q' },
                    't' : { 100 : 't' },
                    'v' : { 180 : 'v',
                        100 : 'v',
                        181 : 'v',
                        182 : 'v',
                        185 : 'v'
                    },
                    'x' : { 180 : 'x',
                        100 : 'x',
                        181 : 'x',
                        182 : 'x',
                        185 : 'x'
                    },
                    'y' : { 180 : 'y',
                        100 : 'y',
                        181 : 'y',
                        182 : 'y',
                        185 : 'y'
                    },
                    'z' : { 180 : 'z',
                        100 : 'z',
                        181 : 'z',
                        182 : 'z',
                        185 : 'z'
                    }
                },
                610 : {
                    'a' : { 110 : 'a' },
                    'd' : { 110 : 'd' },
                    't' : { 110 : 't' },
                    'v' : { 180 : 'v',
                        110 : 'v',
                        181 : 'v',
                        182 : 'v',
                        185 : 'v'
                    },
                    'x' : { 180 : 'x',
                        110 : 'x',
                        181 : 'x',
                        182 : 'x',
                        185 : 'x'
                    },
                    'y' : { 180 : 'y',
                        110 : 'y',
                        181 : 'y',
                        182 : 'y',
                        185 : 'y'
                    },
                    'z' : { 180 : 'z',
                        110 : 'z',
                        181 : 'z',
                        182 : 'z',
                        185 : 'z'
                    }
                },
                611 : {
                    'a' : { 111 : 'a' },
                    'd' : { 111 : 'd' },
                    't' : { 111 : 't' },
                    'v' : { 180 : 'v',
                        111 : 'v',
                        181 : 'v',
                        182 : 'v',
                        185 : 'v'
                    },
                    'x' : { 180 : 'x',
                        111 : 'x',
                        181 : 'x',
                        182 : 'x',
                        185 : 'x'
                    },
                    'y' : { 180 : 'y',
                        111 : 'y',
                        181 : 'y',
                        182 : 'y',
                        185 : 'y'
                    },
                    'z' : { 180 : 'z',
                        111 : 'z',
                        181 : 'z',
                        182 : 'z',
                        185 : 'z'
                    }
                },
                630 : {
                    'a' : { 130 : 'a' },
                    'd' : { 130 : 'd' }
                },
                648 : {
                    'a' : { 148 : 'a' },
                    'v' : { 148 : 'v' },
                    'x' : { 148 : 'x' },
                    'y' : { 148 : 'y' },
                    'z' : { 148 : 'z' }
                },
                650 : {
                    'a' : { 150 : 'a' },
                    'b' : { 150 : 'b' },
                    'v' : { 180 : 'v',
                        150 : 'v',
                        181 : 'v',
                        182 : 'v',
                        185 : 'v'
                    },
                    'x' : { 180 : 'x',
                        150 : 'x',
                        181 : 'x',
                        182 : 'x',
                        185 : 'x'
                    },
                    'y' : { 180 : 'y',
                        150 : 'y',
                        181 : 'y',
                        182 : 'y',
                        185 : 'y'
                    },
                    'z' : { 180 : 'z',
                        150 : 'z',
                        181 : 'z',
                        182 : 'z',
                        185 : 'z'
                    }
                },
                651 : {
                    'a' : { 151 : 'a' },
                    'v' : { 180 : 'v',
                        151 : 'v',
                        181 : 'v',
                        182 : 'v',
                        185 : 'v'
                    },
                    'x' : { 180 : 'x',
                        151 : 'x',
                        181 : 'x',
                        182 : 'x',
                        185 : 'x'
                    },
                    'y' : { 180 : 'y',
                        151 : 'y',
                        181 : 'y',
                        182 : 'y',
                        185 : 'y'
                    },
                    'z' : { 180 : 'z',
                        151 : 'z',
                        181 : 'z',
                        182 : 'z',
                        185 : 'z'
                    }
                },
                655 : {
                    'a' : { 155 : 'a' },
                    'v' : { 180 : 'v',
                        155 : 'v',
                        181 : 'v',
                        182 : 'v',
                        185 : 'v'
                    },
                    'x' : { 180 : 'x',
                        155 : 'x',
                        181 : 'x',
                        182 : 'x',
                        185 : 'x'
                    },
                    'y' : { 180 : 'y',
                        155 : 'y',
                        181 : 'y',
                        182 : 'y',
                        185 : 'y'
                    },
                    'z' : { 180 : 'z',
                        155 : 'z',
                        181 : 'z',
                        182 : 'z',
                        185 : 'z'
                    }
                }
            }
        }
     };

}
