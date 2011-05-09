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

if(!dojo._hasResource["MARC.AuthorityControlSet"]) {

    dojo.require('openils.PermaCrud');
    dojo.require('MARC.FixedFields');

    dojo._hasResource["MARC.AuthorityControlSet"] = true;
    dojo.provide("MARC.AuthorityControlSet");
    dojo.declare('MARC.AuthorityControlSet', null, {

        _controlset : null,

        constructor : function(kwargs) {

            if (!MARC.AuthorityControlSet._remote_loaded) {

                // TODO -- push the raw tree into the oils cache for later reuse

                var pcrud = new openils.PermaCrud();
                var acs_list = pcrud.retrieveAll('acs');

                // loop over each acs
                dojo.forEach( acs_list, function (cs) {
                    MARC.AuthorityControlSet._controlsets[''+cs.id()] = {
                        id : cs.id(),
                        name : cs.name(),
                        description : cs.description(),
                        authority_tag_map : {},
                        control_map : {},
                        bib_fields : [],
                        raw : cs
                    };

                    // grab the authority fields
                    var acsaf_list = pcrud.search('acsaf', {control_set : cs.id()});
                    var at_list = pcrud.search('at', {control_set : cs.id()});
                    MARC.AuthorityControlSet._controlsets[''+cs.id()].raw.authority_fields( acsaf_list );
                    MARC.AuthorityControlSet._controlsets[''+cs.id()].raw.thesauri( at_list );

                    // and loop over each
                    dojo.forEach( acsaf_list, function (csaf) {
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
                            })[0]
                        );

                        // now, bib fields
                        var acsbf_list = pcrud.search('acsbf', {authority_field : csaf.id()});
                        csaf.bib_fields( acsbf_list );

                        MARC.AuthorityControlSet._controlsets[''+cs.id()].bib_fields = [].concat(
                            MARC.AuthorityControlSet._controlsets[''+cs.id()].bib_fields
                            acsbf_list
                        );

                        dojo.forEach( acsbf_list, function (csbf) {
                            // link the main entry if we're subordinate
                            if (csbf.authority_field()) {
                                csbf.authority_field(
                                    dojo.filter(acsaf_list, function (x) {
                                        return x.a() == csbf.authority_field();
                                    })[0]
                                );
                            }
    
                        });
                    });

                    // build the authority_tag_map
                    dojo.forEach( MARC.AuthorityControlSet._controlsets[''+cs.id()].bib_fields, function (bf) {
                        MARC.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()] = {};
                        dojo.forEach( bf.authority_field().sf_list().split(''), function (sf_code) {
                            MARC.AuthorityControlSet._controlsets[''+cs.id()].control_map[bf.tag()][sf_code] = { bf.authority_field().tag() : sf_code };
                        });
                    });
                });

                
                if (this.controlSetList().length > 0)
                    delete MARC.AuthorityControlSet._controlsets['-1'];

                MARC.AuthorityControlSet._remote_loaded = true;
            }

            if (kwargs.controlSet) {
                this.controlSetId( kwargs.controlSet );
            } else {
                this.controlSetId( this.controlSetList().sort(function(a,b){return (a - b)}) );
            }
        },

        controlSetId: function (x) {
            if (x) this._controlset = ''+x;
            return this._controlset;
        },

        controlSet: function (x) {
            return MARC.AuthorityControlSet._controlsets[''+this.controlSetId(x)];
        },

        authorityFields: function (x) {
            return MARC.AuthorityControlSet._controlsets[''+this.controlSetId(x)].raw.authority_fields();
        },

        thesauri: function (x) {
            return MARC.AuthorityControlSet._controlsets[''+this.controlSetId(x)].raw.thesauri();
        },

        controlSetList : function () {
            var l = [];
            for (var i in MARC.AuthorityControlSet._controlsets) {
                l.push(i);
            }
            return l;
        },

        findControlSetsForTag : function (tag) {
            var old_acs = this.controlSetId();
            var acs_list = dojo.filter(
                this.controlSetList(),
                function(acs_id) { return (this.controlSet(acs_id).control_map[tag]) }
            );
            this.controlSetId(old_acs);
            return acs_list;
        }

    });

    MARC.AuthorityControlSet._remote_loaded = false;

    MARC.AuthorityControlSet._controlsets = {
        // static sorta-LoC setup ... to be overwritten with server data 
        -1 : {
            id : -1,
            name : 'Static LoC legacy mapping',
            description : 'Legacy mapping provided as a default',
            contorl_map : {
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
