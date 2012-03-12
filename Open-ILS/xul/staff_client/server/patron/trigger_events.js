var list; var error; var net; var rows;

function $(id) { return document.getElementById(id); }

//// parent interfaces often call these
function default_focus() { $('atev_list').focus(); }
function refresh() { populate_list(); }
////

function trigger_event_init() {
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

        init_list();
        $('list_actions').appendChild( list.render_list_actions() );
        list.set_list_actions();
        $('cmd_cancel_event').addEventListener('command', gen_event_handler('cancel'), false);
        $('cmd_reset_event').addEventListener('command', gen_event_handler('reset'), false);
        $('circ').addEventListener('command', function() { populate_list(); }, false);
        $('ahr').addEventListener('command', function() { populate_list(); }, false);
        $('pending').addEventListener('command', function() { populate_list(); }, false);
        $('complete').addEventListener('command', function() { populate_list(); }, false);
        $('error').addEventListener('command', function() { populate_list(); }, false);
        populate_list();
        default_focus();

    } catch(E) {
        var err_prefix = 'trigger_events.js -> trigger_event_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function gen_event_handler(method) { // cancel or reset?
    return function(ev) {
        try {
            var sel = list.retrieve_selection();
            var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );

            var pm = $('progress'); pm.value = 0; pm.hidden = false;
            var idx = -1;

            var i = method == 'cancel' ? 'FM_ATEV_CANCEL' : 'FM_ATEV_RESET';
            fieldmapper.standardRequest(
                [ api[i].app, api[i].method ],
                {   async: true,
                    params: [ses(), ids],
                    onresponse: function(r) {
                        try {
                            idx++; pm.value = Number( pm.value ) + 100/ids.length;
                            var result = openils.Util.readResponse(r);
                            if (typeof result.ilsevent != 'undefined') { throw(result); }
                        } catch(E) {
                            error.standard_unexpected_error_alert('In patron/trigger_events.js, handle_'+i+'_event onresponse.',E);
                        }
                    },
                    onerror: function(r) {
                        try {
                            var result = openils.Util.readResponse(r);
                            throw(result);
                        } catch(E) {
                            error.standard_unexpected_error_alert('In patron/trigger_events.js, handle_'+i+'_event onerror.',E);
                        }
                        pm.hidden = true; pm.value = 0; populate_list();
                    },
                    oncomplete: function(r) {
                        try {
                            var result = openils.Util.readResponse(r);
                        } catch(E) {
                            error.standard_unexpected_error_alert('In patron/trigger_events.js, handle_'+i+'_event oncomplete.',E);
                        }
                        pm.hidden = true; pm.value = 0; populate_list();
                    }
                }
            );

        } catch(E) {
            alert('Error in patron/trigger_events.js, handle_???_event(): ' + E);
        }
    };
}

function init_list() {
    try {

        list = new util.list( 'atev_list' );
        list.init( 
            {
                'columns' : [].concat(
                    list.fm_columns('atev', {
                        'atev_target' : { 'render' : function(my) { return fieldmapper.IDL.fmclasses[my.atev.target().classname].label; } }
                    })
                ).concat(
                    list.fm_columns('atevdef', { 
                        '*' : { 'expanded_label' : true, 'hidden' : true }, 
                        'atevdef_name' : { 'hidden' : false }, 
                        'atevdef_reactor' : { 'render' : function(my) { return my.atevdef.reactor().id(); } }, 
                        'atevdef_validator' : { 'render' : function(my) { return my.atevdef.validator().id(); } } 
                    })
                ).concat(
                    list.fm_columns('atreact', { 
                        '*' : { 'expanded_label' : true, 'hidden' : true }, 
                        'atreact_module' : { 'hidden' : false } 
                    })
                ).concat(
                    list.fm_columns('atval', { 
                        '*' : { 'expanded_label' : true, 'hidden' : true }, 
                        'atval_module' : { 'hidden' : false } 
                    })
                ).concat(
                    list.fm_columns('circ', { 
                        '*' : { 'expanded_label' : true, 'hidden' : true }, 
                        'circ_due_date' : { 'hidden' : false } 
                    })
                ).concat(
                    list.fm_columns('acp', { 
                        '*' : { 'expanded_label' : true, 'hidden' : true }, 
                        'acp_barcode' : { 'hidden' : false } 
                    })
                ).concat(
                    list.fm_columns('ahr', { 
                        '*' : { 'expanded_label' : true, 'hidden' : true },
                        'ahr_id' : { 'hidden' : false } 
                    })
                ),
                'retrieve_row' : retrieve_row,
                'on_select' : handle_selection
            }
        );

    } catch(E) {
        var err_prefix = 'trigger_events.js -> init_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function retrieve_row(params) { // callback function for fleshing rows in a list
    params.treeitem_node.setAttribute('retrieve_id',params.row.my.atev.id()); 
    params.on_retrieve(params.row); 
    return params.row; 
}

function handle_selection(ev) { // handler for list row selection event
    var sel = list.retrieve_selection();
    if (sel.length > 0) {
        $('cmd_cancel_event').setAttribute('disabled','false');
        $('cmd_reset_event').setAttribute('disabled','false');
    } else {
        $('cmd_cancel_event').setAttribute('disabled','true');
        $('cmd_reset_event').setAttribute('disabled','true');
    }
};

function populate_list() {
    try {

        $('circ').disabled = true; $('ahr').disabled = true; $('pending').disabled = true; $('complete').disabled = true; $('error').disabled = true;

        rows = {};
        list.clear();

        function onResponse(r) {
            var evt = openils.Util.readResponse(r);
            var row_params = {
                'row' : {
                    'my' : {
                        'atev' : evt,
                        'atevdef' : evt.event_def(),
                        'atreact' : evt.event_def().reactor(),
                        'atval' : evt.event_def().validator(),
                        'circ' : evt.target().classname == 'circ' ? evt.target() : null,
                        'ahr' : evt.target().classname == 'ahr' ? evt.target() : null,
                        'acp' : evt.target().classname == 'circ' ? evt.target().target_copy() : evt.target().current_copy()
                    }
                }
            };
            rows[ evt.id() ] = list.append( row_params );

        }

        function onError(r) {
            var evt = openils.Util.readResponse(r);
            alert('error, evt = ' + js2JSON(evt));
            $('circ').disabled = false; $('ahr').disabled = false; $('pending').disabled = false; $('complete').disabled = false; $('error').disabled = false;
        }

        var method = $('circ').checked ? 'FM_ATEV_APROPOS_CIRC' : 'FM_ATEV_APROPOS_AHR';
        if (xul_param('copy_id')) { method += '_VIA_COPY'; }

        var filter = {"event":{"state":"complete"}, "order_by":[{"class":"atev", "field":"run_time", "direction":"desc"}]};

        if ($('pending').checked) { filter.event.state = 'pending'; filter.order_by[0].direction = 'asc'; }
        if ($('error').checked) { filter.event.state = 'error'; }

        fieldmapper.standardRequest(
            [api[method].app, api[method].method ],
            {   async: true,
                params: [ses(), xul_param('copy_id') || xul_param('patron_id'), filter],
                onresponse : onResponse,
                onerror : onError,
                oncomplete : function() {
                    $('circ').disabled = false; $('ahr').disabled = false; $('pending').disabled = false; $('complete').disabled = false; $('error').disabled = false;
                }
            }
        );

    } catch(E) {
        var err_prefix = 'trigger_events.js -> populate_list() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}
