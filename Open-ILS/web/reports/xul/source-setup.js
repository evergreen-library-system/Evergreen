dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");
var idlNS	= "http://opensrf.org/spec/IDL/base/v1";
var persistNS	= "http://open-ils.org/spec/opensrf/IDL/persistence/v1";
var objNS	= "http://open-ils.org/spec/opensrf/IDL/objects/v1";
var rptNS	= "http://open-ils.org/spec/opensrf/IDL/reporter/v1";
var gwNS	= "http://opensrf.org/-/namespaces/gateway/v1";
var xulNS	= "http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul";

var oilsIDL;
var rpt_rel_cache = {};

function sortHashLabels (a,b) { return a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1; }

function sortNames (a,b) {
	var aname =  a.name.toLowerCase();
	if (!aname) aname = a.idlclass.toLowerCase();

	var bname =  b.name.toLowerCase();
	if (!bname) bname = b.idlclass.toLowerCase();

	return aname < bname ? -1 : 1;
}

function sortLabels (a,b) {
	var aname =  a.getAttributeNS(rptNS, 'label').toLowerCase();
	if (!aname) aname = a.getAttribute('name');
	if (!aname) aname = a.getAttribute('id');

	var bname =  b.getAttributeNS(rptNS, 'label').toLowerCase();
	if (!bname) bname = b.getAttribute('name');
	if (!bname) bname = b.getAttribute('id');

	return aname < bname ? -1 : 1;
}


function loadTemplate(id) {
	var cgi = new CGI();
	var session = cgi.param('ses');

	var r = new Request('open-ils.reporter:open-ils.reporter.template.retrieve', session, id);

	r.callback(
		function(res) {
			var tmpl = res.getResultObject();
			var template = JSON2js( tmpl.data() );

			resetUI( template.core_class );

			$('template-name').value = tmpl.name() + ' (clone)';
			$('template-description').value = tmpl.description();

			rpt_rel_cache = template.rel_cache;
			renderSources();
		}
	);

	r.send();
}


function loadIDL() {
        var req = new XMLHttpRequest();
        req.open('GET', '../fm_IDL.xml', true);
        req.onreadystatechange = function() {
                if( req.readyState == 4 ) {
                        oilsIDL = req.responseXML;
			populateSourcesMenu(
				filterByAttributeNS( oilsIDL.getElementsByTagName('class'), rptNS, 'core', 'true' )
			);

			var cgi = new CGI();
			var template_id = cgi.param('ct');
			if (template_id) loadTemplate(template_id);
                }
        }
	req.send(null);

}

function getIDLClass (id) { return filterByAttribute( oilsIDL.getElementsByTagName('class'), 'id', id )[0] }
function getIDLField (classNode,field) { return filterByAttribute( classNode.getElementsByTagName('field'), 'name', field )[0] }
function getIDLLink (classNode,field) { return filterByAttribute( classNode.getElementsByTagName('link'), 'field', field )[0] }

function resetUI (idlclass) {
	if (getKeys(rpt_rel_cache).length > 0) {
		if (!confirm( rpt_strings.SOURCE_SETUP_CONFIRM_EXIT)) return false;
	}

	rpt_rel_cache = {};
	try { renderSources(); } catch (e) {}

	populateSourcesTree( idlclass );

	var tree = $('sources-treetop').parentNode;
	tree.focus();
	tree.view.selection.select(0);
	tree.click();
}

function populateSourcesMenu (classList) {
	classList.sort( sortLabels );

	var menu = $('source-menu');

	menu.appendChild(
		createMenuItem(
			{ label : rpt_strings.SOURCE_SETUP_CORE_SOURCES,
			  disabled : 'true',
			  style : 'color: black; text-decoration: underline;'
			}
		)
	);


	for (var i in classList) {

		var name = classList[i].getAttributeNS(rptNS,'label');
		var id = classList[i].getAttribute('id');
		if (!name) name = id;

		menu.appendChild(
			createMenuItem(
				{ container : 'true',
				  idlclass : id,
				  label : name,
				  onmouseup : 'resetUI( "' + id + '");'
				}
			)
		);

	}

	menu.appendChild( createMenuSeparator() );

	var _m = createMenu(
		{ label : rpt_strings.SOURCE_SETUP_ALL_AVAIL_SOURCES },
		createMenuPopup(
			{},
			createMenuItem(
				{ label : rpt_strings.SOURCE_SETUP_ALL_AVAIL_SOURCES,
				  disabled : 'true',
				  style : 'color: black; '
				}
			),
			createMenuSeparator()
		)
	);

	menu.appendChild( _m );
	menu = _m.firstChild;

	var all = map(function(x){return x;}, oilsIDL.getElementsByTagNameNS(idlNS,'class'));
	all.sort( sortLabels );

	for (var i = 0; i < all.length; i++) {

		if (all[i].getAttributeNS(persistNS,'virtual') == 'true') continue;

		var name = all[i].getAttributeNS(rptNS,'label');
		var id = all[i].getAttribute('id');
		if (!name) name = id;

		menu.appendChild(
			createMenuItem(
				{ container : 'true',
				  idlclass : id,
				  label : name,
				  onmouseup : 'resetUI( "' + id + '");'
				}
			)
		);

	}


}

function populateSourcesTree (idlclass) {

	var tcNode = $('sources-treetop');
	while (tcNode.childNodes.length) tcNode.removeChild(tcNode.lastChild);

	var c = getIDLClass( idlclass );
	var name = c.getAttributeNS(rptNS,'label');
	if (!name) name = idlclass;

	tcNode.appendChild(
		createTreeItem(
			{ container : 'true',
			  idlclass : idlclass,
			  fullpath : idlclass
			},
			createTreeRow(
				{ },
				createTreeCell( { label : '' } ),
				createTreeCell( { label : name } )
			),
			createTreeChildren( { alternatingbackground : true } )
		)
	);
}

function populateSourcesSubtree (tcNode, classList) {
	classList.sort(sortNames);
	for (var i in classList) {
		var obj = classList[i];

		var p = getIDLClass( obj.idlclass );
		var cont = p.getElementsByTagName('link').length ? 'true' : 'false';

		tcNode.appendChild(
			createTreeItem(
				{ container : cont,
				  idlclass : obj.idlclass,
				  map : obj.map,
				  key : obj.key,
				  field : obj.field,
				  link : obj.link,
				  join : obj['join'],
				  reltype : obj.reltype,
				  fullpath : obj.fullpath
				},
				createTreeRow(
					{ },
					createTreeCell( { label : obj.nullable } ),
					createTreeCell( { label : obj.name } )
				),
				createTreeChildren( { alternatingbackground : true } )
			)
		);


	}
}

function populateDetailTree (tcNode, c, item) {
	var fullpath = item.getAttribute('fullpath');
	var reltype = item.getAttribute('reltype');

	var fields = nodelistToArray(c.getElementsByTagName('field'));
	fields.sort( sortLabels );

	var id = c.getAttribute('id');
	var path_label = [];

	var steps = fullpath.split('.');
	for (var k in steps) {

		if (!steps[k]) continue;

		var atom = steps[k].split('-');
		var classNode = getIDLClass(atom[0]);

		var _cname = classNode.getAttributeNS(rptNS, 'label');
		if (!_cname) _cname = classNode.getAttribute('id');

		var _label = _cname; 

		if (atom.length > 1 && k == steps.length - 1) {
			var field_name = atom[1];
			var join_type = field_name;

			field_name = field_name.split(/>/)[0];
			join_type = join_type.split(/>/)[1];

			var _f = getIDLField(classNode, field_name);
			var _fname = _f.getAttributeNS(rptNS, 'label');
			if (!_fname) _fname = _f.getAttribute('name');
			if (_fname) _label += ' :: ' + _fname; 
			if (join_type) _label += ' (' + join_type + ')'; 

		} else if (atom[1]) {
			var field_name = atom[1];
			var join_type = field_name;

			switch (join_type) {
				case 'right':
					_label += ' (' + rpt_strings.LINK_NULLABLE_RIGHT + ')'; 
					break;
				case 'left':
					_label += ' (' + rpt_strings.LINK_NULLABLE_LEFT + ')'; 
					break;
				case 'inner':
					_label += ' (' + rpt_strings.LINK_NULLABLE_NONE + ')'; 
					break;
			}
		}

		path_label.push(_label); 
	}

	$('path-label').value = path_label.join(' -> ');
	$('path-label').setAttribute('reltype',reltype);

	for (var i in fields) {

		var type = fields[i].getAttributeNS(rptNS, 'datatype');
		//if (!type) type = 'text';

		var suppress = fields[i].getAttribute('suppress_controller');
		if (suppress && suppress.indexOf('open-ils.reporter-store') > -1) continue;

		var label = fields[i].getAttributeNS(rptNS, 'label');
		var name = fields[i].getAttribute('name');
		if (!label) label = name;

		tcNode.appendChild(
			createTreeItem(
				{ idlclass : id,
				  idlfield : name,
				  datatype : type,
				  fullpath : fullpath
				},
				createTreeRow(
					{ },
					createTreeCell( { label : label } ),
					createTreeCell( { label : type } )
				)
			)
		);
	}
}


