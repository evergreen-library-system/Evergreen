dump('entering serial/scap_editor.js\n');
// vim:noet:sw=4:ts=4:

JSAN.use('serial.editor_base');

if (typeof serial == 'undefined') serial = {};
serial.scap_editor = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
        JSAN.use('util.network'); this.network = new util.network();
    } catch(E) {
        dump('serial/scap_editor: ' + E + '\n');
    }

    /* This keeps track of what fields have been edited for styling purposes */
    this.changed = {};

    /* This holds the original values for prepopulating the field editors */
    this.editor_values = {};

};

serial.scap_editor.prototype = {
    // we could do this with non-standard '__proto__' property instead
    'editor_base_init' : serial.editor_base.editor_base_init,
    'editor_base_apply' : serial.editor_base.editor_base_apply,
    'editor_base_save' : serial.editor_base.editor_base_save,

    'fm_type' : 'scap',
    'fm_type_plural' : 'scaps',

    'init' : function (params) {
        var obj = this;

        params.retrieve_function = 'FM_SCAP_BATCH_RETRIEVE.authoritative';

        obj.editor_base_init(params);

        /* Do it */
        obj.summarize( obj.scaps );
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
        'scap_editor_left_pane' :
        [
            [
                'id',
                { 
                    //input: 'c = function(v){ obj.apply("distribution",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

                }
            ],
            [
                'create_date',
                {
                    render: 'fm.create_date() == null ? "" : util.date.formatted_date( fm.create_date(), "%F");',
                }
            ],
            [
                'type',
                {
                    input: 'c = function(v){ obj.apply("type",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ ["basic", "basic"], ["index", "index"], ["supplement", "supplement"] ] ); x.setAttribute("value",obj.editor_values.type); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'type',
                    required: true
                }
            ],
            [
                'active',
                {
                    render: 'fm.active() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : ( get_bool( fm.active() ) ? $("catStrings").getString("staff.cat.copy_editor.field.circulate.yes_or_true") : $("catStrings").getString("staff.cat.copy_editor.field.circulate.no_or_false") )',
                    input: 'c = function(v){ obj.apply("active",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.circulate.yes_or_true"), get_db_true() ], [ $("catStrings").getString("staff.cat.copy_editor.field.circulate.no_or_false"), get_db_false() ] ] ); x.setAttribute("value",obj.editor_values.active); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'active',
                    dropdown_key: 'fm.active()'
                }
            ],
            [
                'pattern_code',
                { 
                    input: 'c = function(v){ obj.apply("pattern_code",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("multiline",true); x.setAttribute("cols",40); x.setAttribute("value",obj.editor_values.pattern_code); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'pattern_code',
                    required: true
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
    /* save the caption/patterns */

    'save' : function() {
        var obj = this;
        obj.editor_base_save('open-ils.serial.caption_and_pattern.batch.update');
    },

    /* Pattern/caption wizard */
    "pattern_wizard": function() {
        var obj = this;

        var onsubmit = function(value) {
            obj.apply("pattern_code", value);
            obj.summarize(obj.scaps);
            obj.render();
        };
        window.openDialog(
            xulG.url_prefix("XUL_SERIAL_PATTERN_WIZARD"),
            "pattern_wizard",
            "width=800,height=400",
            onsubmit
        );
    },

    /******************************************************************************************************/
    'save_attributes' : serial.editor_base.editor_base_save_attributes
};

dump('exiting serial/scap_editor.js\n');
