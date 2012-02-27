dump('entering serial/manage_subs.js\n');
// vim:et:sw=4:ts=4:

if (typeof serial == 'undefined') serial = {};
serial.manage_subs = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
    } catch(E) {
        dump('serial/manage_subs: ' + E + '\n');
    }
};

serial.manage_subs.prototype = {

    'map_tree' : {},
    'map_ssub' : {},
    'map_sdist' : {},
    'map_siss' : {},
    'map_scap' : {},
    'sel_list' : [],
    'funcs' : [],
    'editor_indexes' : { 'ssub' : 1, 'sdist' : 2, 'siss' : 3, 'scap' : 4 },

    'ids_from_sel_list' : function(type) {
        var obj = this;
        JSAN.use('util.functional');

        var list = util.functional.map_list(
            util.functional.filter_list(
                obj.sel_list,
                function (o) {
                    return o.split(/_/)[0] == type;
                }
            ),
            function (o) {
                return o.split(/_/)[1];
            }
        );

        return list;
    },

    'editor_init' : function(type, mode, params) {
        var obj = this;
        try {
            $('serial_manage_subs_editor_deck').selectedIndex = obj.editor_indexes[type];

            if (type == "siss") { // begin transition from xul to dojo editors
                var iframe = dojo.byId('alt_siss_editor');
                var src;
                if (mode == "add") {
                    src = '/eg/serial/edit_siss/new/' + params.sisses[0].subscription();
                    iframe.refresh_command = function () {obj.refresh_list();};
                } else {
                    src = '/eg/serial/edit_siss/' + params.siss_ids[0];
                    iframe.refresh_command = function () { /* TODO: redraw tree node */ };
                }
                iframe.setAttribute("src", src);
            } else {
                var editor_type = type + '_editor';
                if (typeof obj[editor_type] == 'undefined') {
                    JSAN.use('serial.' + editor_type);
                    obj[editor_type] = new serial[editor_type]();
                }

                params.do_edit = true;
                params.handle_update = true;
                params.trigger_refresh = true;
                if (mode == 'add') {
                    params.refresh_command = function () {obj.refresh_list();};
                } else {
                    params.refresh_command = function () {obj.remap_node(type, this);};
                }

                obj[editor_type].init(params);
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert('editor_init() error',E);
        }
    },

    // while not a true tree node repace, this should at least prevent
    // non-display side-effects.  True node replace is TODO
    'remap_node' : function(type, editor_obj) {
        var obj = this;
        try {
            for (i = 0; i < editor_obj[editor_obj.fm_type_plural].length; i++) {
                var new_obj = editor_obj[editor_obj.fm_type_plural][i];
                var old_obj = obj['map_' + type][type + '_' + new_obj.id()];
                if (type == 'ssub') { // add children back on
                    new_obj.distributions(old_obj.distributions());
                    new_obj.issuances(old_obj.issuances());
                    new_obj.scaps(old_obj.scaps());
                }
                obj['map_' + type][type + '_' + new_obj.id()] = new_obj;
            }
            editor_obj.render();
        } catch(E) {
            obj.error.standard_unexpected_error_alert('remap_node() error',E);
        }
    },

    'do_delete' : function(type, method, overridable_events) {
        var obj = this;
        try {
            JSAN.use('util.functional');

            var list = util.functional.filter_list(
                obj.sel_list,
                function (o) {
                    return o.split(/_/)[0] == type;
                }
            );

            list = util.functional.map_list(
                list,
                function (o) {
                    return JSON2js( js2JSON( obj['map_' + type][ type + '_' + o.split(/_/)[1] ] ) );
                }
            );

            //TODO: proper messages
            var delete_msg;
            if (list.length != 1) {
                delete_msg = document.getElementById('serialStrings').getFormattedString('staff.serial.manage_subs.delete_' + type + '.confirm.plural', [list.length]);
            } else {
                delete_msg = document.getElementById('serialStrings').getString('staff.serial.manage_subs.delete_' + type + '.confirm');
            }
            var r = obj.error.yns_alert(
                    delete_msg,
                    document.getElementById('serialStrings').getString('staff.serial.manage_subs.delete_' + type + '.title'),
                    document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.delete'),
                    document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.cancel'),
                    null,
                    document.getElementById('commonStrings').getString('common.confirm')
            );

            if (r == 0) {
                for (var i = 0; i < list.length; i++) {
                    list[i].isdeleted('1');
                }
                var robj = obj.network.request(
                    'open-ils.serial', 
                    method, 
                    [ ses(), list, true ],
                    null,
                    {
                        'title' : document.getElementById('serialStrings').getString('staff.serial.manage_subs.delete_' + type + '.override'),
                        'overridable_events' : overridable_events
                    }
                );
                if (robj == null) throw(robj);
                if (typeof robj.ilsevent != 'undefined') {
                    if (robj.ilsevent != 0) {
                        var overridable = false;
                        for (i = 0; i < overridable_events.length; i++) {
                            if (overridable_events[i] == robj.ilsevent) {
                                overridable = true;
                                break;
                            }
                        }
                        if (!overridable) throw(robj);
                    }
                }
                obj.refresh_list();
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('serialStrings').getString('staff.serial.manage_subs.delete.error'),E);
            obj.refresh_list();
        }
    },

    'init' : function( params ) {

        try {
            var obj = this;

            obj.docid = params.docid;

            JSAN.use('util.network'); obj.network = new util.network();
            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
            JSAN.use('util.controller'); obj.controller = new util.controller();
            obj.controller.init(
                {
                    control_map : {
                        'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
                        'sel_clip' : [
                            ['command'],
                            function() { obj.list.clipboard(); }
                        ],
                        'cmd_broken' : [
                            ['command'],
                            function() { 
                                alert(document.getElementById('commonStrings').getString('common.unimplemented'));
                            }
                        ],
                        'cmd_show_my_libs' : [
                            ['command'],
                            function() { 
                                obj.show_my_libs(); 
                            }
                        ],
                        'cmd_show_all_libs' : [
                            ['command'],
                            function() {
                                obj.show_all_libs();
                            }
                        ],
                        'cmd_clear' : [
                            ['command'],
                            function() {
                                obj.map_tree = {};
                                obj.list.clear();
                            }
                        ],
                        'cmd_add_scap' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('ssub');
                                    if (list.length == 0) list = obj.ids_from_sel_list('scap-group');
                                    if (list.length == 0) return;

                                    /*TODO: permission check?
                                    //populate 'list' with owning_libs of subs, TODO
                                    var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }

                                    if (edit==0) return; // no read-only view for this interface */
                                    var new_scap = new scap();
                                    new_scap.subscription(list[0]);//TODO: add multiple at once support?
                                    new_scap.isnew(1);
                                    var params = {};
                                    params.scaps = [new_scap];
                                    obj.editor_init('scap', 'add', params);
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('serialStrings').getString('staff.serial.manage_subs.add.error'),E);
                                }
                            }
                        ],
                        'cmd_add_siss' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('ssub');
                                    if (list.length == 0) list = obj.ids_from_sel_list('siss-group');
                                    if (list.length == 0) return;

                                    /*TODO: permission check?
                                    //populate 'list' with owning_libs of subs, TODO
                                    var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }

                                    if (edit==0) return; // no read-only view for this interface */
                                    var new_siss = new siss();
                                    new_siss.subscription(list[0]);//TODO: add multiple at once support?
                                    new_siss.isnew(1);
                                    var params = {};
                                    params.sisses = [new_siss];
                                    obj.editor_init('siss', 'add', params);
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('serialStrings').getString('staff.serial.manage_subs.add.error'),E);
                                }
                            }
                        ],
                        'cmd_add_sdist' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('ssub');
                                    if (list.length == 0) list = obj.ids_from_sel_list('sdist-group');
                                    if (list.length == 0) return;

                                    /*TODO: permission check?
                                    //populate 'list' with owning_libs of subs, TODO
                                    var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }

                                    if (edit==0) return; // no read-only view for this interface */
                                    var new_sdist = new sdist();
                                    new_sdist.subscription(list[0]);//TODO: add multiple at once support?
                                    new_sdist.holding_lib(obj.map_ssub['ssub_' + list[0]].owning_lib());//default to sub owning lib
                                    new_sdist.label($('serialStrings').getString('serial.common.default'));
                                    new_sdist.isnew(1);
                                    var params = {};
                                    params.sdists = [new_sdist];
                                    obj.editor_init('sdist', 'add', params);
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('serialStrings').getString('staff.serial.manage_subs.add.error'),E);
                                }
                            }
                        ],
                        'cmd_delete_scap' : [
                            ['command'],
                            function() {
                                var overridable_events = [
                                    11001 // SERIAL_CAPTION_AND_PATTERN_HAS_ISSUANCES
                                ];
                                obj.do_delete('scap', 'open-ils.serial.caption_and_pattern.batch.update', overridable_events);
                            }
                        ],
                        'cmd_delete_sdist' : [
                            ['command'],
                            function() {
                                var overridable_events = [ //TODO: proper overrides
                                ];
                                obj.do_delete('sdist', 'open-ils.serial.distribution.fleshed.batch.update', overridable_events);
                            }
                        ],
                        'cmd_delete_siss' : [
                            ['command'],
                            function() {
                                var overridable_events = [ //TODO: proper overrides
                                ];
                                obj.do_delete('siss', 'open-ils.serial.issuance.fleshed.batch.update', overridable_events);
                            }
                        ],
                        'cmd_delete_ssub' : [
                            ['command'],
                            function() {
                                var overridable_events = [
                                    11000 // SERIAL_SUBSCRIPTION_NOT_EMPTY
                                ];
                                obj.do_delete('ssub', 'open-ils.serial.subscription.fleshed.batch.update', overridable_events);
                            }
                        ],
                        /*dbw2 'cmd_delete_ssub' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'ssub';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return JSON2js( js2JSON( obj.map_ssub[ 'ssub_' + o.split(/_/)[1] ] ) );
                                        }
                                    );

                                    var del_prompt;
                                    if (list.length == 1) {
                                        //TODO: correct prompts
                                        del_prompt = document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.prompt');
                                    } else {
                                        del_prompt = document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.delete_volume.prompt.plural', [list.length]);
                                    }

                                    var r = obj.error.yns_alert(
                                            del_prompt,
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.title'),
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.delete'),
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.cancel'),
                                            null,
                                            document.getElementById('commonStrings').getString('common.confirm')
                                    );

                                    if (r == 0) {
                                        for (var i = 0; i < list.length; i++) {
                                            list[i].isdeleted('1');
                                        }
                                        var robj = obj.network.simple_request(
                                            'FM_ACN_TREE_UPDATE', 
                                            [ ses(), list, true ],
                                            null,
                                            {
                                                'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.override'),
                                                'overridable_events' : [
                                                ]
                                            }
                                        );
                                        if (robj == null) throw(robj);
                                        if (typeof robj.ilsevent != 'undefined') {
                                            if (robj.ilsevent == 1206 ) { // VOLUME_NOT_EMPTY
                                                alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.copies_remain'));
                                                return;
                                            }
                                            if (robj.ilsevent != 0) throw(robj);
                                        }
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.success'));
                                        obj.refresh_list();
                                    }
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.exception'),E);
                                    obj.refresh_list();
                                }

                            }
                        ], dbw2*/
                        'cmd_mark_library' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('aou');
                                    if (list.length == 1) {
                                        obj.data.marked_library = { 'lib' : list[0], 'docid' : obj.docid };
                                        obj.data.stash('marked_library');
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_library.alert'));
                                    } else {
                                        obj.error.yns_alert(
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_library.prompt'),
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_library.title'),
                                                document.getElementById('commonStrings').getString('common.ok'),
                                                null,
                                                null,
                                                document.getElementById('commonStrings').getString('common.confirm')
                                                );
                                    }
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert('manage_subs.js -> mark library',E);
                                }
                            }
                        ],

                        'cmd_mark_subscription' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('ssub');
                                    if (list.length == 1) {
                                        obj.data.marked_subscription = list[0];
                                        obj.data.stash('marked_subscription');
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_volume.alert'));
                                    } else {
                                        obj.error.yns_alert(
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_volume.prompt'),
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_volume.title'),
                                                document.getElementById('commonStrings').getString('common.ok'),
                                                null,
                                                null,
                                                document.getElementById('commonStrings').getString('common.confirm')
                                                );
                                    }
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert('manage_subs.js -> mark subscription',E);
                                }
                            }
                        ],
                        'cmd_add_subscriptions' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('aou');
                                    if (list.length == 0) return;
                                    //TODO: permission check?
                                    /*var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_VOLUME', 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }

                                    if (edit==0) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.add_volume.permission_error'));
                                        return; // no read-only view for this interface
                                    } */
                                    var new_ssub = new ssub();
                                    new_ssub.owning_lib(list[0]);//TODO: add multiple at once support?
                                    new_ssub.isnew(1);
                                    new_ssub.record_entry(obj.docid);
                                    var params = {};
                                    params.ssubs = [new_ssub];
                                    obj.editor_init('ssub', 'add', params);
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('serialStrings').getString('staff.serial.manage_subs.add.error'),E);
                                }
                            }
                        ],
                        'cmd_transfer_subscription' : [
                            ['command'],
                            function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_library) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_volume.alert'));
                                        return;
                                    }
                                    
                                    var list = obj.ids_from_sel_list('ssub');

                                    JSAN.use('util.functional');

                                    var ssub_list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return obj.map_ssub[ 'ssub_' + o ].start_date();
                                        }
                                    ).join(document.getElementById('commonStrings').getString('common.grouping_string'));

                                    var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
                                    xml += '<description>';
                                    xml += document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.transfer.prompt', [ssub_list, obj.data.hash.aou[ obj.data.marked_library.lib ].shortname()]);
                                    xml += '</description>';
                                    xml += '<hbox><button label="' + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.submit.label') + '" name="fancy_submit"/>';
                                    xml += '<button label="' 
                                        + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.cancel.label') 
                                        + '" accesskey="' 
                                        + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.cancel.accesskey') 
                                        + '" name="fancy_cancel"/></hbox>';
                                    xml += '<iframe style="overflow: scroll" flex="1" src="' + urls.XUL_BIB_BRIEF + '?docid=' + obj.data.marked_library.docid + '" oils_force_external="true"/>';
                                    xml += '</vbox>';
                                    JSAN.use('OpenILS.data');
                                    var data = new OpenILS.data(); data.init({'via':'stash'});
                                    //data.temp_transfer = xml; data.stash('temp_transfer');
                                    JSAN.use('util.window'); var win = new util.window();
                                    var fancy_prompt_data = win.open(
                                        urls.XUL_FANCY_PROMPT,
                                        //+ '?xml_in_stash=temp_transfer'
                                        //+ '&title=' + window.escape('Volume Transfer'),
                                        'fancy_prompt', 'chrome,resizable,modal,width=500,height=300',
                                        {
                                            'xml' : xml,
                                            'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.title')
                                        }
                                    );

                                    if (fancy_prompt_data.fancy_status == 'incomplete') {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.incomplete'));
                                        return;
                                    }

                                    var robj = obj.network.simple_request(
                                        'FM_ACN_TRANSFER', 
                                        [ ses(), { 'docid' : obj.data.marked_library.docid, 'lib' : obj.data.marked_library.lib, 'subscriptions' : list } ],
                                        null,
                                        {
                                            'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.override.failure'),
                                            'overridable_events' : [
                                                1208, // TITLE_LAST_COPY
                                                1219, // COPY_REMOTE_CIRC_LIB
                                            ],
                                        }
                                    );

                                    if (typeof robj.ilsevent != 'undefined') {
                                        if (robj.ilsevent == 1221) { // ORG_CANNOT_HAVE_VOLS
                                            alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.ineligible_destination'));
                                        } else {
                                            throw(robj);
                                        }
                                    } else {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.success'));
                                    }

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.unexpected_error'),E);
                                }
                                obj.refresh_list();
                            }
                        ],

                        'cmd_transfer_sdists' : [
                            ['command'],
                            function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_subscription) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_items.missing_volume'));
                                        return;
                                    }
                                    
                                    JSAN.use('util.functional');

                                    var list = obj.ids_from_sel_list('sdist');
                                    var subscription = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ obj.data.marked_subscription ]);

                                    JSAN.use('cat.util'); cat.util.transfer_copies( { 
                                        'distribution_ids' : list, 
                                        'docid' : subscription.record(),
                                        'subscription_label' : subscription.start_date(),
                                        'owning_lib' : subscription.owning_lib(),
                                    } );

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_items.unexpected_error'),E);
                                }
                                obj.refresh_list();
                            }
                        ],
                        'cmd_refresh_list' : [
                            ['command'],
                            function() {
                                obj.refresh_list();
                            }
                        ],
                        'cmd_make_predictions' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('ssub');
                                    if (list.length == 0) {
                                        alert($('serialStrings').getString('serial.manage_subs.predict.alert')); //TODO: better error
                                        return;
                                    }

                                    var num_to_predict = prompt($('serialStrings').getString('serial.manage_subs.predict.prompt'),
                                            '12',
                                            $('serialStrings').getString('serial.manage_subs.predict.prompt.text'));
                                    num_to_predict = String( num_to_predict ).replace(/\D/g,'');
                                    if (num_to_predict == '') {
                                        alert($('serialStrings').getString('serial.manage_subs.invalid_number')); //TODO: better error
                                        return;
                                    }

                                    for (i = 0; i < list.length; i++) {
                                        var robj = obj.network.request(
                                                'open-ils.serial',
                                                'open-ils.serial.make_predictions',
                                                [ ses(), {"ssub_id":list[i], "num_to_predict":num_to_predict}]
                                        );
                                        alert($('serialStrings').getFormattedString('serial.manage_subs.predict_success', [robj.length, list[i]]));
                                    }

                                    obj.refresh_list();

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert('cmd_make_predictions failed!',E);
                                }
                            }
                        ]
                    }
                }
            );

            obj.list_init(params);

            obj.org_ids = obj.network.simple_request('FM_SSUB_AOU_IDS_RETRIEVE_VIA_RECORD_ID.authoritative',[ obj.docid ]);
            if (typeof obj.org_ids.ilsevent != 'undefined') throw(obj.org_ids);
            JSAN.use('util.functional'); 
            obj.org_ids = util.functional.map_list( obj.org_ids, function (o) { return Number(o); });

            var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
            //obj.show_libs( org );

            //obj.show_my_libs();

            JSAN.use('util.file'); JSAN.use('util.widgets');

            var file; var list_data; var ml; 

            file = new util.file('offline_ou_list'); 
            if (file._file.exists()) {
                list_data = file.get_object(); file.close();
                for (var i = 0; i < list_data[0].length; i++) { // make sure all entries are enabled
                    list_data[0][i][2] = false;
                }
                ml = util.widgets.make_menulist( list_data[0], list_data[1] );
                ml.setAttribute('id','lib_menu'); document.getElementById('serial_sub_lib_menu').appendChild(ml);
                //TODO: class this menu properly
                for (var i = 0; i < obj.org_ids.length; i++) {
                    ml.getElementsByAttribute('value',obj.org_ids[i])[0].setAttribute('class','has_distributions');
                }
                ml.firstChild.addEventListener(
                    'popupshown',
                    function(ev) {
                        document.getElementById('legend').setAttribute('hidden','false');
                    },
                    false
                );
                ml.firstChild.addEventListener(
                    'popuphidden',
                    function(ev) {
                        document.getElementById('legend').setAttribute('hidden','true');
                    },
                    false
                );
                ml.addEventListener(
                    'command',
                    function(ev) {
                        if (document.getElementById('refresh_button')) document.getElementById('refresh_button').focus(); 
                        JSAN.use('util.file'); var file = new util.file('manage_subs_prefs.'+obj.data.server_unadorned);
                        util.widgets.save_attributes(file, { 'lib_menu' : [ 'value' ], 'show_ssubs' : [ 'checked' ], 'show_ssub_groups' : [ 'checked' ] });
                        obj.refresh_list();
                    },
                    false
                );
            } else {
                throw(document.getElementById('catStrings').getString('staff.cat.copy_browser.missing_library') + '\n');
            }

            file = new util.file('manage_subs_prefs.'+obj.data.server_unadorned);
            util.widgets.load_attributes(file);
            ml.value = ml.getAttribute('value');
            if (! ml.value) {
                ml.value = org.id();
                ml.setAttribute('value',ml.value);
            }

            document.getElementById('show_ssubs').addEventListener(
                'command',
                function(ev) {
                    JSAN.use('util.file'); var file = new util.file('manage_subs_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, { 'lib_menu' : [ 'value' ], 'show_ssubs' : [ 'checked' ], 'show_ssub_groups' : [ 'checked' ] });
                },
                false
            );

            document.getElementById('show_ssub_groups').addEventListener(
                'command',
                function(ev) {
                    JSAN.use('util.file'); var file = new util.file('manage_subs_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, { 'lib_menu' : [ 'value' ], 'show_ssubs' : [ 'checked' ], 'show_ssub_groups' : [ 'checked' ] });
                },
                false
            );

            obj.show_my_libs( ml.value );

            JSAN.use('util.exec'); var exec = new util.exec(20); exec.timer(obj.funcs,100);

            obj.toggle_actions(); // disable menus initially

        } catch(E) {
            this.error.standard_unexpected_error_alert('serial/manage_subs.init: ',E);
        }
    },

    'show_my_libs' : function(org) {
        var obj = this;
        try {
            if (!org) {
                org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
            } else {
                if (typeof org != 'object') org = obj.data.hash.aou[ org ];
            }
            obj.show_libs( org, false );
        } catch(E) {
            alert(E);
        }
    },

    'show_libs' : function(start_aou,show_open) {
        var obj = this;
        try {
            if (!start_aou) throw('show_libs: Need a start_aou');
            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
            JSAN.use('util.functional'); 

            var parents = [];
            var temp_aou = start_aou;
            while ( temp_aou.parent_ou() ) {
                temp_aou = obj.data.hash.aou[ temp_aou.parent_ou() ];
                parents.push( temp_aou );
            }
            parents.reverse();

            for (var i = 0; i < parents.length; i++) {
                obj.funcs.push(
                    function(o,p) {
                        return function() { 
                            obj.append_org(o,p,{'container':'true','open':'true'}); 
                        };
                    }(parents[i], obj.data.hash.aou[ parents[i].parent_ou() ])
                );
            }

            obj.funcs.push(
                function(o,p) {
                    return function() { obj.append_org(o,p); };
                }(start_aou,obj.data.hash.aou[ start_aou.parent_ou() ])
            );

            obj.funcs.push(
                function() {
                    if (start_aou.children()) {
                        var x = obj.map_tree[ 'aou_' + start_aou.id() ];
                        x.setAttribute('container','true');
                        if (show_open) x.setAttribute('open','true');
                        for (var i = 0; i < start_aou.children().length; i++) {
                            obj.funcs.push(
                                function(o,p) {
                                    return function() { obj.append_org(o,p); };
                                }( start_aou.children()[i], start_aou )
                            );
                        }
                    }
                }
            );

        } catch(E) {
            alert(E);
        }
    },

    'on_select' : function(list,twisty) {
        var obj = this;
        var sel_lists = {};

        for (var i = 0; i < list.length; i++) {
            var row_type = list[i].split('_')[0];
            var id = list[i].split('_')[1];

            if (!sel_lists[row_type]) sel_lists[row_type] = [];
            sel_lists[row_type].push(id);

            switch(row_type) {
                case 'aou' : obj.on_click_aou(id,twisty); break;
                case 'ssub' : obj.on_select_ssub(id,twisty); break;
                default: break;
            }
        }

        if (!obj.focused_node_retrieve_id) return;

        var row_type = obj.focused_node_retrieve_id.split('_')[0];
        var id = obj.focused_node_retrieve_id.split('_')[1];

        if (sel_lists[row_type]) { // the type focused is in the selection (usually the case)
            switch(row_type) {
                case 'aou' : obj.on_click_aou(id,twisty); break;
                default: if (obj['on_click_' + row_type]) obj['on_click_' + row_type](sel_lists[row_type],twisty);
            }
        }
    },

    'on_select_ssub' : function(ssub_id,twisty) {
        var obj = this;
        try {
            //typo? var ssub_tree = obj.map_sdist[ 'ssub_' + ssub_id ];
            var ssub_tree = obj.map_ssub[ 'ssub_' + ssub_id ];
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
                document.getElementById('lib_menu').setAttribute('disabled','true'); 
            } );
            if (ssub_tree.distributions()) {
                for (var i = 0; i < ssub_tree.distributions().length; i++) {
                    obj.funcs.push(
                        function(c,a) {
                            return function() {
                                obj.append_member(c,a,[],'sdist');
                            }
                        }( ssub_tree.distributions()[i], ssub_tree )
                    )
                }
            }
            if (ssub_tree.issuances()) {
                for (var i = 0; i < ssub_tree.issuances().length; i++) {
                    obj.funcs.push(
                        function(c,a) {
                            return function() {
                                obj.append_member(c,a,[],'siss');
                            }
                        }( ssub_tree.issuances()[i], ssub_tree )
                    )
                }
            }
            if (ssub_tree.scaps()) {
                for (var i = 0; i < ssub_tree.scaps().length; i++) {
                    obj.funcs.push(
                        function(c,a) {
                            return function() {
                                obj.append_member(c,a,[],'scap');
                            }
                        }( ssub_tree.scaps()[i], ssub_tree )
                    )
                }
            }
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
                document.getElementById('lib_menu').setAttribute('disabled','false'); 
            } );
        } catch(E) {
            alert(E);
        }
    },

    'on_click_ssub' : function(ssub_ids,twisty) {
        var obj = this;
        try {
            // draw sdist editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.ssub_ids = ssub_ids;
                obj.editor_init('ssub', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_sdist' : function(sdist_ids,twisty) {
        var obj = this;
        try {
            // draw sdist editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.sdist_ids = sdist_ids;
                obj.editor_init('sdist', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_siss' : function(siss_ids,twisty) {
        var obj = this;
        try {
            // draw siss editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.siss_ids = siss_ids;
                obj.editor_init('siss', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_scap' : function(scap_ids,twisty) {
        var obj = this;
        try {
            // draw scap editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.scap_ids = scap_ids;
                obj.editor_init('scap', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_aou' : function(org_id,twisty) {
        var obj = this;
        var org = obj.data.hash.aou[ org_id ];
        var default_aou = obj.data.hash.aou[obj.default_lib];
        obj.funcs.push( function() { 
            document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
            document.getElementById('lib_menu').setAttribute('disabled','true'); 
        } );
        if (org.children()) {
            for (var i = 0; i < org.children().length; i++) {
                var child = org.children()[i];
                if (orgIsMine(default_aou,child)) {
                    obj.funcs.push(
                        function(o,p) {
                            return function() {
                                obj.append_org(o,p)
                            }
                        }(child,org)
                    );
                }
            }
        } 
        if (obj.map_ssub[ 'aou_' + org_id ]) {
            for (var i = 0; i < obj.map_ssub[ 'aou_' + org_id ].length; i++) {
                obj.funcs.push(
                    function(o,a) {
                        return function() {
                            obj.append_ssub(o,a);
                        }
                    }( org, obj.map_ssub[ 'aou_' + org_id ][i] )
                );
            }
        }
        obj.funcs.push( function() { 
            document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
            document.getElementById('lib_menu').setAttribute('disabled','false'); 
        } );

        // remove current editor
        if (typeof twisty == 'undefined') {
            document.getElementById('serial_manage_subs_editor_deck').selectedIndex = 0;
        }
    },

    'append_org' : function (org,parent_org,params) {
        var obj = this;
        try {
            if (obj.map_tree[ 'aou_' + org.id() ]) {
                var x = obj.map_tree[ 'aou_' + org.id() ];
                if (params) {
                    for (var i in params) {
                        x.setAttribute(i,params[i]);
                    }
                }
                return x;
            }

            var data = {
                'row' : {
                    'my' : {
                        'aou' : org,
                    }
                },
                'skip_all_columns_except' : [0,1,2],
                'retrieve_id' : 'aou_' + org.id(),
                'to_bottom' : true,
                'no_auto_select' : true,
            };
        
            var ssub_tree_list;
            if ( obj.org_ids.indexOf( Number( org.id() ) ) == -1 ) {
                data.row.my.subscription_count = '0';
                //data.row.my.distribution_count = '<0>';
            } else {
                var s_count = 0; //var d_count = 0;
                ssub_tree_list = obj.network.simple_request(
                    'FM_SSUB_TREE_LIST_RETRIEVE_VIA_RECORD_ID_AND_ORG_IDS.authoritative',
                    [ ses(), obj.docid, [ org.id() ] ]
                );
                for (var i = 0; i < ssub_tree_list.length; i++) {
                    s_count++;
                    obj.map_ssub[ 'ssub_' + ssub_tree_list[i].id() ] = function(r){return r;}(ssub_tree_list[i]);
                    var distributions = ssub_tree_list[i].distributions();
                    //if (distributions) d_count += distributions.length;
                    for (var j = 0; j < distributions.length; j++) {
                        obj.map_sdist[ 'sdist_' + distributions[j].id() ] = function(r){return r;}(distributions[j]);
                    }
                    var issuances = ssub_tree_list[i].issuances();
                    for (var j = 0; j < issuances.length; j++) {
                        obj.map_siss[ 'siss_' + issuances[j].id() ] = function(r){return r;}(issuances[j]);
                    }
                    var scaps = ssub_tree_list[i].scaps();
                    for (var j = 0; j < scaps.length; j++) {
                        obj.map_scap[ 'scap_' + scaps[j].id() ] = function(r){return r;}(scaps[j]);
                    }
                }
                data.row.my.subscription_count = s_count;
                //data.row.my.distribution_count = '<' + d_count + '>';
            }
            if (parent_org) {
                data.node = obj.map_tree[ 'aou_' + parent_org.id() ];
            }
            var nparams = obj.list.append(data);
            var node = nparams.treeitem_node;
            if (params) {
                for (var i in params) {
                    node.setAttribute(i,params[i]);
                }
            }
            obj.map_tree[ 'aou_' + org.id() ] = node;

            if (org.children()) {
                node.setAttribute('container','true');
            }

            if (parent_org) {
                if ( obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].parent_ou() == parent_org.id() ) {
                    data.node.setAttribute('open','true');
                    obj.funcs.push( function() { obj.on_click_aou( org.id() ); } );
                }
            } else {
                obj.map_tree[ 'aou_' + org.id() ].setAttribute('open','true');
                obj.funcs.push( function() { obj.on_click_aou( org.id() ); } );
            }

            if (ssub_tree_list) {
                obj.map_ssub[ 'aou_' + org.id() ] = ssub_tree_list;
                node.setAttribute('container','true');
            }

            if (document.getElementById('show_ssubs').checked) {
                obj.funcs.push( function() { obj.on_click_aou( org.id() ); } );
                node.setAttribute('open','true');
            }

        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'append_ssub' : function( org, ssub_tree, params ) {
        var obj = this;
        try {
            if (obj.map_tree[ 'ssub_' + ssub_tree.id() ]) {
                var x = obj.map_tree[ 'ssub_' + ssub_tree.id() ];
                if (params) {
                    for (var i in params) {
                        x.setAttribute(i,params[i]);
                    }
                }
                return x;
            }

            var parent_node = obj.map_tree[ 'aou_' + org.id() ];
            var data = {
                'row' : {
                    'my' : {
                        'aou' : org,
                        'ssub' : ssub_tree,
                        'subscription_count' : '',
                        //'distribution_count' : ssub_tree.distributions() ? ssub_tree.distributions().length : '0',
                    }
                },
                'skip_all_columns_except' : [0,1,2],
                'retrieve_id' : 'ssub_' + ssub_tree.id(),
                'node' : parent_node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            var nparams = obj.list.append(data);
            var node = nparams.treeitem_node;
            obj.map_tree[ 'ssub_' + ssub_tree.id() ] =  node;
            if (params) {
                for (var i in params) {
                    node.setAttribute(i,params[i]);
                }
            }
            if (ssub_tree.distributions() || ssub_tree.scaps() || ssub_tree.issuances()) {
                //did this support a later typo? obj.map_sdist[ 'ssub_' + ssub_tree.id() ] = ssub_tree;
                node.setAttribute('container','true');
            }
            if (document.getElementById('show_ssub_groups').checked) {
                node.setAttribute('open','true');
                obj.funcs.push( function() { obj.on_select_ssub( ssub_tree.id(), true ); } );
            }
            var sdist_group_node_data = {
                'row' : {
                    'my' : {
                        'label' : $('serialStrings').getString('serial.manage_subs.distributions'),
                    }
                },
                'retrieve_id' : 'sdist-group_' + ssub_tree.id(),
                'node' : node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            nparams = obj.list.append(sdist_group_node_data);
            obj.map_tree[ 'ssub_sdist_group_' + ssub_tree.id() ] =  nparams.treeitem_node;

            var siss_group_node_data = {
                'row' : {
                    'my' : {
                        'label' : $('serialStrings').getString('serial.manage_subs.issuances'),
                    }
                },
                'retrieve_id' : 'siss-group_' + ssub_tree.id(),
                'node' : node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            nparams = obj.list.append(siss_group_node_data);
            obj.map_tree[ 'ssub_siss_group_' + ssub_tree.id() ] =  nparams.treeitem_node;

            var scap_group_node_data = {
                'row' : {
                    'my' : {
                        'label' : $('serialStrings').getString('serial.manage_subs.captions_patterns'),
                    }
                },
                'retrieve_id' : 'scap-group_' + ssub_tree.id(),
                'node' : node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            nparams = obj.list.append(scap_group_node_data);
            obj.map_tree[ 'ssub_scap_group_' + ssub_tree.id() ] =  nparams.treeitem_node;
        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'append_member' : function( item, ssub_tree, attributes, type ) {
        var obj = this;
        try {
            if (obj.map_tree[ type + '_' + item.id() ]) {
                var x = obj.map_tree[ type + '_' + item.id() ];
                if (attributes) {
                    for (var i in attributes) {
                        x.setAttribute(i,attributes[i]);
                    }
                }
                return x;
            }

            var parent_node = obj.map_tree[ 'ssub_' + type + '_group_' + ssub_tree.id() ];
            var data = {
                'row' : {
                    'my' : {
                        'aou' : obj.data.hash.aou[ ssub_tree.owning_lib() ],
                        'ssub' : ssub_tree,
                        'subscription_count' : '',
                        //'distribution_count' : '',
                    }
                },
                'retrieve_id' : type + '_' + item.id(),
                'node' : parent_node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            data['row']['my'][type] = item; // TODO: future optimization: get only the IDs of these leaves, then fetch the full row in 'retrieve_row'
            var nparams = obj.list.append(data);
            var node = nparams.treeitem_node;
            obj.map_tree[ type + '_' + item.id() ] =  node;
            if (attributes) {
                for (var i in attributes) {
                    node.setAttribute(i,attributes[i]);
                }
            }

        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'list_init' : function( params ) {

        try {
            var obj = this;
            
            JSAN.use('circ.util');
            var columns = [
                {
                    'id' : 'tree_location',
                    'label' : $('serialStrings').getString('serial.manage_subs.tree_location'),
                    'flex' : 1, 'primary' : true, 'hidden' : false, 
                    'render' : function(my) { 
                        if (my.sdist) { return my.sdist.label(); }
                        if (my.siss) { return my.siss.label(); }
                        if (my.scap) { return $('serialStrings').getFormattedString('serial.manage_subs.scap_id', [my.scap.id()]); }
                        if (my.ssub) { return $('serialStrings').getFormattedString('serial.manage_subs.ssub_id', [my.ssub.id()]); }
                        if (my.aou) { return $('serialStrings').getFormattedString('serial.manage_dists.library_label', [my.aou.shortname(), my.aou.name()]); }
                        if (my.label) { return my.label; }
                        /* If all else fails... */
                        return "???"; 
                    },
                },
                {
                    'id' : 'subscription_count',
                    'label' : $('serialStrings').getString('serial.manage_subs.subscriptions'),
                    'flex' : 0, 'primary' : false, 'hidden' : false, 
                    'render' : function(my) { return my.subscription_count; },
                },
                /*{
                    'id' : 'distribution_count',
                    'label' : 'Members',
                    'flex' : 0,
                    'primary' : false, 'hidden' : false, 
                    'render' : function(my) { return my.distribution_count; },
                },*/
            ];
            JSAN.use('util.list'); obj.list = new util.list('subs_tree');
            obj.list.init(
                {
                    'no_auto_select' : true,
                    'columns' : columns,
                    'retrieve_row' : function(params) {

                        var row = params.row;
                        obj.funcs.push(
                            function() {

                                if (typeof params.on_retrieve == 'function') {
                                    params.on_retrieve(row);
                                }

                            }
                        );

                        return row;
                    },
                    'on_click' : function(ev) {
                        var row = {}; var col = {}; var nobj = {};
                        obj.list.node.treeBoxObject.getCellAt(ev.clientX,ev.clientY,row,col,nobj); 
                        if ((row.value == -1)||(nobj.value != 'twisty')) { return; } // on_click runs for twistys only

                        var node = obj.list.node.contentView.getItemAtIndex(row.value);
                        var list = [ node.getAttribute('retrieve_id') ];
                        if (typeof obj.on_select == 'function') {
                            obj.on_select(list,true);
                        }
                        if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
                            window.xulG.on_select(list);
                        }
                    },
                    'on_select' : function(ev) {
                        JSAN.use('util.functional');
                        
                        // get the actual node clicked to determine which editor to use
                        if (obj.list.node.view.selection.currentIndex > -1) {
                            var node = obj.list.node.contentView.getItemAtIndex(obj.list.node.view.selection.currentIndex);
                            obj.focused_node_retrieve_id = node.getAttribute('retrieve_id');
                        }

                        var sel = obj.list.retrieve_selection();
                        obj.controller.view.sel_clip.disabled = sel.length < 1;
                        obj.sel_list = util.functional.map_list(
                            sel,
                            function(o) { return o.getAttribute('retrieve_id'); }
                        );
                        obj.toggle_actions();
                        if (typeof obj.on_select == 'function') {
                            obj.on_select(obj.sel_list);
                        }
                        if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
                            window.xulG.on_select(obj.sel_list);
                        }
                    },
                }
            );

            obj.controller.render();

        } catch(E) {
            this.error.sdump('D_ERROR','serial/manage_subs.list_init: ' + E + '\n');
            alert(E);
        }
    },

    'toggle_actions' : function() {
        var obj = this;
        try {
            var found_aou = false; var found_ssub = false; var found_sdist = false; var found_siss = false; var found_scap = false; var found_sdist_group = false; var found_siss_group = false; var found_scap_group = false;
            for (var i = 0; i < obj.sel_list.length; i++) {
                var type = obj.sel_list[i].split(/_/)[0];
                switch(type) {
                    case 'aou' : 
                        found_aou = true; 
                    break;
                    case 'ssub' : found_ssub = true; break;
                    case 'sdist' : found_sdist = true; break;
                    case 'siss' : found_siss = true; break;
                    case 'scap' : found_scap = true; break;
                    case 'sdist-group' : found_sdist_group = true; break;
                    case 'siss-group' : found_siss_group = true; break;
                    case 'scap-group' : found_scap_group = true; break;
                }
            }
            obj.controller.view.cmd_add_sdist.setAttribute('disabled','true');
            obj.controller.view.cmd_add_siss.setAttribute('disabled','true');
            obj.controller.view.cmd_add_scap.setAttribute('disabled','true');
            obj.controller.view.cmd_make_predictions.setAttribute('disabled','true');
            obj.controller.view.cmd_delete_sdist.setAttribute('disabled','true');
            obj.controller.view.cmd_delete_siss.setAttribute('disabled','true');
            obj.controller.view.cmd_delete_scap.setAttribute('disabled','true');
            obj.controller.view.cmd_add_subscriptions.setAttribute('disabled','true');
            obj.controller.view.cmd_mark_library.setAttribute('disabled','true');
            obj.controller.view.cmd_delete_ssub.setAttribute('disabled','true');
            obj.controller.view.cmd_mark_subscription.setAttribute('disabled','true');
            obj.controller.view.cmd_transfer_subscription.setAttribute('disabled','true');
            obj.controller.view.cmd_transfer_sdists.setAttribute('disabled','true');
            if (found_aou) {
                obj.controller.view.cmd_add_subscriptions.setAttribute('disabled','false');
                obj.controller.view.cmd_mark_library.setAttribute('disabled','false');
            }
            if (found_ssub) {
                obj.controller.view.cmd_delete_ssub.setAttribute('disabled','false');
                obj.controller.view.cmd_mark_subscription.setAttribute('disabled','false');
                obj.controller.view.cmd_add_sdist.setAttribute('disabled','false');
                obj.controller.view.cmd_add_siss.setAttribute('disabled','false');
                obj.controller.view.cmd_add_scap.setAttribute('disabled','false');
                obj.controller.view.cmd_transfer_subscription.setAttribute('disabled','false');
                obj.controller.view.cmd_make_predictions.setAttribute('disabled','false');
            }
            if (found_sdist_group) {
                obj.controller.view.cmd_add_sdist.setAttribute('disabled','false');
            }
            if (found_siss_group) {
                obj.controller.view.cmd_add_siss.setAttribute('disabled','false');
            }
            if (found_scap_group) {
                obj.controller.view.cmd_add_scap.setAttribute('disabled','false');
            }
            if (found_sdist) {
                obj.controller.view.cmd_delete_sdist.setAttribute('disabled','false');
                obj.controller.view.cmd_transfer_sdists.setAttribute('disabled','false');
            }
            if (found_siss) {
                obj.controller.view.cmd_delete_siss.setAttribute('disabled','false');
            }
            if (found_scap) {
                obj.controller.view.cmd_delete_scap.setAttribute('disabled','false');
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.actions.error'),E);
        }
    },

    'refresh_list' : function() { 
        try {
            var obj = this;
            obj.list.clear();
            obj.map_tree = {};
            obj.map_ssub = {};
            obj.map_sdist = {};
            obj.map_siss = {};
            obj.map_scap = {};
            obj.org_ids = obj.network.simple_request('FM_SSUB_AOU_IDS_RETRIEVE_VIA_RECORD_ID.authoritative',[ obj.docid ]);
            if (typeof obj.org_ids.ilsevent != 'undefined') throw(obj.org_ids);
            JSAN.use('util.functional'); 
            obj.org_ids = util.functional.map_list( obj.org_ids, function (o) { return Number(o); });
            /*
            var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
            obj.show_libs( org );
            */
            obj.default_lib = document.getElementById('lib_menu').value;
            obj.show_my_libs( obj.default_lib );
        } catch(E) {
            this.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.refresh_list.error'),E);
        }
    },
};

dump('exiting serial/manage_subs.js\n');
