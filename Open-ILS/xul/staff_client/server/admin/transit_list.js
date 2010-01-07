dump('entering admin.transit_list.js\n');

if (typeof admin == 'undefined') admin = {};
admin.transit_list = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network(); JSAN.use('util.file');
    JSAN.use('util.date'); JSAN.use('util.widgets'); JSAN.use('util.fm_utils'); JSAN.use('util.functional');
    JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

admin.transit_list.prototype = {

    'init' : function( params ) {

        var obj = this;

        var x = document.getElementById('libmenu_placeholder');
        util.widgets.remove_children( x );

        var file; var list_data; var ml; 

        file = new util.file('offline_ou_list'); 
        if (file._file.exists()) {
            list_data = file.get_object(); file.close();
            ml = util.widgets.make_menulist( list_data[0], list_data[1] );
            ml.setAttribute('id','libmenu'); document.getElementById('libmenu_placeholder').appendChild(ml);
            ml.addEventListener(
                'command',
                function(ev) {
                    var file = new util.file('transit_list_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, { 'libmenu' : [ 'value' ] });
                },
                false
            );
        } else {
            throw(document.getElementById('adminStrings').getString('staff.admin.transit_list.missing_list') + '\n');
        }

        file = new util.file('transit_list_prefs.'+obj.data.server_unadorned);
        util.widgets.load_attributes(file);
        ml.value = ml.getAttribute('value');
        if (! ml.value) {
            ml.value = obj.data.list.au[0].ws_ou();
            ml.setAttribute('value',ml.value);
        }

        x.appendChild( ml );

        obj.list_init();
        obj.controller_init();
        //obj.kick_off();

    },

    'sdate' : null,
    'edate' : null,

    'handle_date' : function(value,end_of_day) {
        try {
            var _date = null;

            /* The Beginning */
            if (value.match(/The Beginning/)) {
                _date = new Date(); _date.setTime( 0 );
            }

            /* Today */
            if (value.match(/^Today$/i)) {
                _date = new Date(); _date = util.date.buildDate( _date.getFullYear(), _date.getMonth()+1, _date.getDate(), 0, 0, 0); // morning
            }

            /* handle YYYY-MM-DD */
            var _string = value.match(/(\d\d\d\d)[\-\/](\d\d?)[\-\/](\d\d?)/);
            if (_string) {
                if (util.date.check('YYYY-MM-DD',_string[1]+'-'+_string[2]+'-'+_string[3])) {
                    _date = util.date.buildDate( _string[1], _string[2], _string[3], 0, 0, 0);
                } else {
                    alert(document.getElementById('adminStrings').getFormattedString('staff.admin.transit_list.invalid_date', [_string])); 
                    _date = new Date(); _date = util.date.buildDate( _date.getFullYear(), _date.getMonth()+1, _date.getDate(), 0, 0, 0); // morning
                }
            }

            /* handle relative dates */
            var interval = value.match(/Today \- (.+)/);
            if (interval) {
                _date = new Date(); _date = util.date.buildDate( _date.getFullYear(), _date.getMonth()+1, _date.getDate(), 0, 0, 0); // morning
                _date.setTime( _date.getTime() - util.date.interval_to_seconds(interval[1])*1000 );
            }

            if (! util.date.check('YYYY-MM-DD',util.date.formatted_date(_date,"%F")) ) { 
                alert(document.getElementById('adminStrings').getFormattedString('staff.admin.transit_list.invalid_date', [_date, util.date.formatted_date(_date,"%F")])); 
                _date = new Date(); _date = util.date.buildDate( _date.getFullYear(), _date.getMonth()+1, _date.getDate(), 0, 0, 0); // morning
            }
                
            if (end_of_day) { // This just handles calendar days.. if we wanted to support (Today-1 month,Today-1 month), I'll need a better library, or a query to postgres
                _date.setTime( _date.getTime() + util.date.interval_to_seconds('1 day')*1000 - util.date.interval_to_seconds('1 second')*1000 );
            }

            return util.date.formatted_date(_date,'%{iso8601}');
        } catch(E) {
            try { obj.error.standard_unexpected_error_alert(document.getElementById('adminStrings').getString('staff.admin.transit_list.date_processing.error'),E); } catch(F) { alert(E); }
            _date = new Date(); _date = util.date.buildDate( _date.getFullYear(), _date.getMonth()+1, _date.getDate(), 0, 0, 0); // morning
            return util.date.formatted_date(_date,'%{iso8601}');
        }
    },

    'kick_off' : function() {
        var obj = this;
        try {
            obj.list.clear();
            obj.sdate = obj.handle_date( document.getElementById('sdate').value, false );
            obj.edate = obj.handle_date( document.getElementById('edate').value, true );
            var sdate; var edate;
            if (obj.sdate < obj.edate) {
                sdate = obj.sdate; edate = obj.edate;
            } else {
                sdate = obj.edate; edate = obj.sdate;
            }
            obj.network.simple_request('FM_ATC_RETRIEVE_VIA_AOU',[ ses(), /*obj.data.list.au[ 0 ].ws_ou()*/ document.getElementById('libmenu').value, sdate, edate ], 
                function(req) {
                    try {
                        var robj = req.getResultObject();
                        if (typeof robj.ilsevent != 'undefined') throw(robj);

                        JSAN.use('util.exec'); 
                        var exec = new util.exec(2);
                        var exec2 = new util.exec(2);

                        function gen_list_append(id,which_list) {
                            return function() {
                                switch(which_list) {
                                    case 0: obj.list.append( { 'row' : { 'my' : { 'transit_id' : id } }, 'no_auto_select' : true } ); break;
                                    case 1: obj.list.append( { 'row' : { 'my' : { 'transit_id' : id } }, 'no_auto_select' : true } ); break;
                                }
                            };
                        }

                        var rows = []; 

                        if (document.getElementById('transit_direction').value=='transit_from') for (var i = 0; i < robj.from.length; i++) {
                            //get_transit(robj.from[i], 0);
                            rows.push( gen_list_append(robj.from[i],0) );
                        }

                        if (document.getElementById('transit_direction').value=='transit_to') for (var i = 0; i < robj.to.length; i++) {
                            //get_transit(robj.to[i], 1);
                            rows.push( gen_list_append(robj.to[i],1) );
                        }
                
                        if (rows.length > 0) {
                            exec.chain( rows );
                        } else {
                            alert(document.getElementById('adminStrings').getString('staff.admin.transit_list.no_match'));
                        }

                    } catch(E) {
                        try { obj.error.standard_unexpected_error_alert(document.getElementById('adminStrings').getString('staff.admin.transit_list.retrieving_transit.error'),E); } catch(F) { alert(E); }
                    }
                }
            );
        } catch(E) {
            try { obj.error.standard_unexpected_error_alert(document.getElementById('adminStrings').getString('staff.admin.transit_list.preretrieving_transit.error'),E); } catch(F) { alert(E); }
        }
    },

    'list_init' : function() {

        var obj = this;

        obj.selection_list = [];

        JSAN.use('circ.util'); 
        var columns = circ.util.transit_columns(
            {
                'transit_source' : { 'hidden' : false },
                'transit_source_send_time' : { 'hidden' : false },
                'transit_dest_lib' : { 'hidden' : false },
                'transit_item_barcode' : { 'hidden' : false },
                'transit_item_title' : { 'hidden' : false },
            },
            {
                'just_these' : [
                    'transit_id',
                    'transit_source',
                    'transit_source_send_time',
                    'transit_dest_lib',
                    'transit_item_barcode',
                    'transit_item_title',
                    'transit_item_author',
                    'transit_item_callnumber',
                    'transit_target_copy',
                ]
            }
        ).concat( 
            circ.util.hold_columns(
                {
                    'request_time' : { 'hidden' : false },
                },
                {
                    'just_these' : [
                        'request_timestamp',
                        'request_time',
                        'capture_timestamp',
                        'capture_time',
                        'hold_type',
                        'expire_time',
                        'patron_first_given_name',
                        'patron_family_name',
                        'patron_barcode',
                    ],
                }
            ) 
        );

        JSAN.use('util.list'); 
        obj.list = new util.list('transit_list');
        obj.list.init( 
            { 
                'columns' : columns, 
                'map_row_to_columns' : circ.util.std_map_row_to_columns(), 
                'retrieve_row' : function(params) {
                    var row = params.row;
                    try {
                        obj.get_transit_and_hold_and_run_func(
                            row.my.transit_id,
                            function(transit,hold) { return obj.get_rest_of_row_given_transit_and_hold(params,transit,hold); }
                        );
                    } catch(E) {
                        try { obj.error.standard_unexpected_error_alert(document.getElementById('adminStrings').getString('staff.admin.transit_list.retrieving_row.error'),E); } catch(F) { alert(E); }
                    }
                },
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list.retrieve_selection();
                        obj.selection_list = util.functional.map_list(
                            sel,
                            function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
                        );
                        obj.error.sdump('D_TRACE','admin.transit_list: selection list = ' + js2JSON(obj.selection_list) );
                        if (obj.selection_list.length == 0) {
                            obj.controller.view.sel_edit.setAttribute('disabled','true');
                            obj.controller.view.sel_opac.setAttribute('disabled','true');
                            obj.controller.view.sel_bucket.setAttribute('disabled','true');
                            obj.controller.view.sel_copy_details.setAttribute('disabled','true');
                            obj.controller.view.sel_patron.setAttribute('disabled','true');
                            obj.controller.view.sel_transit_abort.setAttribute('disabled','true');
                            obj.controller.view.sel_clip.setAttribute('disabled','true');
                        } else {
                            obj.controller.view.sel_edit.setAttribute('disabled','false');
                            obj.controller.view.sel_opac.setAttribute('disabled','false');
                            obj.controller.view.sel_patron.setAttribute('disabled','false');
                            obj.controller.view.sel_bucket.setAttribute('disabled','false');
                            obj.controller.view.sel_copy_details.setAttribute('disabled','false');
                            obj.controller.view.sel_transit_abort.setAttribute('disabled','false');
                            obj.controller.view.sel_clip.setAttribute('disabled','false');
                        }
                    } catch(E) {
                        alert('FIXME: ' + E);
                    }
                },
            }
        );
    },

    'get_transit_and_hold_and_run_func' : function (transit_id,do_this) {
        var obj = this;
        obj.network.simple_request('FM_ATC_RETRIEVE', [ ses(), transit_id ],
            function(req2) {
                try {
                    var r_atc = req2.getResultObject();
                    if (typeof r_atc.ilsevent != 'undefined') throw(r_atc);

                    if (instanceOf(r_atc,atc)) {
                        do_this(r_atc,null);
                    } else if (instanceOf(r_atc,ahtc)) {
                        obj.network.simple_request('FM_AHR_RETRIEVE', [ ses(), r_atc.hold() ],
                            function(req3) {
                                try {
                                    var r_ahr = req3.getResultObject();
                                    if (typeof r_ahr.ilsevent != 'undefined') throw(r_ahr);
                                    if (r_ahr.length == 0) {
                                        try { obj.error.standard_unexpected_error_alert(document.getElementById('adminStrings').getString('staff.admin.transit_list.empty_array.error') + document.getElementById('adminStrings').getFormattedString('staff.admin.transit_list.empty_array.error', [r_atc.hold(), transit_id]),E); } catch(F) { alert(E); }
                                        do_this(r_atc,null);
                                    } else {
                                        if (instanceOf(r_ahr[0],ahr)) {
                                            do_this(r_atc,r_ahr[0]);
                                        } else {
                                            throw(r_ahr);
                                        }
                                    }
                                } catch(E) {
                                    try { obj.error.standard_unexpected_error_alert(document.getElementById('adminStrings').getFormattedString('staff.admin.transit_list.empty_array.error', [r_atc.hold(), transit_id]),E); } catch(F) { alert(E); }
                                    do_this(r_atc,null);
                                }
                            }
                        );
                    } else {
                        throw(r_atc);
                    }

                } catch(E) {
                    try { obj.error.standard_unexpected_error_alert(document.getElementById('adminStrings').getFormattedString('staff.admin.transit_list.transit_id.error', [transit_id]),E); } catch(F) { alert(E); }
                }
            }
        );
    },

    'get_rest_of_row_given_transit_and_hold' : function(params,transit,hold) {
        var obj = this;
        var row = params.row;

        row.my.atc = transit;
        if (hold) row.my.ahr = hold;

        obj.network.simple_request(
            'FM_ACP_RETRIEVE',
            [ row.my.atc.target_copy() ],
            function(req) {
                try { 
                    var r_acp = req.getResultObject();
                    if (typeof r_acp.ilsevent != 'undefined') throw(r_acp);
                    row.my.acp = r_acp;

                    obj.network.simple_request(
                        'FM_ACN_RETRIEVE.authoritative',
                        [ r_acp.call_number() ],
                        function(req2) {
                            try {
                                var r_acn = req2.getResultObject();
                                if (typeof r_acn.ilsevent != 'undefined') throw(r_acn);
                                row.my.acn = r_acn;

                                if (row.my.acn.record() > 0) {
                                    obj.network.simple_request(
                                        'MODS_SLIM_RECORD_RETRIEVE.authoritative',
                                        [ r_acn.record() ],
                                        function(req3) {
                                            try {
                                                var r_mvr = req3.getResultObject();
                                                if (typeof r_mvr.ilsevent != 'undefined') throw(r_mvr);
                                                row.my.mvr = r_mvr;

                                                params.row_node.setAttribute(
                                                    'retrieve_id', js2JSON( { 
                                                        'copy_id' : row.my.acp ? row.my.acp.id() : null, 
                                                        'doc_id' : row.my.mvr ? row.my.mvr.doc_id() : null,  
                                                        'barcode' : row.my.acp ? row.my.acp.barcode() : null, 
                                                        'acp_id' : row.my.acp ? row.my.acp.id() : null, 
                                                        'acn_id' : row.my.acn ? row.my.acn.id() : null,  
                                                        'atc_id' : row.my.atc ? row.my.atc.id() : null,  
                                                        'ahr_id' : row.my.ahr ? row.my.ahr.id() : null,  
                                                    } )
                                                );
                                                if (typeof params.on_retrieve == 'function') {
                                                    params.on_retrieve(row);
                                                }
                                            } catch(E) {
                                                try { obj.error.standard_unexpected_error_alert('retrieving mvr',E); } catch(F) { alert(E); }
                                            }
                                        }
                                    );
                                } else {
                                    params.row_node.setAttribute(
                                        'retrieve_id', js2JSON( { 
                                            'copy_id' : row.my.acp ? row.my.acp.id() : null, 
                                            'doc_id' : row.my.mvr ? row.my.mvr.doc_id() : null,  
                                            'barcode' : row.my.acp ? row.my.acp.barcode() : null, 
                                            'acp_id' : row.my.acp ? row.my.acp.id() : null, 
                                            'acn_id' : row.my.acn ? row.my.acn.id() : null,  
                                            'atc_id' : row.my.atc ? row.my.atc.id() : null,  
                                            'ahr_id' : row.my.ahr ? row.my.ahr.id() : null,  
                                        } )
                                    );
                                    if (typeof params.on_retrieve == 'function') {
                                        params.on_retrieve(row);
                                    }
                                }
                    
                            } catch(E) {
                                try { obj.error.standard_unexpected_error_alert('retrieving acn',E); } catch(F) { alert(E); }
                            }
                        }
                    );


                } catch(E) {
                    try { obj.error.standard_unexpected_error_alert('retrieving acp',E); } catch(F) { alert(E); }
                }
            }
        );
    },

    'controller_init' : function() {
        var obj = this;

        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                'control_map' : {
                    'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
                    'sel_clip' : [ ['command'], function() { obj.list.clipboard(); } ],
                    'sel_edit' : [ ['command'], function() { try { obj.spawn_copy_editor(0); } catch(E) { alert(E); } } ],
                    'sel_opac' : [ ['command'], function() { JSAN.use('cat.util'); cat.util.show_in_opac(obj.selection_list); } ],
                    'sel_transit_abort' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.abort_transits(obj.selection_list); } ],
                    'sel_patron' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.show_last_few_circs(obj.selection_list); } ],
                    'sel_copy_details' : [ ['command'], function() { JSAN.use('circ.util'); for (var i = 0; i < obj.selection_list.length; i++) { circ.util.show_copy_details( obj.selection_list[i].copy_id ); } } ],
                    'sel_bucket' : [ ['command'], function() { JSAN.use('cat.util'); cat.util.add_copies_to_bucket(obj.selection_list); } ],
                    'cmd_print_list' : [ ['command'], function() { obj.print_list(0); } ],
                    'cmd_kick_off' : [ ['command'], function(ev) { ev.target.disabled = true; obj.kick_off(); } ],
                    'sdate' : [ ['change'], function(ev) { ev.target.value = obj.handle_date(ev.target.value,false); obj.sdate = ev.target.value; /*alert('obj.sdate='+obj.sdate);*/ } ],
                    'edate' : [ ['change'], function(ev) { ev.target.value = obj.handle_date(ev.target.value,true); obj.edate = ev.target.value; /*alert('obj.edate='+obj.edate);*/ } ],
                }
            }
        );
        this.controller.render();

    },

    'print_list' : function(which_list) {
        var obj = this;
        try {
            var list = which_list == 0 ? obj.list : obj.list2;
            var p = { 
                'template' : 'transit_list'
            };
            list.print(p);
        } catch(E) {
            obj.error.standard_unexpected_error_alert('print',E); 
        }
    },
    
    'spawn_copy_editor' : function(which_list) {

        var obj = this;

        JSAN.use('util.functional');

        var list = which_list == 0 ? obj.selection_list : obj.selection_list2;

        list = util.functional.map_list(
            list,
            function (o) {
                return o.copy_id;
            }
        );

        JSAN.use('cat.util'); cat.util.spawn_copy_editor( { 'copy_ids' : list, 'edit' : 1 } );

    },

}

dump('exiting admin.transit_list.js\n');
