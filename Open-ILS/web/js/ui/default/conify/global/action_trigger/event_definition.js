dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.form.Textarea');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.Util');


function loadEventDef() { 
    edGrid.loadAll({order_by:{atevdef : 'hook'}}); 
    edGrid.overrideEditWidgetClass.template = 'dijit.form.Textarea';
    dojo.connect(eventDefTabs,'selectChild', tabLoader);
}

var loadedTabs = {'tab-atevdef' : true};
function tabLoader(child) {
    if(loadedTabs[child.id]) return;
    loadedTabs[child.id] = true;
    switch(child.id) {
        case 'tab-atevparam': 
            tepGrid.loadAll({order_by:{atevparam : 'event_def'}}); 
            break;
        case 'tab-ath': 
            thGrid.loadAll({order_by:{ath : 'key'}}); 
            break;
        case 'tab-atenv': 
            teeGrid.loadAll({order_by:{atenv : 'event_def'}}); 
            break;
        case 'tab-atreact': 
            trGrid.loadAll({order_by:{atreact : 'module'}}); 
            break;
        case 'tab-atval': 
            tvGrid.loadAll({order_by:{atval : 'module'}}); 
            break;
    }
}

openils.Util.addOnLoad(loadEventDef);
