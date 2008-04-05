if(!dojo._hasResource['util.Dojo']) {
dojo._hasResource['util.Dojo'] = true;
dojo.provide('util.Dojo');

/**
 * General purpose Dojo utility functions 
 */

dojo.declare('util.Dojo', null, {
    /* add instance methods here if necessary */
});


util.Dojo.buildSimpleGrid = function(domId, columns, dataList, identifier) {
    /** Builds a dojo grid based on the provided data.  
     * @param domId The ID of the DOM node where the grid lives.
     * @param structure List of column header objects.
     * @param dataList List of objects (hashes) to be inserted into the grid.
     * @paramd identifier The identifier field for objects in the grid.  Defaults to 'id'
     */
    identifier = (identifier) ? identifier : 'id';
    domNode = dojo.byId(domId);

    var colWidth = (dojo.coords(domNode.parentNode).w / columns.length) - 30;
    for(var i in columns) {
        if(columns[i].width == undefined)
            columns[i].width = colWidth + 'px';
    }

    layout = [{cells : [columns]}];

    var store = new dojo.data.ItemFileWriteStore({data:{identifier:identifier,items:dataList}});
    var model = new dojox.grid.data.DojoData(null, store, {rowsPerPage: 20, clientSort: true});
    var grid = new dojox.Grid({structure: layout, model: model}, domId);
    grid.setModel(model);
    grid.setStructure(layout);
    grid.startup();

    return {grid:grid, store:store, model:model};
};
}

