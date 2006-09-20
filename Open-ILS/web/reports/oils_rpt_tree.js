var oilsIDLCache = {};

/* fetchs and draws the report tree */
function oilsDrawRptTree(callback) {
	oilsLoadRptTree(callback);
}

/* fetches the IDL XML */
function oilsLoadRptTree(callback) {
	var r = new XMLHttpRequest();
	r.open('GET', OILS_IDL_URL, true);
	r.onreadystatechange = function() {
		if( r.readyState == 4 ) {
			oilsParseRptTree(r.responseXML, callback);
		}
	}
	r.send(null);
}


/* turns the IDL into a js object */
function oilsParseRptTree(IDL, callback) {
	var classes = IDL.getElementsByTagName('class');
	oilsIDL = {};

	for( var i = 0; i < classes.length; i++ ) {
		var node = classes[i];
		var id = node.getAttribute('id');

		var obj = { 
			fields	: oilsRptParseFields(node),
			name		: node.getAttribute('id'),
			table		: node.getAttributeNS(oilsIDLPersistNS, 'tablename'),
			core		: node.getAttributeNS(oilsIDLReportsNS, 'core'),
			label		: node.getAttributeNS(oilsIDLReportsNS, 'label')
		};

		if( obj.core == 'true' ) obj.core = true;
		else obj.core = false;
		obj.label = (obj.label) ? obj.label : obj.name;

		oilsIDL[id] = obj;
	}

	oilsRenderRptTree(callback);
}

/* parses the links and fields portion of the IDL */
function oilsRptParseFields( node ) {
	var data = [];

	var fields = node.getElementsByTagName('fields')[0];
	fields = fields.getElementsByTagName('field');

	var links = node.getElementsByTagName('links')[0];
	if( links )
		links = links.getElementsByTagName('link');
	else links = [];

	for( var i = 0; i < fields.length; i++ ) {

		var field = fields[i];
		var name = field.getAttribute('name');

		var obj = {
			field : fields[i],
			name	: name,
			label : field.getAttributeNS(oilsIDLReportsNS,'label'),
			type	: 'field'
		}

		var link = null;
		for( var l = 0; l < links.length; l++ ) {
			if( links[l].getAttribute('field') == name ) {
				link = links[l];
				break;
			}
		}

		if( link ) {
			obj.type = 'link';
			obj.reltype = link.getAttribute('reltype');
			obj.key = link.getAttribute('key');
			obj['class'] = link.getAttribute('class');
		} else {
			if( fields[i].getAttributeNS(oilsIDLPersistNS, 'virtual') == 'true' ) 
				continue;
		}

		obj.label = (obj.label) ? obj.label : obj.name;
		data.push(obj);
	}

	/* sort by field name */
	data = data.sort(
		function(a,b) {
			if( a.name > b.name ) return 1;
			if( a.name < b.name ) return -1;
			return 0;
		}
	);

	return data;
}


/* shoves the IDL into a UI tree */
function oilsRenderRptTree(callback) {

	oilsRptTree = new SlimTree( $('oils_rpt_tree_div'), 'oilsRptTree' );
	var treeId = oilsNextId();
	oilsRptTree.addNode( treeId, -1, nodeText('oils_rpt_tree_label'));
	for( var i in oilsIDL ) {
		var data = oilsIDL[i];
		if( !data.core ) continue;
		var subTreeId	= oilsNextId();
		oilsRptTree.addNode( subTreeId, treeId, data.label );
		oilsRenderSubTree( data, subTreeId, 'Display Data', '' );
	}
	if( callback ) callback();
}


function oilsRenderSubTree( data, subTreeId, rootName, path ) {

	_debug("rendering subtree with full path "+path);

	for( var f = 0; f < data.fields.length; f++ ) {

		var field = data.fields[f];
		var  dataId = oilsNextId();

		var fval = data.name+'-'+field.name;
		var fullpath = (path) ? path + '-' + fval : fval;

		/* for now */
		//var action = 'javascript:oilsAddRptDisplayItem("'+fullpath+'")';
		var action = 'javascript:oilsRptDrawDataWindow("'+fullpath+'")';

		if( field.type == 'link' )
			action = 'javascript:oilsAddLinkTree("' +
				dataId+'","'+field['class']+'","'+fullpath+'");';

		oilsRptTree.addNode( dataId, subTreeId, field.label, action );
	}
}



var oilsLinkTreeCache = {};
function oilsAddLinkTree( parentId, classname, fullpath ) {
	_debug("adding link with class="+classname+' : full path '+fullpath);
	if( ! oilsLinkTreeCache[parentId] ) 
		oilsLinkTreeCache[parentId] = [];

	if( grep ( oilsLinkTreeCache[parentId], 
		function(i) { return (i == classname); } ) ) {
			oilsRptTree.toggle(parentId);
			return;
	}

	oilsLinkTreeCache[parentId].push(classname);
	var data = grep( oilsIDL, function(i) { return ( i.name == classname ); })[0];
	var sid = oilsRenderSubTree( data, parentId, '', fullpath );
	oilsRptTree.open(parentId);
}





