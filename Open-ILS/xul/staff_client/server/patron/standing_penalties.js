var list; var archived_list; var data; var error; var net; var rows; var archived_rows;

function default_focus() { document.getElementById('apply_btn').focus(); } // parent interfaces often call this

function penalty_init() {
    try {
        commonStrings = document.getElementById('commonStrings');
        patronStrings = document.getElementById('patronStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                commonStrings.getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();
        XML_HTTP_SERVER = data.server_unadorned;

        JSAN.use('util.error'); error = new util.error();
        JSAN.use('util.network'); net = new util.network();
        JSAN.use('patron.util'); 
        JSAN.use('util.list'); 
        JSAN.use('util.functional'); 
        JSAN.use('util.widgets');

        init_list();
        init_archived_list();
        document.getElementById('date1').year = document.getElementById('date1').year - 1;
        document.getElementById('cmd_apply_penalty').addEventListener('command', handle_apply_penalty, false);
        document.getElementById('cmd_remove_penalty').addEventListener('command', handle_remove_penalty, false);
        document.getElementById('cmd_edit_penalty').addEventListener('command', handle_edit_penalty, false);
        document.getElementById('cmd_archive_penalty').addEventListener('command', handle_archive_penalty, false);
        document.getElementById('cmd_retrieve_archived_penalties').addEventListener('command', handle_retrieve_archived_penalties, false);
        populate_list();
        default_focus();

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> penalty_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function init_list() {
    try {

        list = new util.list( 'ausp_list' );
        list.init( 
            {
                'columns' : patron.util.ausp_columns({}),
                'retrieve_row' : retrieve_row,
                'on_select' : generate_handle_selection(list)
            } 
        );

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> init_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function init_archived_list() {
    try {

        archived_list = new util.list( 'archived_ausp_list' );
        archived_list.init( 
            {
                'columns' : patron.util.ausp_columns({}),
                'retrieve_row' : retrieve_row, // We're getting fleshed objects for now, but if we move to just ausp.id's, then we'll need to put a per-id fetcher in here
                'on_select' : generate_handle_selection(archived_list)
            } 
        );

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> init_archived_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}


function retrieve_row (params) { // callback function for fleshing rows in a list
    params.treeitem_node.setAttribute('retrieve_id',params.row.my.ausp.id()); 
    params.on_retrieve(params.row); 
    return params.row; 
}

function generate_handle_selection(which_list) {
    return function (ev) { // handler for list row selection event
        var sel = which_list.retrieve_selection();
        var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
        if (which_list == list) { // top list
            if (ids.length > 0) {
                document.getElementById('cmd_remove_penalty').setAttribute('disabled','false');
                document.getElementById('cmd_edit_penalty').setAttribute('disabled','false');
                document.getElementById('cmd_archive_penalty').setAttribute('disabled','false');
            } else {
                document.getElementById('cmd_remove_penalty').setAttribute('disabled','true');
                document.getElementById('cmd_edit_penalty').setAttribute('disabled','true');
                document.getElementById('cmd_archive_penalty').setAttribute('disabled','true');
            }
        }
    };
}

function populate_list() {
    try {

        rows = {};
        list.clear();
        for (var i = 0; i < xulG.patron.standing_penalties().length; i++) {
            var row_params = {
                'row' : {
                    'my' : {
                        'ausp' : xulG.patron.standing_penalties()[i],
                        'csp' : xulG.patron.standing_penalties()[i].standing_penalty(),
                        'au' : xulG.patron,
                    }
                }
            };
            rows[ xulG.patron.standing_penalties()[i].id() ] = list.append( row_params );
        };

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> populate_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function handle_apply_penalty(ev) {
    try {
        JSAN.use('util.window');
        var win = new util.window();
        var my_xulG = win.open(
            urls.XUL_NEW_STANDING_PENALTY,
            'new_standing_penalty',
            'chrome,resizable,modal',
            {}
        );

        if (!my_xulG.id) { return 0; }

        var penalty = new ausp();
        penalty.usr( xulG.patron.id() );
        penalty.isnew( 1 );
        penalty.standing_penalty( my_xulG.id );
        penalty.org_unit( ses('ws_ou') );
        penalty.note( my_xulG.note );
        net.simple_request(
            'FM_AUSP_APPLY', 
            [ ses(), penalty ],
            generate_request_handler_for_penalty_apply( penalty, my_xulG.id )
        );

        document.getElementById('progress').hidden = false;

    } catch(E) {
        alert('error: ' + E);
        var err_prefix = 'standing_penalties.js -> handle_apply_penalty() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function generate_request_handler_for_penalty_apply(penalty,id) {
    return function(reqobj) {
        try {

            var req = reqobj.getResultObject();
            if (typeof req.ilsevent != 'undefined') {
                error.standard_unexpected_error_alert(
                    patronStrings.getFormattedString('staff.patron.standing_penalty.apply_error',[data.hash.csp[id].name()]),
                    req
                );
            } else {
                penalty.id(req);
                JSAN.use('patron.util'); JSAN.use('util.functional');
                //xulG.patron.standing_penalties( xulG.patron.standing_penalties().concat( penalty ) ); // Not good enough for pcrud
                xulG.patron = patron.util.retrieve_fleshed_au_via_id( ses(), xulG.patron.id() ); // So get the real deal instead
                penalty = util.functional.find_list( xulG.patron.standing_penalties(), function(o) { return o.id() == req; } );

                var row_params = {
                    'row' : {
                        'my' : {
                            'ausp' : penalty,
                            'csp' : typeof penalty.standing_penalty() == 'object'
                                ? penalty.standing_penalty()
                                : data.hash.csp[ penalty.standing_penalty() ],
                            'au' : xulG.patron,
                        }
                    }
                };
                rows[ penalty.id() ] = list.append( row_params );
            }
            /*
            if (xulG && typeof xulG.refresh == 'function') {
                xulG.refresh();
            }
            */
            document.getElementById('progress').hidden = true;

        } catch(E) {
            var err_prefix = 'standing_penalties.js -> request_handler_for_penalty_apply() : ';
            if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
        }
    };
}
 
function handle_remove_penalty(ev) {
    try {

        var sel = list.retrieve_selection();
        var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
        if (! ids.length > 0 ) return;

        var funcs = [];
        for (var i = 0; i < ids.length; i++) {
            funcs.push( generate_penalty_remove_function(ids[i]) );
        } 
        funcs.push(
            function() {
                /*
                if (xulG && typeof xulG.refresh == 'function') {
                    xulG.refresh();
                }
                */
                document.getElementById('progress').hidden = true;

                patron.util.set_penalty_css(xulG.patron, patron.display.w.document.documentElement);
            }
        );
        document.getElementById('progress').hidden = false;
        JSAN.use('util.exec'); var exec = new util.exec();
        exec.chain(funcs);

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> request_handler_for_penalty_apply() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function generate_penalty_remove_function(id) {
    return function() {
        try {

            var penalty = util.functional.find_list( xulG.patron.standing_penalties(), function(o) { return o.id() == id; } );
            penalty.isdeleted(1);

            var req = net.simple_request( 'FM_AUSP_REMOVE', [ ses(), penalty ] );
            if (typeof req.ilsevent != 'undefined' || String(req) != '1') {
                error.standard_unexpected_error_alert(patronStrings.getFormattedString('staff.patron.standing_penalty.remove_error',[id]),req);
            } else {
                var node = rows[ id ].treeitem_node;
                var parentNode = node.parentNode;
                parentNode.removeChild( node );
                delete(rows[ id ]);
            }

        } catch(E) {
            var err_prefix = 'standing_penalties.js -> penalty_remove_function() : ';
            if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
        }
    }; 
}

function handle_edit_penalty(ev) {
    try {

        JSAN.use('util.window');
        var win = new util.window();

        var sel = list.retrieve_selection();
        var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
        if (ids.length > 0) {
            for (var i = 0; i < ids.length; i++) {
                var penalty = util.functional.find_list( xulG.patron.standing_penalties(), function(o) { return o.id() == ids[i]; } );
                var my_xulG = win.open(
                    urls.XUL_EDIT_STANDING_PENALTY,
                    'new_standing_penalty',
                    'chrome,resizable,modal',
                    { 
                        'id' : typeof penalty.standing_penalty() == 'object' ? penalty.standing_penalty().id() : penalty.standing_penalty(), 
                        'note' : penalty.note() 
                    }
                );
                if (my_xulG.modify) {
                    document.getElementById('progress').hidden = false;
                    penalty.note( my_xulG.note ); /* this is for rendering, and propogates by reference to the object associated with the row in the GUI */
                    penalty.standing_penalty( my_xulG.id );
                    penalty.ischanged( 1 );
                    dojo.require('openils.PermaCrud');
                    var pcrud = new openils.PermaCrud( { authtoken :ses() });
                    pcrud.update( penalty, {
                        timeout : 10, // makes it synchronous
                        onerror : function(r) {
                            try {
                                document.getElementById('progress').hidden = true;
                                var res = openils.Util.readResponse(r,true);
                                error.standard_unexpected_error_alert(patronStrings.getString('staff.patron.standing_penalty.update_error'),res);
                            } catch(E) {
                                alert(E);
                            }
                        },
                        oncomplete : function gen_func(p,row_id) {
                            return function(r) {
                                try {
                                    var res = openils.Util.readResponse(r,true);
                                    /* FIXME - test for success */
                                    var row_params = rows[row_id];
                                    row_params.row.my.ausp = p;
                                    row_params.row.my.csp = p.standing_penalty();
                                    list.refresh_row( row_params );

                                    patron.util.set_penalty_css(xulG.patron, patron.display.w.document.documentElement);
                                    document.getElementById('progress').hidden = true;
                                } catch(E) {
                                    alert(E);
                                }
                            }
                        }(penalty,ids[i])
                    });
                }
            } 
            /*
            if (xulG && typeof xulG.refresh == 'function') {
                xulG.refresh();
            }
            */
        }

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> handle_edit_penalty() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function handle_archive_penalty(ev) {
    try {
        var outstanding_requests = 0;
        var sel = list.retrieve_selection();
        var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
        if (ids.length > 0) {
            document.getElementById('progress').hidden = false;
            for (var i = 0; i < ids.length; i++) {
                outstanding_requests++;
                var penalty = util.functional.find_list( xulG.patron.standing_penalties(), function(o) { return o.id() == ids[i]; } );
                penalty.ischanged( 1 );
                penalty.stop_date( util.date.formatted_date(new Date(),'%F') );
                dojo.require('openils.PermaCrud');
                var pcrud = new openils.PermaCrud( { authtoken :ses() });
                pcrud.update( penalty, {
                    onerror : function(r) {
                        try {
                            var res = openils.Util.readResponse(r,true);
                            error.standard_unexpected_error_alert(patronStrings.getString('staff.patron.standing_penalty.update_error'),res);
                        } catch(E) {
                            alert(E);
                        }
                        if (--outstanding_requests==0) {
                            document.getElementById('progress').hidden = true;
                        }
                    },
                    oncomplete : function gen_func(row_id) {
                        return function(r) {
                            try {
                                var res = openils.Util.readResponse(r,true);
                                /* FIXME - test for success */
                                var node = rows[row_id].treeitem_node;
                                var parentNode = node.parentNode;
                                parentNode.removeChild( node );
                                delete(rows[row_id]);
                            } catch(E) {
                                alert(E);
                            }
                            if (--outstanding_requests==0) {
                                document.getElementById('progress').hidden = true;

                                patron.util.set_penalty_css(xulG.patron, patron.display.w.document.documentElement);
                            }
                        }
                    }(ids[i])
                });
            } 
            /*
            if (xulG && typeof xulG.refresh == 'function') {
                xulG.refresh();
            }
            */
        }

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> handle_archive_penalty() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function handle_retrieve_archived_penalties() {
    try {
        document.getElementById('archived_progress').hidden = false;
        archived_list.clear(); archived_rows = {};
        JSAN.use('util.date');
        dojo.require('openils.PermaCrud');
        var pcrud = new openils.PermaCrud( { authtoken :ses() });
        var date2 = document.getElementById('date2').dateValue;
        date2.setDate( date2.getDate() + 1 ); // Javascript will wrap into subsequent months
        pcrud.search(
            'ausp',
            {
                usr : xulG.patron.id(),
                stop_date : {
                    'between' : [ 
                        document.getElementById('date1').value, 
                        document.getElementById('date2').value == util.date.formatted_date(new Date(),'%F') ? 
                            'now' : util.date.formatted_date( date2 ,'%F')
                    ]
                }
            },
            {
                async : true,
                streaming : true,
                onerror : function(r) {
                    try {
                        var res = openils.Util.readResponse(r,true);
                        error.standard_unexpected_error_alert(patronStrings.getString('staff.patron.standing_penalty.retrieve_error'),res);
                    } catch(E) {
                        error.standard_unexpected_error_alert(patronStrings.getString('staff.patron.standing_penalty.retrieve_error'),r);
                    }
                },
                oncomplete : function() {
                    document.getElementById('archived_progress').hidden = true;
                },
                onresponse : function(r) {
                    try {
                        var my_ausp = openils.Util.readResponse(r);
                        var row_params = {
                            'row' : {
                                'my' : {
                                    'ausp' : my_ausp,
                                    'csp' : my_ausp.standing_penalty(),
                                    'au' : xulG.patron,
                                }
                            }
                        };
                        archived_rows[ my_ausp.id() ] = archived_list.append( row_params );
                    } catch(E) {
                        error.standard_unexpected_error_alert(patronStrings.getString('staff.patron.standing_penalty.retrieve_error'),E);
                    }
                }
            }
        );
    } catch(E) {
        var err_prefix = 'standing_penalties.js -> handle_retrieve_archived_penalties() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}
