var list; var error; var net; var rows; var menu_lib;

function $(id) { return document.getElementById(id); }

//// parent interfaces often call these
function default_focus() { $('lib_menu').focus(); }
function refresh() { populate_list(); }
////

function staged_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect"); 

        commonStrings = $('commonStrings');
        patronStrings = $('patronStrings');

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

        dojo.require('openils.Util');

        populate_lib_menu();
        init_list();
        $('list_actions').appendChild( list.render_list_actions() );
        list.set_list_actions();
        $('cmd_cancel').addEventListener('command', gen_event_handler('cancel'), false);
        $('cmd_load').addEventListener('command', gen_event_handler('load'), false);
        populate_list();
        default_focus();

    } catch(E) {
        var err_prefix = 'staged.js -> staged_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function populate_lib_menu() {
    try {
        JSAN.use('util.widgets');
        var x = document.getElementById('lib_menu_placeholder');
        if (!x) { return; }
        util.widgets.remove_children( x );

        JSAN.use('util.file');
        var file = new util.file('offline_ou_list');
        if (file._file.exists()) {
            var list_data = file.get_object(); file.close();
            var ml = util.widgets.make_menulist( list_data[0], ses('ws_ou') );
            ml.setAttribute('id','lib_menu');
            x.appendChild( ml );
            ml.addEventListener(
                'command',
                function(ev) {
                    menu_lib = ev.target.value;
                    populate_list();
                },
                false
            );
        } else {
            alert($("patronStrings").getString('staff.patron.staged.lib_menus.missing_library_list'));
        }
    } catch(E) {
        alert('Error in staged.js, populate_lib_menu(): ' + E);
    }
}

function gen_event_handler(method) { // cancel or load?
    return function(ev) {
        try {
            var sel = list.retrieve_selection();
            var ids = util.functional.map_list( sel, function(o) { return o.getAttribute('retrieve_id'); } );

            if (method == 'cancel') {
                cancel( ids );
            } else {
                load( ids );
            }

        } catch(E) {
            alert('Error in patron/staged.js, handle_???_event(): ' + E);
        }
    };
}

function cancel(ids) {
    try {
        var pm = $('progress'); pm.value = 0; pm.hidden = false;
        var idx = -1;

        fieldmapper.standardRequest(
            [ api['FM_STGU_CANCEL'].app, api['FM_STGU_CANCEL'].method ],
            {   async: true,
                params: [ses(), ids],
                onresponse: function(r) {
                    try {
                        idx++; pm.value = Number( pm.value ) + 100/ids.length;
                        var result = openils.Util.readResponse(r);
                        if (typeof result.ilsevent != 'undefined') { throw(result); }
                    } catch(E) {
                        error.standard_unexpected_error_alert('In patron/staged.js, handle_'+i+'_event onresponse.',E);
                    }
                },
                onerror: function(r) {
                    try {
                        var result = openils.Util.readResponse(r);
                        throw(result);
                    } catch(E) {
                        error.standard_unexpected_error_alert('In patron/staged.js, handle_'+i+'_event onerror.',E);
                    }
                    pm.hidden = true; pm.value = 0; populate_list();
                },
                oncomplete: function(r) {
                    try {
                        var result = openils.Util.readResponse(r);
                    } catch(E) {
                        error.standard_unexpected_error_alert('In patron/staged.js, handle_'+i+'_event oncomplete.',E);
                    }
                    pm.hidden = true; pm.value = 0; populate_list();
                }
            }
        );
    } catch(E) {
        alert('Error in staged.js, cancel(): ' + E);
    }
}

function spawn_search(s) {
    data.stash_retrieve();
    xulG.new_patron_tab( {}, { 'doit' : 1, 'query' : s } );
}

function spawn_editor(p) {
    var url = urls.XUL_PATRON_EDIT;
    var loc = xulG.url_prefix( urls.XUL_REMOTE_BROWSER );
    xulG.new_tab(
        loc, 
        {}, 
        { 
            'url' : url,
            'show_print_button' : true , 
            'tab_name' : $("patronStrings").getFormattedString('staff.patron.staged.register_patron',[p.stage]),
            'passthru_content_params' : {
                'spawn_search' : spawn_search,
                'spawn_editor' : spawn_editor,
                'url_prefix' : xulG.url_prefix,
                'new_tab' : xulG.new_tab,
                'new_patron_tab' : xulG.new_patron_tab,
                'params' : p
            }
        }
    );
}

function load( ids ) {
    try {
        var seen = {};

        for (var i = 0; i < ids.length; i++) {
            if (! seen[ ids[i] ]) {
                seen[ ids[i] ] = true;
                spawn_editor( { 'stage' : ids[i] } );
            }
        }

    } catch(E) {
        alert('Error in staged.js, load(): ' + E);
    }
}

function init_list() {
    try {

        list = new util.list( 'stgu_list' );
        list.init( 
            {
                'columns' : list.fm_columns(
                    'stgu', {
                        'stgu_ident_type' : { 'render' : function(my) { return data.hash.cit[ my.stgu.ident_type() ].name(); } },
                        'stgu_home_ou' : { 'render' : function(my) { return data.hash.aou[ my.stgu.home_ou() ].shortname(); } }
                    }
                ),
                'retrieve_row' : retrieve_row,
                'on_select' : handle_selection
            }
        );

    } catch(E) {
        var err_prefix = 'staged.js -> init_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function retrieve_row(params) { // callback function for fleshing rows in a list
    try {
        params.row_node.setAttribute('retrieve_id',params.row.my.stgu.usrname()); 
        params.on_retrieve(params.row); 
    } catch(E) {
        alert('Error in staged.js, retrieve_row(): ' + E);
    }
    return params.row; 
}

function handle_selection(ev) { // handler for list row selection event
    var sel = list.retrieve_selection();
    if (sel.length > 0) {
        $('cmd_cancel').setAttribute('disabled','false');
        $('cmd_load').setAttribute('disabled','false');
    } else {
        $('cmd_cancel').setAttribute('disabled','true');
        $('cmd_load').setAttribute('disabled','true');
    }
};

function populate_list() {
    try {

        rows = {};
        list.clear();

        function onResponse(r) {
            var blob = openils.Util.readResponse(r);
            var row_params = {
                'row' : {
                    'my' : {
                        'stgu' : blob.user
                    }
                }
            };
            rows[ blob.user.usrname() ] = list.append( row_params );
        }

        function onError(r) {
            var my_stgu = openils.Util.readResponse(r);
            alert('error, my_stgu = ' + js2JSON(my_stgu));
        }

        fieldmapper.standardRequest(
            [api['FM_STGU_RETRIEVE'].app, api['FM_STGU_RETRIEVE'].method ],
            {   async: true,
                params: [ses(), menu_lib || ses('ws_ou')],
                onresponse : onResponse,
                onerror : onError,
                oncomplete : function() {
                }
            }
        );

    } catch(E) {
        var err_prefix = 'staged.js -> populate_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}
