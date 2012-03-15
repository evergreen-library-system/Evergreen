dump('entering util/hide.js\n');

if (typeof util == 'undefined') var util = {};
util.hide = {};

util.hide.EXPORT_OK    = [
    'generate_dialog',
    'generate_css'
];
util.hide.EXPORT_TAGS    = { ':all' : util.hide.EXPORT_OK };

util.hide.generate_dialog = function(setting,org) {
    JSAN.use('util.network'); JSAN.use('OpenILS.data');
    var data = new OpenILS.data(); data.stash_retrieve();
    var network = new util.network();

    // gather the hideable elements and determine how we might best label them
    var nl = document.getElementsByAttribute('hideable','*');
    var hideable = {};
    for (var i = 0; i < nl.length; i++) {
        var hname = nl[i].getAttribute('hideable');
        var value = nl[i].getAttribute('value');
        var label = nl[i].getAttribute('label');

        if (typeof hideable[hname] == 'undefined') {
            hideable[hname] = hname;
        }

        if (nl[i].nodeName == 'label' && value) {
            hideable[hname] = value;
        }

        if (label) {
            hideable[hname] = label;
        }
    }

    // put them into a sorted array
    var elements = [];
    for (var hname in hideable) {
        elements.push( { 'hname' : hname, 'label' : hideable[hname] } );
    }
    elements = elements.sort(
        function(a,b) {
            if (a.label < b.label) return -1;
            if (a.label > b.label) return 1;
            return 0;
        }
    );

    // create our dialog
    JSAN.use('util.widgets');
    var vbox = document.createElement('vbox');
    var menu_box = document.createElement('hbox');
    vbox.appendChild(menu_box);
    var perm = 'STAFF_LOGIN'; // let's be less restrictive up front, since
    // staff may want to configure and then call over a manager for a perm
    // override
    var menu = util.widgets.render_perm_org_menu(perm,ses('ws_ou'));
    if (!menu) {
        alert(
            $('offlineStrings').getFormattedString(
                'util.hide_elements.missing_permission',
                [ perm ]
            )
        );
        return false;
    }
    menu_box.appendChild(menu);

    var already_hidden = {};
    var aous_req = network.simple_request(
        'FM_AOUS_SPECIFIC_RETRIEVE',
        [
            org || ses('ws_ou'),
            setting,
            ses()
        ]
    );
    if (aous_req) {
        var desc = document.createElement('description');
        vbox.appendChild(desc);
        var msg = $('offlineStrings').getFormattedString(
            'util.hide_elements.current_setting_preamble',
            [ ses('ws_ou_shortname'), data.hash.aou[ aous_req.org ].shortname() ]
        );
        desc.appendChild( document.createTextNode( msg ) );

        for (var i in aous_req.value) {
            already_hidden[aous_req.value[i]] = true;
        }

        /* update data.hash.aous while we have fresh data */
        data.hash.aous[setting] = aous_req.value;
        data.stash('hash');

    } else {
        var desc = document.createElement('description');
        vbox.appendChild(desc);
        var msg = $('offlineStrings').getFormattedString(
            'util.hide_elements.current_setting_nonexistent',
            [ ses('ws_ou_shortname') ]
        );
        desc.appendChild( document.createTextNode( msg ) );

        data.hash.aous[setting] = null;
        data.stash('hash');
    }

    for (var i = 0; i < elements.length; i++) {
        var checkbox = document.createElement('checkbox');
        checkbox.setAttribute('label',elements[i].label);
        checkbox.setAttribute('value',elements[i].hname);
        if (already_hidden[elements[i].hname]) {
            checkbox.setAttribute('checked','true');
        }
        vbox.appendChild(checkbox);
    }


    var results = widget_prompt(
        vbox,
        {
            'title' : $('offlineStrings').getString('util.hide_elements.title'),
            'desc' : $('offlineStrings').getString('util.hide_elements.desc'),
            'access' : 'method',
            'method' : function() {
                var hide_these = [];
                for (var i = 0; i < vbox.childNodes.length; i++) {
                    var checkbox = vbox.childNodes[i];
                    if (checkbox.checked) {
                        hide_these.push( checkbox.getAttribute('value') );
                    }
                }
                return { 'org' : menu.value, 'elements' : hide_these };
            }
        }
    );
    if (!results) { return; }

    var params = {};
    params[setting] = results.elements.length > 0
        ? results.elements
        : null; // delete the setting so we can inherit from higher orgs
    var result = network.simple_request(
        'FM_AOUS_UPDATE',
        [
            ses(),
            results.org,
            params
        ]
    );
    if (result == 1) {

        if (results.elements.length > 0) {
            alert($('offlineStrings').getString('util.hide_elements.update_setting.update_success'));
        } else {
            alert($('offlineStrings').getString('util.hide_elements.update_setting.delete_success'));
        }
        data.hash.aous[setting] = params[setting];
        data.stash('hash');

        util.hide.generate_css(setting);

    } else {
        alert($('offlineStrings').getString('util.hide_elements.update_setting.failure'));
    }
}

util.hide.generate_css = function(setting) {
    JSAN.use('OpenILS.data');
    var data = new OpenILS.data(); data.stash_retrieve();
    var hidden = {};
    for (var i in data.hash.aous[setting]) {
        hidden[data.hash.aous[setting][i]] = true;
    }
 
    var nl = document.getElementsByAttribute('hideable','*');
    for (var i = 0; i < nl.length; i++) {
        var hname = nl[i].getAttribute('hideable');
        if (hidden[hname]) {
            addCSSClass(nl[i],'hideme');
        } else {
            removeCSSClass(nl[i],'hideme');
        }
    }
}

dump('exiting util/hide.js\n');
