
if(!dojo._hasResource['openils.widget.PCrudFilterDialog']) {
    dojo.provide('openils.widget.PCrudFilterDialog');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('dijit.form.FilteringSelect');
    dojo.require('dijit.form.Button');
    dojo.require('dojo.data.ItemFileReadStore');
    dojo.require('dijit.Dialog');
    dojo.require('openils.Util');

    /**
     * Given a fieldmapper object, this builds a pop-up dialog used for editing the object
     */

    dojo.declare(
        'openils.widget.PCrudFilterDialog',
        [dijit.Dialog, openils.widget.AutoWidget],
        {

            constructor : function(args) {
                for(var k in args)
                    this[k] = args[k];
                this.widgetIndex = 0;
                this.widgetCache = {};
            },

            /**
             * Builds a basic table of key / value pairs.  Keys are IDL display labels.
             * Values are dijit's, when values set
             */
            startup : function() {
                var self = this;
                this.inherited(arguments);
                this.initAutoEnv();
                var realFieldList = this.sortedFieldList.filter(
                    function(item) { return !item.virtual; });
                this.fieldStore = new dojo.data.ItemFileReadStore({
                    data : {
                        identifier : 'name',
                        name : 'label',
                        items : realFieldList.map(
                            function(item) {
                                return {label:item.label, name:item.name};
                            }
                        )
                    }
                });
                
                // TODO i18n/CSS
                dojo.place(
                    dojo.create(
                        'div', 
                        {innerHTML:'Filter Selector', style:'text-align:center;width:100%;padding:10px;'}
                    ), this.domNode);

                dojo.place(
                    new dijit.form.Button({
                        label:"Apply",
                        onClick : function() {
                            if(self.onApply)
                                self.onApply(self.compileFilter());
                            self.hide();
                        }
                    }).domNode, this.domNode);

                dojo.place(
                    new dijit.form.Button({
                        label:"Cancel",
                        onClick : function() {
                            if(self.onCancel)
                                self.onCancel();
                            self.hide();
                        }
                    }).domNode, this.domNode);

                this.table = dojo.place(dojo.create('table'), this.domNode);
                openils.Util.addCSSClass(this.table, 'oils-fm-edit-dialog');
                this.insertFieldSelector();
            },

            insertFieldSelector : function() {
                var selector = new dijit.form.FilteringSelect({labelAttr:'label', store:this.fieldStore});
                var row = dojo.place(dojo.create('tr'), this.table);
                var selectorTd = dojo.place(dojo.create('td'), row);
                var valueTd = dojo.place(dojo.create('td'), row);
                dojo.place(selector.domNode, selectorTd);

                // dummy text box
                dojo.place(new dijit.form.TextBox().domNode, valueTd);

                // when a field is selected, update the value widget
                var self = this;
                dojo.connect(selector, 'onChange',
                    function(value) {

                        if(valueTd.childNodes[0]) 
                            valueTd.removeChild(valueTd.childNodes[0]);

                        var widget = new openils.widget.AutoFieldWidget({
                            fmClass : self.fmClass, 
                            fmField : value,
                            parentNode : dojo.place(dojo.create('div'), valueTd)
                        });
                        widget.build();

                        if(self.widgetCache[selector.widgetIndex]) {
                            self.widgetCache[selector.widgetIndex].widget.destroy();
                            delete self.widgetCache[selector.widgetIndex];
                        }

                        selector.widgetIndex = this.widgetIndex;
                        self.widgetCache[self.widgetIndex++] = widget;
                    }
                );
            },

            compileFilter : function() {
                var filter = {};
                for(var i in this.widgetCache) {
                    var widget = this.widgetCache[i];
                    filter[widget.fmField] = widget.getFormattedValue();
                }
                return filter;
            }
        }
    );
}

