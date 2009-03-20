dojo.require('openils.widget.AutoGrid');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
var provider;
var contactIds = [];
function draw() {
    if(providerId) {
        openils.Util.addCSSClass(dojo.byId('provider-list-div'), 'hidden');
        drawProviderSummary();
    } else {
        openils.Util.addCSSClass(dojo.byId('provider-details-div'), 'hidden');
        pListGrid.onPostCreate = function(fmObject) {
            location.href = location.href + '/' + fmObject.id();
        }
        pListGrid.loadAll({order_by:{acqpro : 'name'}});
    }
}
openils.Util.addOnLoad(draw);

function drawProviderSummary() {
    openils.Util.removeCSSClass(dojo.byId('provider-details-div'), 'hidden');
    var pcrud = new openils.PermaCrud();
    pcrud.retrieve('acqpro', providerId, {
        oncomplete : function(r) {
            provider = openils.Util.readResponse(r);
            var pane = new openils.widget.EditPane({fmObject:provider}, dojo.byId('provider-summary-pane'));
            pane.startup();

        }
    });
    paListGrid.overrideEditWidgets.provider = new
        dijit.form.TextBox({style:'display:none', value: providerId});
    paListGrid.loadAll({order_by:{acqpa : 'provider'}}, {provider : providerId});
    pcListGrid.overrideEditWidgets.provider = new
        dijit.form.TextBox({style:'display:none', value: providerId});
    pcListGrid.loadAll(
    {
        order_by:{acqpc : 'name'},

        oncomplete:  function(){
            pcListGrid.store.fetch({
                onComplete: function(items) {
                    dojo.forEach(items, function(item) {
                        contactIds.push(pcListGrid.store.getValue(item, 'id')); }
                    );
                    console.log("contact IDs are " + js2JSON(contactIds));
                    pcaListGrid.overrideEditWidgets.contact = new
                        dijit.form.FilteringSelect({store: pcListGrid.store});
                    pcaListGrid.loadAll({order_by:{acqpca : 'contact'}}, {contact: contactIds});
                }
            });
        }
    }, {provider : providerId});
}

function getProviderName(rowIndex, item) {
    if(!item) return '';
    return '<a href="' + location.href + '/' +
        this.grid.store.getValue(item, 'id') + '">' +
        this.grid.store.getValue(item, 'name') + '</a>';
}

