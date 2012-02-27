dump('entering serial/siss_editor.js\n');
// vim:noet:sw=4:ts=4:

JSAN.use('serial.editor_base');

if (typeof serial == 'undefined') serial = {};
serial.siss_editor = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
        JSAN.use('util.network'); this.network = new util.network();
    } catch(E) {
        dump('serial/siss_editor: ' + E + '\n');
    }

    /* This keeps track of what fields have been edited for styling purposes */
    this.changed = {};

    /* This holds the original values for prepopulating the field editors */
    this.editor_values = {};
};

serial.siss_editor.prototype = {
    // we could do this with non-standard '__proto__' property instead
    'editor_base_init' : serial.editor_base.editor_base_init,
    'editor_base_apply' : serial.editor_base.editor_base_apply,
    'editor_base_save' : serial.editor_base.editor_base_save,

    'fm_type' : 'siss',
    'fm_type_plural' : 'sisses',
    'can_have_notes' : false, // XXX no notes table exists yet, but it might make sense

    'init' : function (params) {
        var obj = this;
        
        params.retrieve_function = 'FM_SISS_FLESHED_BATCH_RETRIEVE.authoritative';

        obj.editor_base_init(params);

        obj.multi_ssub_edit = false;
        var ssub = obj.sisses[0].subscription();
        for (var i = 1; i < obj.sisses.length; i++) {
            if (obj.sisses[i].subscription() != ssub) {
                obj.multi_ssub_edit = true;
                break;
            }
        }

        /* Do it */
        obj.summarize( obj.sisses );
        obj.render();
    },

    /******************************************************************************************************/
    /* Restore backup copies */

    'reset' : serial.editor_base.editor_base_reset,

    /******************************************************************************************************/
    /* Apply a value to a specific field on all the copies being edited */

    'apply' : function(field,value) {
        var obj = this;
        if (field == 'date_published' || field == 'caption_and_pattern') {
            if (value == '') { value = null; }
        }
        obj.editor_base_apply(field, value);
    },

    /******************************************************************************************************/
    /* Initialize the panes */

    'render_scap' : function(scap) {
        var obj = this;
        var id;
        if (scap == null) { // true for both 'null' AND undefined
            return "";
        } else if (typeof scap != 'object') {
            id = scap;
        } else {
            id = scap.id()
        }
        return $('serialStrings').getFormattedString('serial.manage_subs.scap_id', [id]);
    },

    'init_panes' : function () {
        var obj = this;
        obj.panes_and_field_names = {

    /* These get shown in the left panel */
            'siss_editor_left_pane' :
        [
            [
                'create_date',
                {
                    render: 'fm.create_date() == null ? "" : util.date.formatted_date( fm.create_date(), "%F");',
                }
            ],
            [
                'creator',
                {
                    render: 'fm.creator().usrname() == null ? "" : fm.creator().usrname();',
                }
            ],
            [
                'edit_date',
                {
                    render: 'fm.edit_date() == null ? "" : util.date.formatted_date( fm.edit_date(), "%F");',
                }
            ],
            [
                'editor',
                {
                    render: 'fm.editor().usrname() == null ? "" : fm.editor().usrname();',
                }
            ],
        ],

        'siss_editor_middle_pane' :
        [
            [
                'holding_type',
                {
                    input: 'c = function(v){ obj.apply("holding_type",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ ["basic", "basic"], ["index", "index"], ["supplement", "supplement"] ] ); x.setAttribute("value",obj.editor_values.holding_type); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'holding_type',
                    required: true
                }
            ],
/* deprecated            [
                'Holding Link ID',
                {
                    render: 'fm.holding_link_id();',
                    input: 'c = function(v){ obj.apply("holding_link_id",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.holding_link_id); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'holding_link_id'
                }
            ],*/
            [
                'holding_code',
                {
                    input: 'c = function(v){ obj.apply("holding_code",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("multiline",true); x.setAttribute("cols",40); x.setAttribute("value",obj.editor_values.holding_code); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'holding_code'
                }
            ],
            [
                'caption_and_pattern',
                {
                    render: 'obj.render_scap(fm.caption_and_pattern());',
                    input: 'if(!obj.multi_ssub_edit) { c = function(v){ obj.apply("caption_and_pattern",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.get_scap_list(), function(obj2) { return [ obj.render_scap(obj2.id()), obj2.id() ]; }).sort()); x.setAttribute("value",obj.editor_values.caption_and_pattern); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false); }',
                    value_key: 'caption_and_pattern',
                    dropdown_key: 'fm.caption_and_pattern() == null ? null : typeof fm.caption_and_pattern() == "object" ? fm.caption_and_pattern().id() : fm.caption_and_pattern()'
                }
            ]
        ],

        'siss_editor_right_pane' :
        [
            [
                'date_published',
                {
                    render: 'fm.date_published() == null ? "" : util.date.formatted_date( fm.date_published(), "%F");',
                    input: 'c = function(v){ obj.apply("date_published",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.date_published); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'date_published'
                }
            ],
            [
                'label',
                {
                    input: 'c = function(v){ obj.apply("label",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.label); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'label'
                }
            ],
        ],

        };
    },

    /******************************************************************************************************/
    /* This loops through all our fieldnames and all the copies, tallying up counts for the different values */

    'summarize' : serial.editor_base.editor_base_summarize,

    /******************************************************************************************************/
    /* Display the summarized data and inputs for editing */

    'render' : serial.editor_base.editor_base_render,

    /******************************************************************************************************/
    /* This actually draws the change button and input widget for a given field */
    'render_input' : serial.editor_base.editor_base_render_input,

    /******************************************************************************************************/
    /* update the issuances */

    'save' : function() {
        var obj = this;
        obj.editor_base_save('open-ils.serial.issuance.fleshed.batch.update');
    },

    /******************************************************************************************************/
    /* spawn issuance notes interface */

    'notes' : function() {
        var obj = this;
        JSAN.use('util.window'); var win = new util.window();
        win.open(
            urls.XUL_SERIAL_NOTES, 
            $('serialStrings').getString('staff.serial.siss_editor.notes'),'chrome,resizable,modal',
            { 'object_id' : obj.sisses[0].id(), 'function_type' : 'SISSN', 'object_type' : 'issuance', 'constructor' : sissn }
        );
    },

    /******************************************************************************************************/
    'save_attributes' : serial.editor_base.editor_base_save_attributes,

    /******************************************************************************************************/
    /* This returns a list of scaps appropriate for the issuances being edited */
    'get_scap_list' : function() {
        var obj = this;
        try {
            /* we will only show this list if dealing with one subscription, default to first siss*/
            var ssub_id = typeof obj.sisses[0].subscription() == 'object' ? obj.sisses[0].subscription().id() : obj.sisses[0].subscription();

            var scap_list = obj.network.request(
                'open-ils.pcrud',
                'open-ils.pcrud.search.scap',
                [ ses(), {"subscription" : ssub_id }, {"order_by" : {"scap" : "id"} } ]
            );

            if (scap_list == null) {
                return [];
            } else if (!scap_list.length) {
                scap_list = [scap_list];
            }

            return scap_list;
        } catch(E) {
            obj.error.standard_unexpected_error_alert('get_scap_list',E);
            return [];
        }
    }
};

dump('exiting serial/siss_editor.js\n');
