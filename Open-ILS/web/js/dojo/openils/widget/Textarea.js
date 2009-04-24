if(!dojo._hasResource['openils.widget.Textarea']) {
    dojo.provide('openils.widget.Textarea');
    dojo.require("dijit.form._FormWidget");

   /**
     * Simple textarea that honors spaces/tabs
     */

    dojo.declare(
        'openils.widget.Textarea', dijit.form._FormValueWidget,
        {
            width : '',
            height : '',
            templateString : '<textarea class="openils-widget-textarea" value="${value}" dojoAttachPoint="formValueNode,editNode,focusNode,styleNode"></textarea>',
            
            constructor : function(args) {
                if(!args) args = {};
                this.width = args.width || openils.widget.Textarea.width;
                this.height = args.height || openils.widget.Textarea.height;
            },
            
            postCreate : function() {
                if(this.width)
                    dojo.style(this.domNode, 'width', this.width);
                if(this.height)
                    dojo.style(this.domNode, 'height', this.height);
            },

            attr : function(name, val) {
                if(name == 'value') {
                    if(val)
                        this.domNode.value = val;
                    return this.domNode.value;
                } else {
                    return this.inherited(arguments);
                }
            }
        }
    );
}

