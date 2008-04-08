if(!dojo._hasResource['util.Dojo']) {
dojo._hasResource['util.Dojo'] = true;
dojo.provide('util.Dojo');

/**
 * General purpose Dojo utility functions 
 */

dojo.declare('util.Dojo', null, {
    /* add instance methods here if necessary */
});


util.Dojo.buildSimpleGrid = function(domId, columns, dataList, identifier, delayed) {
    /** Builds a dojo grid based on the provided data.  
     * @param domId The ID of the DOM node where the grid lives.
     * @param structure List of column header objects.
     * @param dataList List of objects (hashes) to be inserted into the grid.
     * @param identifier The identifier field for objects in the grid.  Defaults to 'id'
     * @param delayed If true, method returns before the model is linked to the grid. 
     *      The purpose of this is to allow the client to fill the grid with data
     *      before rendering to get past dojo grid display bugs
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
    var grid = new dojox.Grid({structure: layout}, domId);

    if(delayed)
        return {grid:grid, store:store, model:model};

    grid.setModel(model);
    grid.setStructure(layout);
    grid.startup();

    return {grid:grid, store:store, model:model};
};

util.Dojo.expandoGridToggle = function (gridId, inIndex, inShow) {
    var grid = dijit.byId(gridId);
    grid.expandedRows[inIndex] = inShow;
    grid.updateRow(inIndex);
}

util.Dojo.buildExpandoGrid = function(domId, columns, getSubRowDetail, identColumn) {

    identColumn = (identColumn) ? identColumn : 'id';
    var grid = new dojox.Grid({}, domId);

    var rowBar = {type: 'dojox.GridRowView', width: '20px' };

    function onBeforeRow(inDataIndex, inRow) {
        inRow[1].hidden = (!grid.expandedRows || !grid.expandedRows[inDataIndex]);
    }

    function getCheck(inRowIndex) {
        var image = (this.grid.expandedRows[inRowIndex]) ? 'open.gif' : 'closed.gif';
        var show = (this.grid.expandedRows[inRowIndex]) ? 'false' : 'true';
        return '<img src="/oils/media/js/dojo/dojox/grid/tests/images/' + image + 
            '" onclick="util.Dojo.expandoGridToggle(\'' + 
                this.grid.id + '\',' + inRowIndex + ', ' + show + ')" height="11" width="11">';
    }

    /* XXX i18n name: */
    columns.unshift({name: 'Details', width: 4.5, get: getCheck, styles: 'text-align: center;' });

    var view = {
        onBeforeRow: onBeforeRow,
        cells: [
            columns,
            /* XXX i18n name: */
            [{ name: 'Detail', colSpan: columns.length, get: getSubRowDetail }]
        ]
    };

    grid.setStructure([rowBar, view]);

    var store = new dojo.data.ItemFileWriteStore({data:{identifier:identColumn, items:[]}});
    var model = new dojox.grid.data.DojoData(null, store, {rowsPerPage: 20, clientSort: true});
    grid.startup();
    grid.expandedRows = [];

    return {grid:grid, model:model};
};

}




