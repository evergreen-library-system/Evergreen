
if(!dojo._hasResource['openils.widget.PCrudFilterDialog']) {
    dojo.provide('openils.widget.PCrudFilterDialog');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('dijit.form.FilteringSelect');
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
            },

            /**
             * Builds a basic table of key / value pairs.  Keys are IDL display labels.
             * Values are dijit's, when values set
             */
            startup : function() {
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

                dojo.place( // TODO i18n/CSS
                    dojo.create(
                        'div', 
                        {innerHTML:'Filter Selector', style:'text-align:center;width:100%;padding:10px;'}
                    ), this.domNode);

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
                    }
                );
            }
        }
    );
}

