dojo.require('openils.widget.AutoGrid');
dojo.require('openils.PermaCrud');
var provider;

function draw() {
    if(providerId) {
        drawProviderSummary();
    } else {
        openils.Util.removeCSSClass(dojo.byId('provider-list-div'), 'hidden');
        pListGrid.onPostCreate = function(fmObject) { 
            location.href = location.href + '/' + fmObject.id();
        }
        pListGrid.loadAll({order_by:{acqpro : 'name'}}); 
    }
}
openils.Util.addOnLoad(draw);

function drawProviderSummary() {
    openils.Util.removeCSSClass(dojo.byId('provider-details-div'), 'hidden');
    openils.Util.addCSSClass(dojo.byId('provider-list-div'), 'hidden');
    var pcrud = new openils.PermaCrud();
    pcrud.retrieve('acqpro', providerId, {
        oncomplete : function(r) {
            provider = openils.Util.readResponse(r);
            var pane = new openils.widget.EditPane({fmObject:provider, readOnly:true}, dojo.byId('provider-summary-pane'));
            pane.startup();
            
        }
    });
}

function getProviderName(rowIndex, item) {
    if(!item) return '';
    return '<a href="' + location.href + '/' + 
        this.grid.store.getValue(item, 'id') + '">' + 
        this.grid.store.getValue(item, 'name') + '</a>';
}


