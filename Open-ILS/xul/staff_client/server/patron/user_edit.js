var cgi;
var orgTree;
var user;
var ses_id;
var user_groups = [];
var adv_items = [];
var user_perms = [];
var perm_list = [];
var ou_type_list = [];
var user_work_ous = [];
var work_ou_list = [];

function $(id) { return document.getElementById(id); }

function set_work_ou(row) {
        var wid = findNodeByName(row,'a.id').getAttribute('workou_id');
        var wapply = findNodeByName(row,'a.id').checked;

        var w;
        for (var i in user_work_ous) {
                if (!user_work_ous[i]) continue;
                if (user_work_ous[i].work_ou() == wid) {
                        w = user_work_ous[i];
                        if (wapply) {
                                w.isdeleted(0);
                                w.ischanged(1);
                        } else {
                                if (w.isnew()) {
                                        user_work_ous[i] = null;
                                } else {
                                        w.isdeleted(1);
                                }
                        }
                        break;
                }
        }

        if (!w) {
                if (wapply) {
                        p = new puwoum();
                        p.isnew(1);
                        p.work_ou(wid);
                        p.usr(user.id());

                        user_work_ous.push(p);
                }
        }
}

function set_perm(row) {
    var pid = findNodeByName(row,'p.code').getAttribute('permid');
    var papply = findNodeByName(row,'p.id').checked;
    var pdepth = findNodeByName(row,'p.depth').value;
    var pgrant = findNodeByName(row,'p.grantable').checked;

    var p;
    for (var i in user_perms) {
        if (user_perms[i].perm() == pid) {
            p = user_perms[i];
            if (papply) {
                p.isdeleted(0);
                p.ischanged(1);
                p.depth(pdepth);
                p.grantable(pgrant ? 1 : 0);
            } else {
                if (p.isnew()) {
                    user_perms[i] = null;
                } else {
                    p.isdeleted(1);
                }
            }
            break;
        }
    }

    if (!p) {
        if (papply) {
            p = new pupm();
            p.isnew(1);
            p.perm(pid);
            p.usr(user.id());
            p.depth('' + pdepth);
            p.grantable(pgrant ? 1 : 0);

            user_perms.push(p);
        }
    }

}

function save_user () {

    try {

        var save_perms = [];
        for (var i in user_perms) {
            // Group based perm? skip it.
            if (user_perms[i].id() < 0) continue;

            if (user_perms[i].depth() == null) {
                var p;
                for (var j in perm_list) {
                    if (perm_list[j].id() == user_perms[i].perm()) {
                        p = perm_list[j];
                        break;
                    }
                }
                throw $("patronStrings").getFormattedString('staff.patron.user_edit.save_user.depth_required', [p.code()]);
            }

            save_perms.push( user_perms[i] );
        }

        var save_ous = [];
        for (var i in user_work_ous) {
            if (!user_work_ous[i]) continue;
            save_ous.push( user_work_ous[i] );
        }

        var req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.work_ous.update', ses_id, save_ous );
        req.send(true);
        var wok = req.getResultObject();

        if (wok.ilsevent) throw wok;

        req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.permissions.update', ses_id, save_perms );
        req.send(true);
        var pok = req.getResultObject();

        if (pok.ilsevent) throw pok;

        if (pok || wok) {
            alert($("patronStrings").getFormattedString('staff.patron.user_edit.save_user.user_modified_successfully', [user.usrname(), user.card().barcode(), pok, wok]));
        }

        init_editor();

    } catch (e) {
        dump( js2JSON( e ));
        alert( js2JSON( e ));
    };



    return false;
}

function init_editor (u) {
    
    cgi = new CGI();

    ses_id = cgi.param('ses'); 
    try {
        if (xulG) if (xulG.ses) ses_id = xulG.ses;
        if (xulG) if (xulG.params) if (xulG.params.ses) ses_id = xulG.params.ses;
    } catch (e) {}

    var usr_id = cgi.param('usr'); 
    try {
        if (xulG) if (xulG.usr_id) usr_id = xulG.usr_id;
        if (xulG) if (xulG.params) if (xulG.params.usr_id) usr_id = xulG.params.usr_id;
    } catch (e) {}

    var usr_barcode = cgi.param('barcode'); 
    try {
        if (xulG) if (xulG.usr_barcode) usr_ibarcode = xulG.usr_barcode;
        if (xulG) if (xulG.params) if (xulG.params.usr_barcode) usr_ibarcode = xulG.params.usr_barcode;
    } catch (e) {}

    try {
        var req;
        if (usr_id) {
            req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.fleshed.retrieve', ses_id, usr_id );
        } else {
            req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.fleshed.retrieve_by_barcode', ses_id, usr_barcode );
        }
        req.send(true);
        user = req.getResultObject();
    } catch (E) {
        alert(E);
    }

    if (user.usrname()) $('user.usrname').value = user.usrname();
    if (user.card() && user.card().barcode()) $('user.card.barcode').value = user.card().barcode();
    if (user.first_given_name()) $('user.first_given_name').value = user.first_given_name();
    if (user.second_given_name()) $('user.second_given_name').value = user.second_given_name();
    if (user.family_name()) $('user.family_name').value = user.family_name();

    // grab the editing staff user object
    req = new RemoteRequest( 'open-ils.auth', 'open-ils.auth.session.retrieve', ses_id );
    req.send(true);
    var staff = req.getResultObject();

    req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.permissions.user_perms.retrieve', ses_id );
    req.send(true);
    var staff_perms = req.getResultObject();

    // Get the top of the staff perm org for ASSIGN_WORK_ORG_UNIT
    req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.perm.highest_org', ses_id, staff.id(), 'ASSIGN_WORK_ORG_UNIT' );
    req.send(true);
    var top_work_ou = req.getResultObject();

    // and now, the orgs where this staff member can apply the perms
    req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.org_tree.descendants.retrieve', top_work_ou);
    req.send(true);
    var work_ou_tree = req.getResultObject();

    // and now, the orgs where this staff member can apply the perms
    req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.get_work_ous', ses_id, user.id());
    req.send(true);
    user_work_ous = req.getResultObject();

    // and finally, the ou types
    req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.org_types.retrieve' );
    req.send(true);
    ou_type_list = req.getResultObject();

    user_perms = [];
    perm_list = [];
    if (user.id() > 0) {
        req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.permissions.user_perms.retrieve', ses_id, user.id() );
        req.send(true);
        user_perms = req.getResultObject();

        req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.permissions.retrieve' );
        req.send(true);
        perm_list = req.getResultObject();
    }

    f = $('permissions');
    while (f.firstChild) f.removeChild(f.lastChild);

    var rcount = 0;
    for (var i in perm_list.sort(function(a,b){ if (a.code() < b.code()) return -1;return 1; }))
        display_perm(f,perm_list[i],staff_perms, rcount++);

    f = $('work_ous');
    while (f.firstChild) f.removeChild(f.lastChild);

    //flatten the ou tree, keep only those with can_hav_users = true
    work_ou_list = [];
    trim_ou_tree( [work_ou_tree], work_ou_list );

    rcount = 0;
    for (var i in work_ou_list.sort( function(a,b){ if (a.shortname() < b.shortname()) return -1;return 1; }) )
        display_work_ou(f,work_ou_list[i], rcount++);

    return true;
}

function grep ( code, list ) {
    var ret = [];
    for (var i in list) {
        if (code(list[i])) ret.push(list[i]);
    }
    return ret;
}

function trim_ou_tree (tree, list) {
    for (var i in tree) {
        if (!tree[i]) continue;

        var type = grep( function(x) {return x.id() == tree[i].ou_type()}, ou_type_list )[0];
        if ( type && type.can_have_users() == 't' )
            list.push(tree[i]);

        if (tree[i].children()) trim_ou_tree(tree[i].children(), list);
    }
}

function display_work_ou (root,ou_def,r) {

    var wrow = $('work_tmpl').cloneNode(true);
    wrow.id = null;
    if (r % 2) wrow.setAttribute('class', 'odd');
    root.appendChild(wrow);

    findNodeByName(wrow,'a.name').value = ou_def.name();
    findNodeByName(wrow,'a.shortname').value = ou_def.shortname();

    findNodeByName(wrow,'a.id').setAttribute('workou_id', ou_def.id());

    var has_it = grep(
        function(x){ return x.work_ou() == ou_def.id() },
        user_work_ous
    ).length;

    findNodeByName(wrow,'a.id').checked = has_it > 0 ? true : false;
}

function display_perm (root,perm_def,staff_perms, r) {

    var prow = $('perm_tmpl').cloneNode(true);
    prow.id = null;
    if (r % 2) prow.setAttribute('class', 'odd');
    root.appendChild(prow);

    var all = false;
    for (var i in staff_perms) {
        if (staff_perms[i].perm() == -1) {
            all = true;
            break;
        }
    }

    var sp,up;
    if (!all) {
        for (var i in staff_perms) {
            if (perm_def.id() == staff_perms[i].perm() || staff_perms[i].perm() == -1) {
                sp = staff_perms[i];
                break;
            }
        }
    }

    for (var i in user_perms) {
        if (perm_def.id() == user_perms[i].perm())
            up = user_perms[i];
    }

    var dis = false;
    if ((up && up.id() < 0) || !sp || !sp.grantable()) dis = true; 
    if (all) dis = false; 

    findNodeByName(prow,'p.code').value = perm_def.code();
    findNodeByName(prow,'p.code').setAttribute('title', perm_def.description());
    findNodeByName(prow,'p.code').setAttribute('permid', perm_def.id());

    findNodeByName(prow,'p.id').disabled = dis;
    findNodeByName(prow,'p.id').checked = up ? true : false;

    findNodeByName(prow,'p.depth').disabled = dis;
    findNodeByName(prow,'p.depth').id = 'perm-depth-' + perm_def.id();
    selectBuilder(
        'perm-depth-' + perm_def.id(),
        globalOrgTypes,
        (up ? up.depth() : findOrgDepth(user.home_ou())),
        { label_field        : 'name',
          value_field        : 'depth',
          empty_label        : $("patronStrings").getString('staff.patron.user_edit.display_perm.select_one'),
          empty_value        : '',
          clear            : true }
    );

    findNodeByName(prow,'p.grantable').disabled = dis;
    findNodeByName(prow,'p.grantable').checked = up ? (up.grantable() != 0 ? true : false) : false;

}

function selectBuilder (id, objects, def, args) {
    var label_field = args['label_field'];
    var value_field = args['value_field'];
    var depth = args['depth'];
    var newOpt;

    if (!depth) depth = 0;

    args['depth'] = parseInt(depth) + 1;

    var child_field_name = args['child_field_name'];

    var sel = id;
    if (typeof sel != 'object')
        sel = $(sel);
    if (args['clear']) {
        sel.removeAllItems()
        args['clear'] = false;
        if (args['empty_label']) {
            newOpt = sel.appendItem(args['empty_label'], args['empty_value']);
            sel.selectedItem = newOpt;
        }
    }

    for (var i in objects) {
        var l = objects[i][label_field];
        var v = objects[i][value_field];

        if (typeof l == 'function')
            l = objects[i][label_field]();

        if (typeof v == 'function')
            v = objects[i][value_field]();

        newOpt = sel.appendItem(l,v);

        if (depth) {
            var d = 10 * depth;
            newOpt.style.paddingLeft = '' + d + 'px';
        }

        if (typeof def == 'object') {
            for (var j in def) {
                if (v == def[j]) {
                    sel.selectedItem = newOpt;
                }
            }
        } else {
            if (v == def) {
                sel.selectedItem = newOpt;
            }
        }

        if (child_field_name) {
            var c = objects[i][child_field_name];
            if (typeof c == 'function')
                c = objects[i][child_field_name]();

            selectBuilder(
                id,
                c,
                def,
                { label_field        : args['label_field'],
                  value_field        : args['value_field'],
                  depth            : args['depth'],
                  child_field_name    : args['child_field_name'] }
            );
        }

    }
}    

function findNodesByClass(root, nodeClass, list) {
    if(!list) list = [];
        if( !root || !nodeClass) {
        return null;
    }
        
        if(root.nodeType != 1) {
        return null;
    }
        
        if(root.className.match(nodeClass)) list.push( root );

        var children = root.childNodes;
        
        for( var i = 0; i != children.length; i++ ) {
                findNodesByClass(children[i], nodeClass, list);
        }                       
                        
        return list;            
}                                       

