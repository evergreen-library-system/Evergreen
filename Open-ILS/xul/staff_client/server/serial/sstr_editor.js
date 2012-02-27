dump('entering serial/sstr_editor.js\n');
// vim:noet:sw=4:ts=4:

JSAN.use('serial.editor_base');

if (typeof serial == 'undefined') serial = {};
serial.sstr_editor = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
        JSAN.use('util.network'); this.network = new util.network();
    } catch(E) {
        dump('serial/sstr_editor: ' + E + '\n');
    }

    /* This keeps track of what fields have been edited for styling purposes */
    this.changed = {};

    /* This holds the original values for prepopulating the field editors */
    this.editor_values = {};

};

serial.sstr_editor.prototype = {
    // we could do this with non-standard '__proto__' property instead
    'editor_base_init' : serial.editor_base.editor_base_init,
    'editor_base_apply' : serial.editor_base.editor_base_apply,
    'editor_base_save' : serial.editor_base.editor_base_save,

    'fm_type' : 'sstr',
    'fm_type_plural' : 'sstrs',

    'init' : function (params) {
        var obj = this;

        params.retrieve_function = 'FM_SSTR_BATCH_RETRIEVE.authoritative';

        obj.editor_base_init(params);

        /* Do it */
        obj.summarize( obj.sstrs );
        obj.render();
    },

    /******************************************************************************************************/
    /* Restore backup copies */

    'reset' :  serial.editor_base.editor_base_reset,

    /******************************************************************************************************/
    /* Apply a value to a specific field on all the copies being edited */

    'apply' : function(field,value) {
        var obj = this;

        obj.editor_base_apply(field, value);
    },

    /******************************************************************************************************/

    'init_panes' : function () {
        var obj = this;
        obj.panes_and_field_names = {

        /* These get shown in the left panel */
        'sstr_editor_left_pane' :
        [
            [
                'id',
                { 
                    //render: 'fm.id() == null ? "" : fm.id();',
                    //input: 'c = function(v){ obj.apply("distribution",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

                }
            ],
            [
                'routing_label',
                { 
                    //render: 'fm.routing_label() == null ? "" : fm.routing_label();',
                    input: 'c = function(v){ obj.apply("routing_label",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.routing_label); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'routing_label'
                }
            ]
        ]

        };
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
    /* save the streams */

    'save' : function() {
        var obj = this;
        obj.editor_base_save('open-ils.serial.stream.batch.update');
    },

    /******************************************************************************************************/
    'save_attributes' : serial.editor_base.editor_base_save_attributes
};

dump('exiting serial/sstr_editor.js\n');
