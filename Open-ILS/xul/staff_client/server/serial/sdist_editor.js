dump('entering serial/sdist_editor.js\n');
// vim:noet:sw=4:ts=4:

JSAN.use('serial.editor_base');

if (typeof serial == 'undefined') serial = {};
serial.sdist_editor = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
        JSAN.use('util.network'); this.network = new util.network();
    } catch(E) {
        dump('serial/sdist_editor: ' + E + '\n');
    }

    /* This keeps track of what fields have been edited for styling purposes */
    this.changed = {};

    /* This holds the original values for prepopulating the field editors */
    this.editor_values = {};

    // setup sre arrays
    this.sre_id_map = {};
    this.sres_ou_map = {};
    this.build_sre_maps();

    // update sre maps on demand
    var obj = this;
    window.parent.addEventListener("MFHDChange", function() {obj.build_sre_maps()}, false);
};

serial.sdist_editor.prototype = {
    // we could do this with non-standard '__proto__' property instead
    'editor_base_init' : serial.editor_base.editor_base_init,
    'editor_base_apply' : serial.editor_base.editor_base_apply,
    'editor_base_save' : serial.editor_base.editor_base_save,

    'fm_type' : 'sdist',
    'fm_type_plural' : 'sdists',
    'can_have_notes' : true,

    'init' : function (params) {
        var obj = this;

        params.retrieve_function = 'FM_SDIST_FLESHED_BATCH_RETRIEVE.authoritative';

        obj.editor_base_init(params);

        obj.multi_org_edit = false;
        var org_unit = obj.sdists[0].holding_lib();
        for (var i = 1; i < obj.sdists.length; i++) {
            if (obj.sdists[i].holding_lib() != org_unit) {
                obj.multi_org_edit = true;
                break;
            }
        }        

        /* Do it */
        obj.summarize( obj.sdists );
        obj.render();
    },

    /******************************************************************************************************/
    /* Restore backup copies */

    'reset' :  serial.editor_base.editor_base_reset,

    /******************************************************************************************************/
    /* Apply a value to a specific field on all the copies being edited */

    'apply' : function(field,value) {
        var obj = this;

        var field_name_list = ['bind_call_number','receive_call_number','bind_unit_template','receive_unit_template','record_entry'];

        // null out call number if the holding lib is changed
        obj.holding_lib_changed = (field == 'holding_lib');
        var loop_func = function(sdist) {
            if (obj.holding_lib_changed) {
                for (var i = 0; i < field_name_list.length; i++) {
                    sdist[field_name_list[i]](null);
                    obj.changed[fieldmapper.IDL.fmclasses.sdist.field_map[field_name_list[i]].label] = true;
                }
            }
        }

        // check for blank drop-down submits
        for (var i = 0; i < field_name_list.length; i++) {
            if (field == field_name_list[i] && value === '') {
                value = null;
                break;
            }
        }
        obj.editor_base_apply(field, value, loop_func);
        obj.holding_lib_changed = false;
    },

    /******************************************************************************************************/

    'render_call_number' : function(cn) {
        var obj = this;
        if (cn == null) { // true for both 'null' AND undefined
            return '';
        } else if (typeof cn != 'object') {
            return obj.acn_label_map[cn];
        } else {
            return cn.label()
        }
    },

    'render_unit_template' : function(ut) {
        var obj = this;
        if (ut == null) { // true for both 'null' AND undefined
            return '';
        } else if (typeof ut != 'object') {
            return obj.act_name_map[ut];
        } else {
            return ut.name()
        }
    },

    'render_record_entry' : function(sre) {
        var obj = this;
        var sre_id;
        if (sre == null) { // true for both 'null' AND undefined
            return '';
        } else if (typeof sre != 'object') {
            sre_id = sre;
        } else {
            sre_id = sre.id();
        }
        return obj.sre_id_map[sre_id].label;
    },

    'init_panes' : function () {
        var obj = this;
        obj.panes_and_field_names = {

        /* These get shown in the left panel */
        '_editor_left_pane' :
        [
            [
                'id',
                { 
                    //input: 'c = function(v){ obj.apply("distribution",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

                }
            ],
            [
                'label',
                { 
                    input: 'c = function(v){ obj.apply("label",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.label); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'label',
                    required: true
                }
            ],
            [
                'summary_method',
                {
                    render: 'obj.summary_methods[fm.summary_method()]',
                    input: 'c = function(v){ obj.apply("summary_method",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_object_to_list( obj.summary_methods, function(obj,i) { return [ obj[i], i ]; })); x.setAttribute("value",obj.editor_values.summary_method); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'summary_method',
                    dropdown_key: 'fm.summary_method() == null ? null : fm.summary_method()'
                }
            ],
            [
                'unit_label_prefix',
                {
                    input: 'c = function(v){ obj.apply("unit_label_prefix",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.unit_label_prefix); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'unit_label_prefix'
                }
            ],
            [
                'unit_label_suffix',
                { 
                    input: 'c = function(v){ obj.apply("unit_label_suffix",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.unit_label_suffix); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'unit_label_suffix'
                }
            ],
        ],
        /* These get shown in the right panel */
            '_editor_right_pane' :
        [
            [
                'holding_lib',
                {
                    render: 'typeof fm.holding_lib() == "object" ? fm.holding_lib().shortname() : obj.data.hash.aou[ fm.holding_lib() ].shortname()',
                    input: 'c = function(v){ if (obj.editor_values.holding_lib != v) obj.apply("holding_lib",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.data.list.aou, function(myobj) { var sname = myobj.shortname(); for (i = sname.length; i < 20; i++) sname += " "; return [ myobj.name() ? sname + " " + myobj.name() : myobj.shortname(), myobj.id(), ( ! get_bool( obj.data.hash.aout[ myobj.ou_type() ].can_have_vols() ) ), ( obj.data.hash.aout[ myobj.ou_type() ].depth() * 2), ]; }), obj.data.list.au[0].ws_ou()); x.setAttribute("value",obj.editor_values.holding_lib); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'holding_lib',
                    dropdown_key: 'typeof fm.holding_lib() == "object" ? fm.holding_lib().id() : fm.holding_lib()',
                }
            ],
        ],
        /* These get shown in the right 'library-specific-options' panel */
        '_editor_lso_pane' :
        [
            [
                'record_entry',
                {
                    render: 'obj.render_record_entry(fm.record_entry())',
                    input: 'if(!obj.multi_org_edit) { c = function(v){ obj.apply("record_entry",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.get_sre_details_list(), function(obj) { return [ obj.label, obj.id ]; }).sort()); x.setAttribute("value",obj.editor_values.record_entry); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false); }',
                    value_key: 'record_entry',
                    dropdown_key: 'fm.record_entry() == null ? null : typeof fm.record_entry() == "object" ? fm.record_entry().id() : fm.record_entry()'
                }
            ],
            [
                'receive_call_number',
                {
                    render: 'obj.render_call_number(fm.receive_call_number())',
                    input: 'if(!obj.multi_org_edit) { c = function(v){ obj.apply("receive_call_number",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.get_acn_list(), function(obj) { return [ obj.label(), obj.id() ]; }).sort()); x.setAttribute("value",obj.editor_values.receive_call_number); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false); }',
                    value_key: 'receive_call_number',
                    dropdown_key: 'fm.receive_call_number() == null ? null : typeof fm.receive_call_number() == "object" ? fm.receive_call_number().id() : fm.receive_call_number()'
                }
            ],
            [
                'bind_call_number',
                {
                    render: 'obj.render_call_number(fm.bind_call_number())',
                    input: 'if(!obj.multi_org_edit) { c = function(v){ obj.apply("bind_call_number",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.get_acn_list(), function(obj) { return [ obj.label(), obj.id() ]; }).sort()); x.setAttribute("value",obj.editor_values.bind_call_number); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false); }',
                    value_key: 'bind_call_number',
                    dropdown_key: 'fm.bind_call_number() == null ? null : typeof fm.bind_call_number() == "object" ? fm.bind_call_number().id() : fm.bind_call_number()'
                }
            ],
            [
                'receive_unit_template',
                {
                    render: 'obj.render_unit_template(fm.receive_unit_template())',
                    input: 'if(!obj.multi_org_edit) { c = function(v){ obj.apply("receive_unit_template",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.get_act_list(), function(obj) { return [ obj.name(), obj.id() ]; }).sort()); x.setAttribute("value",obj.editor_values.receive_unit_template); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false); }',
                    value_key: 'receive_unit_template',
                    dropdown_key: 'fm.receive_unit_template() == null ? null : typeof fm.receive_unit_template() == "object" ? fm.receive_unit_template().id() : fm.receive_unit_template()'
                }
            ],
            [
                'bind_unit_template',
                {
                    render: 'obj.render_unit_template(fm.bind_unit_template())',
                    input: 'if(!obj.multi_org_edit) { c = function(v){ obj.apply("bind_unit_template",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.get_act_list(), function(obj) { return [ obj.name(), obj.id() ]; }).sort()); x.setAttribute("value",obj.editor_values.bind_unit_template); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false); }',
                    value_key: 'bind_unit_template',
                    dropdown_key: 'fm.bind_unit_template() == null ? null : typeof fm.bind_unit_template() == "object" ? fm.bind_unit_template().id() : fm.bind_unit_template()'
                }
            ],
        ],

        };
        for (i in obj.panes_and_field_names) {
            obj.panes_and_field_names[obj.xul_id_prefix + i] = obj.panes_and_field_names[i];
            delete obj.panes_and_field_names[i];
        }
    },

    /******************************************************************************************************/
    /* This loops through all our fieldnames and all the copies, tallying up counts for the different values */

    'summarize' :  serial.editor_base.editor_base_summarize,

    /******************************************************************************************************/
    /* Display the summarized data and inputs for editing */

    'render' :  serial.editor_base.editor_base_render,

    /******************************************************************************************************/
    /* This actually draws the change button and input widget for a given field */
    'render_input' : serial.editor_base.editor_base_render_input,

    /******************************************************************************************************/
    /* save the distributions */

    'save' : function() {
        var obj = this;
        obj.editor_base_save('open-ils.serial.distribution.fleshed.batch.update');
    },

    /******************************************************************************************************/
    /* spawn notes interface */

    'notes' : function() {
        var obj = this;
        JSAN.use('util.window'); var win = new util.window();
        win.open(
            urls.XUL_SERIAL_NOTES, 
            //+ '?copy_id=' + window.escape(obj.sdists[0].id()),
            $('serialStrings').getString('staff.serial.sdist_editor.notes'),'chrome,resizable,modal',
            { 'object_id' : obj.sdists[0].id(), 'function_type' : 'SDISTN', 'object_type' : 'distribution', 'constructor' : sdistn }
        );
    },

    /******************************************************************************************************/
    'save_attributes' : serial.editor_base.editor_base_save_attributes,

    /******************************************************************************************************/
    /* Build maps of sre details for both display and selection purposes */

    'build_sre_maps' : function() {
        var obj = this;
        try {
            obj.sre_id_map = {};
            obj.sres_ou_map = {};
            var parent_g = window.parent.g;
            if (parent_g.mfhd) {
                var mfhd_details = parent_g.mfhd.details;
                for (var i = 0; i < mfhd_details.length; i++) {
                    var mfhd_detail = {};
                    for (j in mfhd_details[i]) {
                        mfhd_detail[j] = mfhd_details[i][j];
                    }
                    mfhd_detail.label = mfhd_detail.label + ' (' + (mfhd_detail.entryNum + 1) + ')';
                    var sre_id = mfhd_detail.id;
                    var org_unit_id = mfhd_detail.owning_lib;
                    obj.sre_id_map[sre_id] = mfhd_detail;
                    if (!obj.sres_ou_map[org_unit_id]) {
                        obj.sres_ou_map[org_unit_id] = [];
                    }
                    obj.sres_ou_map[org_unit_id].push(mfhd_detail);
                }
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert('build_sre_maps',E);
        }
    },

    /******************************************************************************************************/
    /* This returns a list of sre details appropriate for the distributions being edited */

    'get_sre_details_list' : function() {
        var obj = this;
        try {
            /* we only show this list if dealing with one org_unit, default to first sdist*/
            var lib_id = typeof obj.sdists[0].holding_lib() == 'object' ? obj.sdists[0].holding_lib().id() : obj.sdists[0].holding_lib();
            var sre_details_list = obj.sres_ou_map[lib_id];
            if (sre_details_list == null) {
                return [{'label' : $('serialStrings').getString('staff.serial.sdist_editor.no_mfhd_available.label'), 'id' : ''}];
            } else {
                return sre_details_list;
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert('get_sre_details_list',E);
            return [];
        }
    },

    /******************************************************************************************************/
    /* This returns a list of acn's appropriate for the distributions being edited */

    'get_acn_list' : function() {
        var obj = this;
        try {
            var lib_id = typeof obj.sdists[0].holding_lib() == 'object' ? obj.sdists[0].holding_lib().id() : obj.sdists[0].holding_lib();

            if (!obj.acn_lists) {
                obj.acn_lists = {};
            }

            // return cached version if we have it
            // TODO: clear cache on holding_lib change? (cannot remember how to reproduce this bug)
            if (obj.acn_lists[lib_id]) {
                return obj.acn_lists[lib_id];
            }

            var acn_list = obj.network.request(
                'open-ils.pcrud',
                'open-ils.pcrud.search.acn',
                [ ses(), {"record" : obj.docid, "owning_lib" : lib_id, "deleted" : 'f' }, {"order_by" : {"acn" : "label"} } ]
            );

            if (!acn_list) {
                return [];
            } else if (!acn_list.length) {
                acn_list = [acn_list];
            }

            // build label map
            obj.acn_label_map = {};
            for (i = 0; i < acn_list.length; i++) {
                obj.acn_label_map[acn_list[i].id()] = acn_list[i].label();
            }

            // cache the list
            obj.acn_lists[lib_id] = acn_list;
            return acn_list;

        } catch(E) {
            obj.error.standard_unexpected_error_alert('get_acn_list',E);
            return [];
        }
    },

    /******************************************************************************************************/
    /* This returns a list of asset copy templates appropriate for the distributions being edited */

    'get_act_list' : function() {
        var obj = this;
        try {
            /* we only show this list if dealing with one org_unit, default to first sdist*/
            var lib_id = typeof obj.sdists[0].holding_lib() == 'object' ? obj.sdists[0].holding_lib().id() : obj.sdists[0].holding_lib();

            if (!obj.act_lists) {
                obj.act_lists = {};
            }

            // return cached version if we have it
            if (obj.act_lists[lib_id]) {
                return obj.act_lists[lib_id];
            }
            
            var act_list = obj.network.request(
                'open-ils.pcrud',
                'open-ils.pcrud.search.act',
                [ ses(), {"owning_lib" : lib_id }, {"order_by" : {"act" : "name"} } ]
            );

            if (act_list == null) {
                return [];
            } else if (!act_list.length) {
                act_list = [act_list];
            }

            // build name map
            obj.act_name_map = {};
            for (i = 0; i < act_list.length; i++) {
                obj.act_name_map[act_list[i].id()] = act_list[i].name();
            }

            // cache the list
            obj.act_lists[lib_id] = act_list;
            return act_list;
        } catch(E) {
            obj.error.standard_unexpected_error_alert('get_act_list',E);
            return [];
        }
    },
    /******************************************************************************************************/
    'summary_methods' : {
        "add_to_sre" : $('serialStrings').getString('staff.serial.sdist_editor.add_to_sre.label'),
        "merge_with_sre" : $('serialStrings').getString('staff.serial.sdist_editor.merge_with_sre.label'),
        "use_sre_only" : $('serialStrings').getString('staff.serial.sdist_editor.use_sre_only.label'),
        "use_sdist_only" : $('serialStrings').getString('staff.serial.sdist_editor.use_sdist_only.label'),
    }
};

dump('exiting serial/sdist_editor.js\n');
