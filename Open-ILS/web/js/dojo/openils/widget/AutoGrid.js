if(!dojo._hasResource['openils.widget.AutoGrid']) {
    dojo.provide('openils.widget.AutoGrid');
    dojo.require('dojox.grid.DataGrid');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('openils.Util');

    dojo.declare(
        'openils.widget.AutoGrid',
        [dojox.grid.DataGrid, openils.widget.AutoWidget],
        {
            startup : function() {
                this.inherited(arguments);
                this.initAutoEnv();
                var existing = (this.structure) ? this.structure[0].cells[0] : [];
                var fields = [];
                for(var f in this.sortedFieldList) {
                    var field = this.sortedFieldList[f];
                    if(!field || field.virtual) continue;
                    var entry = existing.filter(function(i){return (i.field == field.name)})[0];
                    if(entry) entry.name = field.label;
                    else entry = {field:field.name, name:field.label};
                    fields.push(entry);
                }
                this.setStructure([{cells: [fields]}]);
                this.setStore(this.buildAutoStore());
            },
        }
    );
    openils.widget.AutoGrid.markupFactory = dojox.grid.DataGrid.markupFactory;
}

