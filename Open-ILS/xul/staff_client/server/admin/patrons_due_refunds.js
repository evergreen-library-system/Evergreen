var list; var error; var net; var rows; var menu_lib;

function $(id) { return document.getElementById(id); }

//// parent interfaces often call these
function default_focus() { $('au_list').focus(); }
function refresh() { populate_list(); }
////

function patrons_due_refunds_init() {
    try {
        if (typeof JSAN == 'undefined') {
            throw(
                $('commonStrings').getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();

        JSAN.use('util.error'); error = new util.error();
        JSAN.use('util.network'); net = new util.network();
        JSAN.use('patron.util'); 
        JSAN.use('util.list'); 
        JSAN.use('util.money'); 
        JSAN.use('util.functional'); 
        JSAN.use('util.widgets');

        dojo.require('openils.Util');
        dojo.require('dojo.date.locale');
        dojo.require('dojo.date.stamp');

        render_lib_menu();
        init_list();
        $('list_actions').appendChild( list.render_list_actions() );
        list.set_list_actions();
        $('retrieve_patron').addEventListener('command', handle_retrieve, false);
        populate_list();
        default_focus();

    } catch(E) {
        var err_prefix = 'patrons_due_refundss.js -> patrons_due_refunds_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function handle_retrieve() { 
    try {
        var sel = list.retrieve_selection();
        var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );

        var seen = {};
        for (var i = 0; i < ids.length; i++) {
            var patron_id = ids[i];
            if (typeof patron_id == 'null') continue;
            if (seen[patron_id]) continue; seen[patron_id] = true;
            xulG.new_patron_tab(
                {},
                { 'id' : patron_id }
            );
        }

    } catch(E) {
        alert('Error in admin/patrons_due_refunds.js, handle_retrieve(): ' + E);
    }
}

function init_list() {
    try {

        list = new util.list( 'au_list' );
        list.init( 
            {
                'columns' : [].concat(
                    list.fm_columns('au',{
                        '*' : { 'hidden' : true },
                        'au_family_name' : { 'hidden' : false },
                        'au_first_given_name' : { 'hidden' : false },
                        'au_second_given_name' : { 'hidden' : false },
                        'au_barred' : { 'hidden' : false },
                        'au_dob' : { 'hidden' : false }
                    })
                ).concat([
                    {
                        'id' : 'balance_owed', 'label' : 'Balance Owed', 'sort_type' : 'money', 'render' : function(my) { 
                            return util.money.sanitize( my.balance_owed ); 
                        }
                    },
                    {
                        'id' : 'last_billing_activity', 'label' : 'Last Billing Activity', 'sort_type' : 'date', 'render' : function(my) { 
                            JSAN.use('util.date');
                            return util.date.formatted_date( my.last_billing_activity, '%{localized}' );
                        }
                    }
                ]),
                'retrieve_row' : retrieve_row,
                'on_select' : handle_selection
            }
        );

    } catch(E) {
        var err_prefix = 'patron_due_refunds.js -> init_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function retrieve_row(params) { // callback function for fleshing rows in a list
    params.treeitem_node.setAttribute('retrieve_id',params.row.my.au.id()); 
    params.on_retrieve(params.row); 
    return params.row; 
}

function handle_selection(ev) { // handler for list row selection event
    var sel = list.retrieve_selection();
    if (sel.length > 0) {
        $('retrieve_patron').setAttribute('disabled','false');
    } else {
        $('retrieve_patron').setAttribute('disabled','true');
    }
};

function populate_list() {
    try {

        rows = {};
        list.clear();
        $('progress').hidden = false;

        function onResponse(r) {
            try {
                var robj = openils.Util.readResponse(r);
                var row_params = {
                    'row' : {
                        'my' : {
                            'au' : robj.usr,
                            'balance_owed' : robj.balance_owed,
                            'last_billing_activity' : robj.last_billing_activity
                        }
                    }
                };
                rows[ robj.usr.id() ] = list.append( row_params );
            } catch(E) {
                alert('Error in patrons_due_refunds.js, populate_list, onResponse(): ' + E);
            }
        }

        function onError(r) {
            try {
                var robj = openils.Util.readResponse(r);
                alert('error, robj = ' + js2JSON(robj));
            } catch(E) {
                alert('Error in patrons_due_refunds.js, populate_list, onError(): ' + E);
            }
        }

        fieldmapper.standardRequest(
            [api['FM_AU_BLOBS_WITH_NEGATIVE_BALANCE'].app, api['FM_AU_BLOBS_WITH_NEGATIVE_BALANCE'].method ],
            {   async: true,
                params: [ses(),menu_lib],
                onresponse : onResponse,
                onerror : onError,
                oncomplete : function() {
                    $('progress').hidden = true;
                }
            }
        );

    } catch(E) {
        alert('Error in patrons_due_refunds.js, populate_list(): ' + E);
    }
}

function render_lib_menu() {
    try {
        var x = document.getElementById('lib_menu_placeholder');
        if (!x) { return; }
        util.widgets.remove_children( x );

        JSAN.use('util.file');
        var file = new util.file('offline_ou_list');
        if (file._file.exists()) {
            var list_data = file.get_object(); file.close();
            menu_lib = x.getAttribute('value') || ses('ws_ou');
            var ml = util.widgets.make_menulist( list_data[0], menu_lib );
            ml.setAttribute('id','lib_menu');
            x.appendChild( ml );
            ml.addEventListener(
                'command',
                function(ev) {
                    menu_lib = ev.target.value;
                    x.setAttribute('value',ev.target.value); oils_persist(x);
                    populate_list();
                },
                false
            );
        } else {
            throw('Missing offline org unit list.');
        }

    } catch(E) {
        alert('Error in patrons_due_refunds.js, render_lib_menu(): ' + E);
    }
}
