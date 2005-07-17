sdump('D_TRACE','Loading fm_utils.js\n');

function get_my_orgs(user_ou) {

	// self and ancestors
	var current_item_id = user_ou.id();
	//sdump('D_FM_UTILS','mw.G[user_ou] = ' + js2JSON(mw.G['user_ou']) + '\n');
	//sdump('D_FM_UTILS','current_item_id = ' + current_item_id + '\n');
	var item_ou; var my_orgs = {}; var other_orgs = {};
	while( item_ou = find_ou(mw.G['org_tree'],current_item_id) ) {
		//sdump('D_FM_UTILS','\titem_ou = ' + js2JSON(item_ou) + '\n');
		my_orgs[ item_ou.id() ] = item_ou;
		current_item_id = item_ou.parent_ou();
		if (!current_item_id) { break; }
	}

        current_item_id = user_ou.id();
	//sdump('D_FM_UTILS','self & ancestors : my_orgs = <<<'+js2JSON(my_orgs)+'>>>\n');
	// descendants
	var my_children;
        var find_ou_result = find_ou(mw.G['org_tree'],current_item_id);
	if (find_ou_result) { 
		my_children = find_ou_result.children() } 
	else {
		sdump('D_FM_UTILS','ERROR: find_ou(org_tree,'+current_item_id+') returned with no properties\n');
	};
	//sdump('D_FM_UTILS','my_children: ' + my_children + ' : ' + js2JSON(my_children) + '\n');
        if (my_children) {
                for (var i = 0; i < my_children.length; i++) {
                        var my_child = my_children[i];
                        my_orgs[ my_child.id() ] = my_child;
			//sdump('D_FM_UTILS','my_child.children(): ' + my_child.children() + ' : ' + js2JSON(my_child.children()) + '\n');
			if (my_child.children() != null) {
                        	for (var j = 0; j < my_child.children().length; j++) {
					var my_gchild = my_child.children()[j];
					my_orgs[ my_gchild.id() ] = my_gchild;
                        	}
			}
                }
        }
	//sdump('D_FM_UTILS','& descendants : my_orgs = <<<'+js2JSON(my_orgs)+'>>>\n');
	return my_orgs;
}

function get_other_orgs(org,other_orgs) {
}

function flatten_ou_branch(branch) {
	//sdump('D_FM_UTILS','flatten: branch = ' + js2JSON(branch) + '\n');
	var my_array = new Array();
	my_array.push( branch );
	for (var i in branch.children() ) {
		var child = branch.children()[i];
		if (child != null) {
			var temp_array = flatten_ou_branch(child);
			for (var j in temp_array) {
				my_array.push( temp_array[j] );
			}
		}
	}
	return my_array;
}

function find_ou(tree,id) {
	if (typeof(id)=='object') { id = id.id(); }
	if (tree.id()==id) {
		return tree;
	}
	for (var i in tree.children()) {
		var child = tree.children()[i];
		ou = find_ou( child, id );
		if (ou) { return ou; }
	}
	return null;
}

function find_ou_by_shortname(tree,sn) {
	var ou = new aou();
	if (tree.shortname()==sn) {
		return tree;
	}
	for (var i in tree.children()) {
		var child = tree.children()[i];
		ou = find_ou_by_shortname( child, sn );
		if (ou) { return ou; }
	}
	return null;
}

function render_fm(d,obj) {
	sdump('D_FM_UTILS',arg_dump(arguments,{1:true}));
	var nl = d.getElementsByAttribute('render','true');
	for (var i = 0; i < nl.length; i++) {
		var node = nl[i];
		var fm_class = node.getAttribute('fm_class');
		var render_value = node.getAttribute('render_value');
		var render_css_style = node.getAttribute('render_css_style');
		var render_css_class = node.getAttribute('render_css_class');
		if ( !fm_class ) continue;
		if ( obj[ fm_class ] ) {
			sdump('D_FM_UTILS',"We're in:\n\trender_value = " + render_value + "\n\trender_css_style = " + render_css_style + "\n\trender_css_class = " + render_css_class + "\n");
			if (render_value) {
				var result = ''; var cmd = '';
				cmd = parse_render_string( 'obj[ fm_class ]', render_value );
				try { result = eval( cmd ); } catch(E) { sdump('D_ERROR',E); }
				set_widget_value_for_display( node, result );
				sdump('D_FM_UTILS','\t<'+cmd+'> renders <'+result+'>\n');
			}
			if (render_css_style) {
				var result = ''; var cmd = '';
				cmd = parse_render_string( 'obj[ fm_class ]', render_css_style );
				cmd = parse_render_string( 'result', cmd, /\%\%/g );
				try { result = eval(cmd); } catch(E) { sdump('D_ERROR',E); }
				node.setAttribute('style',result);
				sdump('D_FM_UTILS','\t<'+cmd+'> renders <'+result+'>\n');
			}
			if (render_css_class) {
				var result = ''; var cmd = '';
				cmd = parse_render_string( 'obj[ fm_class ]', render_css_class );
				cmd = cmd.replace( /\%\%/g, 'result' );
				try { result = eval(cmd); } catch(E) { sdump('D_ERROR',E); }
				node.setAttribute('class',result);
				sdump('D_FM_UTILS','\t<'+cmd+'> renders <'+result+'>\n');
			}
		}
	}
}
