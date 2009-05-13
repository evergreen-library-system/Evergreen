dojo.require('dijit.layout.TabContainer');
dojo.require('openils.widget.AutoGrid');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
dojo.require('openils.MarcXPathParser');


var provider;
var xpathParser = new openils.MarcXPathParser();
var subFields= [];

function draw() {
    if(providerId) {
        openils.Util.addCSSClass(dojo.byId('provider-list-div'), 'hidden');
        console.log('in draw');
        var pcrud = new openils.PermaCrud();
        pcrud.retrieve('acqpro', providerId, {
                oncomplete : function(r) {
                    provider = openils.Util.readResponse(r);
                    console.log('provider is' + js2JSON(provider));
                    var pane = new openils.widget.EditPane({fmObject:provider}, dojo.byId('provider-summary-pane'));
                    pane.startup();
                    console.log("pane started");
                    dojo.connect(providerTabs, 'selectChild', drawProviderSummary);                        
                }
 
            });
      
        drawProviderSummary();
    } else {
        console.log('in else block');
        openils.Util.removeCSSClass(dojo.byId('provider-details-div'), 'hidden');
        pListGrid.loadAll({order_by:{acqpro : 'name'}});       
        pListGrid.onPostCreate = function(fmObject) {
            location.href = location.href + '/' + fmObject.id();
        }
        
    }
   
}
function drawProviderSummary(child) {
    console.log(child);
    openils.Util.addCSSClass(dojo.byId('provider-details-div'), 'visible');
    console.log('added provider.list.div');
    console.log("drawing provider-details-div");
  
    var loadedTabs = {'provider-address' : true};
    if(child){   
        if(loadedTabs[child.id]) return;
        loadedTabs[child.id] = true;
        switch(child.id) {
        case 'tab-pro-contact': 
            pcListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            openils.Util.removeCSSClass(dojo.byId('contact-addr-div'), 'hidden');
            pcListGrid.resetStore();
            pcListGrid.loadAll( {oncomplete:function(r){
                        var count = 0; 
                        pcListGrid.store.fetch( {onComplete:function(list) { 
                                    count =  list.length
                                        if(count>=1){
                                            var contactIds = [];                           
                                            dojo.forEach(list, function(item) {
                                                    contactIds.push(pcListGrid.store.getValue(item, 'id')); }
                                                );
                                            openils.Util.addCSSClass(dojo.byId('contact-addr-div'), 'visible');
                                            pcaListGrid.overrideEditWidgets.contact = new
                                            dijit.form.FilteringSelect({store: pcListGrid.store});
                                            pcaListGrid.resetStore();
                                            pcaListGrid.loadAll({order_by:{acqpca : 'contact'}}, {contact: contactIds});
                                        }else{ 
                                            return;
                                        }            
                                }
                            }
                            );
                    }
                }, {provider : providerId});
            
            break;
        case 'tab-attr': 
            padListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            padListGrid.resetStore();
            padListGrid.loadAll({order_by:{acqlipad : 'provider'}}, {provider : providerId});
            break;
        case 'tab-hold': 
            phsListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            phsListGrid.overrideEditWidgets.name = name;
            phsListGrid.resetStore();
            phsListGrid.loadAll({order_by:{acqphsm : 'provider'}}, {provider : providerId});
            break;
        default:
            paListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            paListGrid.resetStore();
            paListGrid.loadAll({order_by:{acqpa:'provider'}}, {provider: providerId}); 
        }
        
    } else {
        paListGrid.overrideEditWidgets.provider = new
            dijit.form.TextBox({disabled: 'true', value: providerId});
        paListGrid.resetStore();
        paListGrid.loadAll({order_by:{acqpa:'provider'}}, {provider: providerId}); 
    }
}


function getParsedTag(rowIndex, item) {
    console.log("in getParsedTag");
    console.log(item);
    return item && xpathParser.parse(padListGrid.store.getValue(item, 'xpath')).tags;
}


function getParsedSubf(rowIndex, item) {

    if(item) {
        var subfields = xpathParser.parse(padListGrid.store.getValue(item, 'xpath')).subfields;
        return subfields.join(',');
    }
    return'';
}
openils.Util.addOnLoad(draw);
