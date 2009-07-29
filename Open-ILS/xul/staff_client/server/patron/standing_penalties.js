var list; var data; var error; var net; var rows;

function default_focus() { document.getElementById('apply_btn').focus(); } // parent interfaces often call this

function penalty_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect"); 

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
        document.getElementById('cmd_apply_penalty').addEventListener('command', handle_apply_penalty, false);
        document.getElementById('cmd_remove_penalty').addEventListener('command', handle_remove_penalty, false);
        document.getElementById('cmd_edit_penalty').addEventListener('command', handle_edit_penalty, false);
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
                'map_row_to_columns' : patron.util.std_map_row_to_columns(),
                'retrieve_row' : retrieve_row,
                'on_select' : handle_selection
            } 
        );

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> init_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function retrieve_row (params) { // callback function for fleshing rows in a list
    params.row_node.setAttribute('retrieve_id',params.row.my.ausp.id()); 
    params.on_retrieve(params.row); 
    return params.row; 
}

function handle_selection (ev) { // handler for list row selection event
    var sel = list.retrieve_selection();
    var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
    if (ids.length > 0) {
        document.getElementById('cmd_remove_penalty').setAttribute('disabled','false');
        document.getElementById('cmd_edit_penalty').setAttribute('disabled','false');
    } else {
        document.getElementById('cmd_remove_penalty').setAttribute('disabled','true');
        document.getElementById('cmd_edit_penalty').setAttribute('disabled','true');
    }
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
            rows[ xulG.patron.standing_penalties()[i].id() ] = function(p){ return p; }(row_params); // careful with vars in loops
            list.append( row_params );
        };

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> populate_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function handle_apply_penalty(ev) {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect"); 
        JSAN.use('util.window');
        var win = new util.window();
        var my_xulG = win.open(
            urls.XUL_NEW_STANDING_PENALTY,
            'new_standing_penalty',
            'chrome,resizable,modal',
            {}
        );

        if (!my_xulG.id) { alert('cancelled'); return 0; }

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
                xulG.patron.standing_penalties( xulG.patron.standing_penalties().concat( penalty ) );
                var row_params = {
                    'row' : {
                        'my' : {
                            'ausp' : penalty,
                            'csp' : data.hash.csp[ penalty.standing_penalty() ],
                            'au' : xulG.patron,
                        }
                    }
                };
                rows[ penalty.id() ] = row_params;
                list.append( row_params );
            }
            if (xulG && typeof xulG.refresh == 'function') {
                xulG.refresh();
            }
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
                if (xulG && typeof xulG.refresh == 'function') {
                    xulG.refresh();
                }
                document.getElementById('progress').hidden = true;
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
                var node = rows[ id ].my_node;
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

        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect"); 
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
                    pcrud.apply( penalty, {
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
                        oncomplete : function(r) {
                            try {
                                var res = openils.Util.readResponse(r,true);
                                var row_params = rows[ ids[i] ];
                                row_params.row.my.ausp = penalty;
                                row_params.row.my.csp = penalty.standing_penalty();
                                list.refresh_row( row_params );
                                document.getElementById('progress').hidden = true;
                            } catch(E) {
                                alert(E);
                            }
                        }
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
