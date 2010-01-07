dump('entering util/fm_utils.js\n');

if (typeof util == 'undefined') var util = {};
util.fm_utils = {};

util.fm_utils.EXPORT_OK    = [ 'flatten_ou_branch', 'find_ou', 'compare_aou_a_is_b_or_ancestor', 'sort_func_aou_by_depth_and_then_string', 'find_common_aou_ancestor', 'find_common_aou_ancestors' ];
util.fm_utils.EXPORT_TAGS    = { ':all' : util.fm_utils.EXPORT_OK };

util.fm_utils.flatten_ou_branch = function(branch) {
    var my_array = new Array();
    my_array.push( branch );
    if (typeof branch.children == 'function') for (var i in branch.children() ) {
        var child = branch.children()[i];
        if (child != null) {
            var temp_array = util.fm_utils.flatten_ou_branch(child);
            for (var j in temp_array) {
                my_array.push( temp_array[j] );
            }
        }
    }
    return my_array;
}

util.fm_utils.find_ou = function(tree,id) {
    if (typeof(id)=='object') { id = id.id(); }
    if (tree.id()==id) {
        return tree;
    }
    for (var i in tree.children()) {
        var child = tree.children()[i];
        ou = util.fm_utils.find_ou( child, id );
        if (ou) { return ou; }
    }
    return null;
}

util.fm_utils.compare_aou_a_is_b_or_ancestor = function(a,b) {
    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
    if (typeof a != 'object') a = data.hash.aou[ a ];
    if (typeof b != 'object') b = data.hash.aou[ b ];
    var node = b;
    while ( node != null ) {
        if (a.id() == node.id()) return true;
        node = typeof node.parent_ou() == 'object' ? node.parent_ou() : data.hash.aou[ node.parent_ou() ];
    }
    return false;
}

util.fm_utils.sort_func_aou_by_depth_and_then_string = function(a,b) {
    try {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
        var a_aou = a[0]; var b_aou = b[0];
        var a_string = a[1]; var b_string = b[1];
        if (typeof a_aou != 'object') a_aou = data.hash.aou[ a_aou ];
        if (typeof b_aou != 'object') b_aou = data.hash.aou[ b_aou ];
        var A = data.hash.aout[ a_aou.ou_type() ].depth();
        var B = data.hash.aout[ b_aou.ou_type() ].depth();
        if (A < B) return 1;
        if (A > B) return -1;
        if (a_string < b_string ) return -1;
        if (a_string > b_string ) return 1;
        return 0;
    } catch(E) {
        alert('error in util.fm_utils.sort_func_aou_by_depth_and_string: ' + E);
        return 0;
    }
}

util.fm_utils.find_common_aou_ancestor = function(orgs) {
    try {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

        var candidates = {};
        for (var i = 0; i < orgs.length; i++) {

            var node = orgs[i]; 

            while (node) {

                if (typeof node != 'object') node = data.hash.aou[ node ];
                if (!node) continue;

                if ( candidates[node.id()] ) {

                    candidates[node.id()]++;
                    
                } else {

                    candidates[node.id()] = 1;
                }

                if (candidates[node.id()] == orgs.length) return node;

                node = node.parent_ou();
            }

        }

        return null;

    } catch(E) {
        alert('error in util.fm_utils.find_common_aou_ancestor: ' + E);
        return null;
    }
}

util.fm_utils.find_common_aou_ancestors = function(orgs) {
    try {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

        var candidates = {}; var winners = [];
        for (var i = 0; i < orgs.length; i++) {

            var node = orgs[i]; 

            while (node) {

                if (typeof node != 'object') node = data.hash.aou[ node ];
                if (!node) continue;

                if ( candidates[node.id()] ) {

                    candidates[node.id()]++;
                    
                } else {

                    candidates[node.id()] = 1;
                }

                node = node.parent_ou();
            }

        }

        for (var i in candidates) {

            if (candidates[i] == orgs.length) winners.push( i );
        }

        return winners;

    } catch(E) {
        alert('error in util.fm_utils.find_common_aou_ancestors: ' + E);
        return [];
    }
}

