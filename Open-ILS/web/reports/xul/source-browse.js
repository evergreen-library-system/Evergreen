dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");

function sourceTreeHandlerDblClick (ev) { return sourceTreeHandler(ev,true) }

function sourceTreeHandler (ev, dbl) {

	var row = {}, col = {}, part = {}, item;
	var tree = $('idl-browse-tree');


	try {
		tree.treeBoxObject.getCellAt(ev.clientX, ev.clientY, row, col, part);
		item = tree.contentView.getItemAtIndex(row.value);
	} catch (e) {
		// ... meh
	}

	if (part.value == 'twisty' || dbl) { // opening or closing
		if (item.getAttribute('open') == 'true' && item.lastChild.childNodes.length == 0) {
			//var subtree = item.lastChild;
			//while (subtree.childNodes.length)
			//	subtree.removeChild(subtree.lastChild);

			var p = getIDLClass( item.getAttribute('idlclass') );

			var subtreeList = [];
			var link_fields = p.getElementsByTagName('link');

			for ( var i = 0; i < link_fields.length; i++ ) {
				var field = getIDLField( p, link_fields[i].getAttribute('field') );

				if (!field) continue;

				var name = field.getAttributeNS(rptNS,'label');
				if (!name) name = field.getAttribute('name');

				var suppress = field.getAttribute('suppress_controller');
				if (suppress && suppress.indexOf('open-ils.reporter-store') > -1) continue;

				var idlclass = link_fields[i].getAttribute('class');
				var map = link_fields[i].getAttribute('map');
				var link = link_fields[i].getAttribute('field');
				var key = link_fields[i].getAttribute('key');
				var reltype = link_fields[i].getAttribute('reltype');

				if (map) continue;

				var pathList = [];
				findAncestorStack( item, 'treeitem', pathList );

				var fullpath = '';

				for (var j in pathList.reverse()) {
					var n = pathList[j].getAttribute('idlclass');
					var f = pathList[j].getAttribute('field');
					var j = pathList[j].getAttribute('join');

					if (f) fullpath += "-" + f;
					if (f && j != 'undefined') fullpath += '>' + j;

					if (fullpath) fullpath += ".";
					fullpath += n;

				}

				fullpath += "-" + link;

				subtreeList.push(
					{ name : name,
					  nullable : rpt_strings.LINK_NULLABLE_DEFAULT,
					  idlclass : idlclass,
					  map : map,
					  key : key,
					  field : field.getAttribute('name'),
					  reltype : reltype,
					  link : link,
					  fullpath : fullpath
					}
				);

                if ($('nullable-source-control').checked) {
	                if (reltype == 'has_a') {
	    				subtreeList.push(
		    				{ name : name,
	                          nullable : rpt_strings.LINK_NULLABLE_RIGHT,
			    			  idlclass : idlclass,
				    		  map : map,
					    	  key : key,
						      join : 'right',
	    					  field : field.getAttribute('name'),
		    				  reltype : reltype,
			    			  link : link,
				    		  fullpath : fullpath + '>right'
					    	}
	    				);
	
	    				subtreeList.push(
		    				{ name : name,
	                          nullable : rpt_strings.LINK_NULLABLE_NONE,
				    		  idlclass : idlclass,
					    	  map : map,
						      key : key,
						      join : 'inner',
	    					  field : field.getAttribute('name'),
		    				  reltype : reltype,
			    			  link : link,
				    		  fullpath : fullpath + '>inner'
					    	}
	    				);
	
	                } else{
	    				subtreeList.push(
		    				{ name : name,
	                          nullable : rpt_strings.LINK_NULLABLE_LEFT,
			    			  idlclass : idlclass,
				    		  map : map,
					    	  key : key,
						      join : 'left',
	    					  field : field.getAttribute('name'),
		    				  reltype : reltype,
			    			  link : link,
				    		  fullpath : fullpath + '>left'
					    	}
	    				);
	
	    				subtreeList.push(
		    				{ name : name,
	                          nullable : rpt_strings.LINK_NULLABLE_NONE,
				    		  idlclass : idlclass,
					    	  map : map,
						      key : key,
						      join : 'inner',
	    					  field : field.getAttribute('name'),
		    				  reltype : reltype,
			    			  link : link,
				    		  fullpath : fullpath + '>inner'
					    	}
	    				);
	
	                }
                }
			}

			populateSourcesSubtree( item.lastChild, subtreeList );
		}
	} else if (item) {
		var classtree = $('class-treetop');

		while (classtree.childNodes.length)
			classtree.removeChild(classtree.lastChild);

		var c = getIDLClass( item.getAttribute('idlclass') );

		populateDetailTree(
			classtree,
			c,
			item
		);
	}

	return true;
}

function transformSelectHandler (noswap) {
	var transform_tree = $('trans-view');
	var transform = getSelectedItems(transform_tree)[0];

	if (transform) {
		if (transform.getAttribute('aggregate') == 'true') {
			$( 'filter_tab' ).setAttribute('disabled','true');
			$( 'aggfilter_tab' ).setAttribute('disabled','false');

			if (!noswap && $( 'filter_tab' ).selected)
				$( 'filter_tab' ).parentNode.selectedItem = $( 'aggfilter_tab' );
		} else {
			$( 'filter_tab' ).setAttribute('disabled','false');
			$( 'aggfilter_tab' ).setAttribute('disabled','true');

			if (!noswap && $( 'aggfilter_tab' ).selected)
				$( 'aggfilter_tab' ).parentNode.selectedItem = $( 'filter_tab' );
		}
	}

	if ($( 'filter_tab' ).selected) {
		if ($( 'filter_tab' ).getAttribute('disabled') == 'true')
			$( 'source-add' ).setAttribute('disabled','true');
		else
			$( 'source-add' ).setAttribute('disabled','false');

	} else if ($( 'aggfilter_tab' ).selected) {
		if ($( 'aggfilter_tab' ).getAttribute('disabled') == 'true')
			$( 'source-add' ).setAttribute('disabled','true');
		else
			$( 'source-add' ).setAttribute('disabled','false');

	} else if ($( 'dis_tab' ).selected) {
		$( 'source-add' ).setAttribute('disabled','false');
	}
}

function detailTreeHandler (args) {
	var class_tree = $('class-view');
	var transform_tree = $('trans-treetop');

	while (transform_tree.childNodes.length)
		transform_tree.removeChild(transform_tree.lastChild);

	var class_items = getSelectedItems(class_tree);;

	var transforms = new Object(); 
	for (var i in class_items) {
		var item = class_items[i];
		var dtype = item.lastChild.lastChild.getAttribute('label');

		var item_transforms = getTransforms({ datatype : dtype });

		for (var j in item_transforms) {
			transforms[item_transforms[j]] = OILS_RPT_TRANSFORMS[item_transforms[j]];
			transforms[item_transforms[j]].name = item_transforms[j];
		}
	}

	var transformList = [];
	for (var i in transforms) {
		transformList.push( transforms[i] );
	}

	transformList.sort( sortHashLabels );

	$( 'aggfilter_tab' ).setAttribute('disabled','true');

	for (var i in transformList) {
		var t = transformList[i];
		transform_tree.appendChild(
			createTreeItem(
				{ aggregate : t.aggregate,
				  name : t.name,
				  alias : t.label,
				  params : t.params
				},
				createTreeRow(
				  	{},
					createTreeCell( { label : t.label } ),
					createTreeCell( { label : t.params ? t.params : '0' } ),
					createTreeCell( { label : t.datatype.length > 0 ?  t.datatype.join(', ') : 'all' } ),
					createTreeCell( { label : t.aggregate ?  rpt_strings.SOURCE_BROWSE_AGGREGATE : rpt_strings.SOURCE_BROWSE_NON_AGGREGATE } )
				)
			)
		);

		if (t.aggregate) $( 'aggfilter_tab' ).setAttribute('disabled','false');
	}

	transformSelectHandler(true);

	return true;
}



