dump('entering serial/siss_editor.js\n');
// vim:noet:sw=4:ts=4:

JSAN.use('serial.editor_base');

if (typeof serial == 'undefined') serial = {};
serial.siss_editor = function (params) {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
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
    'can_have_notes' : true,

    'init' : function (params) {
        var obj = this;
        
        params.retrieve_function = 'FM_SISS_FLESHED_BATCH_RETRIEVE.authoritative';

        obj.editor_base_init(params);

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
        if (field == 'date_published') {
            if (value == '') { value = null; }
        }
        obj.editor_base_apply(field, value);
    },

    /******************************************************************************************************/
    /* Initialize the panes */

    'init_panes' : function () {
        var obj = this;
        obj.panes_and_field_names = {

    /* These get shown in the left panel */
            'siss_editor_left_pane' :
        [
            [
                $('catStrings').getString('staff.cat.copy_editor.field.creation_date.label') + ' ', //adding extra spaces to satisfy summarize uniqueness requirements
                {
                    render: 'fm.create_date() == null ? "<Unset>" : util.date.formatted_date( fm.create_date(), "%F");',
                }
            ],
            [
                $('catStrings').getString('staff.cat.copy_editor.field.creator.label') + ' ',
                {
                    render: 'fm.creator().usrname() == null ? "<Unset>" : fm.creator().usrname();',
                }
            ],
            [
                $('catStrings').getString('staff.cat.copy_editor.field.last_edit_date.label') + ' ',
                {
                    render: 'fm.edit_date() == null ? "<Unset>" : util.date.formatted_date( fm.edit_date(), "%F");',
                }
            ],
            [
                $('catStrings').getString('staff.cat.copy_editor.field.last_editor.label') + ' ',
                {
                    render: 'fm.editor().usrname() == null ? "<Unset>" : fm.editor().usrname();',
                }
            ],
        ],

        'siss_editor_middle_pane' :
        [
/*rjs7 don't think we need these anymore            [
                'Holding Type',
                {
                    render: 'fm.holding_type();',
                    input: 'c = function(v){ obj.apply("holding_type",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ ["basic", "basic"], ["index", "index"], ["supplement", "supplement"] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                }
            ],
            [
                'Holding Link ID',
                {
                    render: 'fm.holding_link_id();',
                    input: 'c = function(v){ obj.apply("holding_link_id",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.holding_link_id); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'holding_link_id'
                }
            ],*/
            [
                'Holding Code',
                {
                    render: 'fm.holding_code();',
                    input: 'c = function(v){ obj.apply("holding_code",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.holding_code); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'holding_code'
                }
            ],
            [
                'Caption/Pattern', //TODO: make this a drop-down selector, perhaps?
                {
                    render: 'fm.caption_and_pattern();',
                    input: 'c = function(v){ obj.apply("caption_and_pattern",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.caption_and_pattern); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'caption_and_pattern'
                }
            ],
        ],

        'siss_editor_right_pane' :
        [
            [
                'Date Published',
                {
                    render: 'fm.date_published() == null ? "" : util.date.formatted_date( fm.date_published(), "%F");',
                    input: 'c = function(v){ obj.apply("date_published",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.date_published); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'date_published'
                }
            ],
            [
                'Issuance Label',
                {
                    render: 'fm.label() == null ? "" : fm.label();',
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
            'Issuance Notes','chrome,resizable,modal',
            { 'object_id' : obj.sisses[0].id(), 'function_type' : 'SISSN', 'object_type' : 'issuance', 'constructor' : sissn }
        );
    },

    /******************************************************************************************************/
    'save_attributes' : serial.editor_base.editor_base_save_attributes
};

dump('exiting serial/siss_editor.js\n');
