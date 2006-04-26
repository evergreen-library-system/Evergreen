var marcns = new Namespace("http://www.loc.gov/MARC21/slim");
var xulns = new Namespace("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul");
default xml namespace = marcns;

var tooltip_hash = {};
var current_focus;
var _record_type;
var bib_data;

function createComplexHTMLElement (e, attrs, objects, text) {
	var l = document.createElementNS('http://www.w3.org/1999/xhtml',e);

	if (attrs) {
		for (var i in attrs) l.setAttribute(i,attrs[i]);
	}

	if (objects) {
		for ( var i in objects ) l.appendChild( objects[i] );
	}

	if (text) {
		l.appendChild( document.createTextNode(text) )
	}

	return l;
}

function createComplexXULElement (e, attrs, objects) {
	var l = document.createElementNS('http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul',e);

	if (attrs) {
		for (var i in attrs) l.setAttribute(i,attrs[i]);
	}

	if (objects) {
		for ( var i in objects ) l.appendChild( objects[i] );
	}

	return l;
}

function createDescription (attrs) {
	return createComplexXULElement('description', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTooltip (attrs) {
	return createComplexXULElement('tooltip', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createLabel (attrs) {
	return createComplexXULElement('label', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createVbox (attrs) {
	return createComplexXULElement('vbox', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createHbox (attrs) {
	return createComplexXULElement('hbox', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createRow (attrs) {
	return createComplexXULElement('row', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTextbox (attrs) {
	return createComplexXULElement('textbox', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createPopup (attrs) {
	return createComplexXULElement('popup', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createMenuitem (attrs) {
	return createComplexXULElement('menuitem', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createMARCTextbox (element,attrs) {

	var box = createComplexXULElement('textbox', attrs, Array.prototype.slice.apply(arguments, [2]) );
	box.onkeypress = function (event) {
		var root_node;
		var node = element;
		while(node = node.parent()) {
			root_node = node;
		}

		var row = event.target;
		while (row.tagName != 'row') row = row.parentNode;

		if (element.nodeKind() == 'attribute') element[0]=box.value;
		else element.setChildren( box.value );

		if (event.charCode == 100 && event.ctrlKey) { // ctrl+d

			var index_sf, target, move_data;
			if (element.localName() == 'subfield') {
				index_sf = element;
				target = event.target.parentNode;

				var start = event.target.selectionStart;
				var end = event.target.selectionEnd - event.target.selectionStart ?
						event.target.selectionEnd :
						event.target.value.length;

				move_data = event.target.value.substring(start,end);
				event.target.value = event.target.value.substring(0,start) + event.target.value.substring(end);
				event.target.setAttribute('size', event.target.value.length + 2);

				element.setChildren( event.target.value );

			} else if (element.localName() == 'code') {
				index_sf = element.parent();
				target = event.target.parentNode;
			} else if (element.localName() == 'tag' || element.localName() == 'ind1' || element.localName() == 'ind2') {
				index_sf = element.parent().children()[element.parent().children().length() - 1];
				target = event.target.parentNode.lastChild.lastChild;
			}

			var sf = <subfield code="" xmlns="http://www.loc.gov/MARC21/slim">{ move_data }</subfield>;

			index_sf.parent().insertChildAfter( index_sf, sf );

			var new_sf = marcSubfield(sf);

			if (target === target.parentNode.lastChild) {
				target.parentNode.appendChild( new_sf );
			} else {
				target.parentNode.insertBefore( new_sf, target.nextSibling );
			}

			new_sf.firstChild.nextSibling.focus();

			event.preventDefault();
			return false;

		} else if (event.keyCode == 13 || event.keyCode == 77) {
			if (event.ctrlKey) { // ctrl+enter

				var index;
				if (element.localName() == 'subfield') index = element.parent();
				if (element.localName() == 'code') index = element.parent().parent();
				if (element.localName() == 'tag') index = element.parent();
				if (element.localName() == 'ind1') index = element.parent();
				if (element.localName() == 'ind2') index = element.parent();

				var df = <datafield tag="" ind1="" ind2="" xmlns="http://www.loc.gov/MARC21/slim"><subfield code="" /></datafield>;

				index.parent().insertChildAfter( index, df );

				var new_df = marcDatafield(df);

				if (row.parentNode.lastChild === row) {
					row.parentNode.appendChild( new_df );
				} else {
					row.parentNode.insertBefore( new_df, row.nextSibling );
				}

				new_df.firstChild.focus();

				event.preventDefault();
				return false;

			} else if (event.shiftKey) {
				if (row.previousSibling.className.match('marcDatafieldRow'))
					row.previousSibling.firstChild.focus();
			} else {
				row.nextSibling.firstChild.focus();
			}

		} else if (event.keyCode == 46 && event.ctrlKey) { // ctrl+del

			var index;
			if (element.localName() == 'subfield') index = element.parent();
			if (element.localName() == 'code') index = element.parent().parent();
			if (element.localName() == 'tag') index = element.parent();
			if (element.localName() == 'ind1') index = element.parent();
			if (element.localName() == 'ind2') index = element.parent();

			for (var i in index.parent().children()) {
				if (index === index.parent().children()[i]) {
					delete index.parent().children()[i];
					break;
				}
			}

			row.previousSibling.firstChild.focus();
			row.parentNode.removeChild(row);

			event.preventDefault();
			return false;

		} else if (event.keyCode == 46 && event.shiftKey) { // shift+del

			var index;
			if (element.localName() == 'subfield') index = element;
			if (element.localName() == 'code') index = element.parent();

			if (index) {
				for (var i in index.parent().children()) {
					if (index === index.parent().children()[i]) {
						delete index.parent().children()[i];
						break;
					}
				}

				if (event.target.parentNode === event.target.parentNode.parentNode.lastChild) {
					event.target.parentNode.previousSibling.lastChild.focus();
				} else {
					event.target.parentNode.nextSibling.firstChild.nextSibling.focus();
				}

				event.target.parentNode.parentNode.removeChild(event.target.parentNode);

				event.preventDefault();
				return false;
			}
		}
		return true;
	};

	box.addEventListener(
		'keypress', 
		function () {
			if (element.nodeKind() == 'attribute') element[0]=box.value;
			else element.setChildren( box.value );
			return true;
		},
		false
	);

	box.addEventListener(
		'change', 
		function () {
			if (element.nodeKind() == 'attribute') element[0]=box.value;
			else element.setChildren( box.value );
			return true;
		},
		false
	);

	box.addEventListener(
		'keypress', 
		function () {
			if (element.nodeKind() == 'attribute') element[0]=box.value;
			else element.setChildren( box.value );
			return true;
		},
		true
	);

	return box;
}

var rec_type = {
        BKS : { Type : /[at]{1}/,	BLvl : /[acdm]{1}/ },
	SER : { Type : /[a]{1}/,	BLvl : /[bs]{1}/ },
	VIS : { Type : /[gkro]{1}/,	BLvl : /[abcdms]{1}/ },
	MIX : { Type : /[p]{1}/,	BLvl : /[cd]{1}/ },
	MAP : { Type : /[ef]{1}/,	BLvl : /[abcdms]{1}/ },
	SCO : { Type : /[cd]{1}/,	BLvl : /[abcdms]{1}/ },
	REC : { Type : /[ij]{1}/,	BLvl : /[abcdms]{1}/ },
	COM : { Type : /[m]{1}/,	BLvl : /[abcdms]{1}/ }
};

var ff_pos = {
	Ctry : {
		_8 : {
			BKS : {start : 15, len : 3, def : ' ' },
			SER : {start : 15, len : 3, def : ' ' },
			VIS : {start : 15, len : 3, def : ' ' },
			MIX : {start : 15, len : 3, def : ' ' },
			MAP : {start : 15, len : 3, def : ' ' },
			SCO : {start : 15, len : 3, def : ' ' },
			REC : {start : 15, len : 3, def : ' ' },
			COM : {start : 15, len : 3, def : ' ' },
		}
	},
	Lang : {
		_8 : {
			BKS : {start : 35, len : 3, def : ' ' },
			SER : {start : 35, len : 3, def : ' ' },
			VIS : {start : 35, len : 3, def : ' ' },
			MIX : {start : 35, len : 3, def : ' ' },
			MAP : {start : 35, len : 3, def : ' ' },
			SCO : {start : 35, len : 3, def : ' ' },
			REC : {start : 35, len : 3, def : ' ' },
			COM : {start : 35, len : 3, def : ' ' },
		}
	},
	MRec : {
		_8 : {
			BKS : {start : 38, len : 1, def : ' ' },
			SER : {start : 38, len : 1, def : ' ' },
			VIS : {start : 38, len : 1, def : ' ' },
			MIX : {start : 38, len : 1, def : ' ' },
			MAP : {start : 38, len : 1, def : ' ' },
			SCO : {start : 38, len : 1, def : ' ' },
			REC : {start : 38, len : 1, def : ' ' },
			COM : {start : 38, len : 1, def : ' ' },
		}
	},
	DtSt : {
		_8 : {
			BKS : {start : 6, len : 1, def : ' ' },
			SER : {start : 6, len : 1, def : 'c' },
			VIS : {start : 6, len : 1, def : ' ' },
			MIX : {start : 6, len : 1, def : ' ' },
			MAP : {start : 6, len : 1, def : ' ' },
			SCO : {start : 6, len : 1, def : ' ' },
			REC : {start : 6, len : 1, def : ' ' },
			COM : {start : 6, len : 1, def : ' ' },
		}
	},
	Type : {
		ldr : {
			BKS : {start : 6, len : 1, def : 'a' },
			SER : {start : 6, len : 1, def : 'a' },
			VIS : {start : 6, len : 1, def : 'g' },
			MIX : {start : 6, len : 1, def : 'p' },
			MAP : {start : 6, len : 1, def : 'e' },
			SCO : {start : 6, len : 1, def : 'c' },
			REC : {start : 6, len : 1, def : 'i' },
			COM : {start : 6, len : 1, def : 'm' },
		}
	},
	Ctrl : {
		ldr : {
			BKS : {start : 8, len : 1, def : ' ' },
			SER : {start : 8, len : 1, def : ' ' },
			VIS : {start : 8, len : 1, def : ' ' },
			MIX : {start : 8, len : 1, def : ' ' },
			MAP : {start : 8, len : 1, def : ' ' },
			SCO : {start : 8, len : 1, def : ' ' },
			REC : {start : 8, len : 1, def : ' ' },
			COM : {start : 8, len : 1, def : ' ' },
		}
	},
	BLvl : {
		ldr : {
			BKS : {start : 7, len : 1, def : 'm' },
			SER : {start : 7, len : 1, def : 's' },
			VIS : {start : 7, len : 1, def : 'm' },
			MIX : {start : 7, len : 1, def : 'c' },
			MAP : {start : 7, len : 1, def : 'm' },
			SCO : {start : 7, len : 1, def : 'm' },
			REC : {start : 7, len : 1, def : 'm' },
			COM : {start : 7, len : 1, def : 'm' },
		}
	},
	Desc : {
		ldr : {
			BKS : {start : 18, len : 1, def : ' ' },
			SER : {start : 18, len : 1, def : ' ' },
			VIS : {start : 18, len : 1, def : ' ' },
			MIX : {start : 18, len : 1, def : ' ' },
			MAP : {start : 18, len : 1, def : ' ' },
			SCO : {start : 18, len : 1, def : ' ' },
			REC : {start : 18, len : 1, def : ' ' },
			COM : {start : 18, len : 1, def : ' ' },
		}
	},
	ELvl : {
		ldr : {
			BKS : {start : 17, len : 1, def : ' ' },
			SER : {start : 17, len : 1, def : ' ' },
			VIS : {start : 17, len : 1, def : ' ' },
			MIX : {start : 17, len : 1, def : ' ' },
			MAP : {start : 17, len : 1, def : ' ' },
			SCO : {start : 17, len : 1, def : ' ' },
			REC : {start : 17, len : 1, def : ' ' },
			COM : {start : 17, len : 1, def : ' ' },
		}
	},
	Indx : {
		_8 : {
			BKS : {start : 31, len : 1, def : '0' },
			MAP : {start : 31, len : 1, def : '0' },
		},
		_6 : {
			BKS : {start : 14, len : 1, def : '0' },
			MAP : {start : 14, len : 1, def : '0' },
		}
	},
	Date1 : {
		_8 : {
			BKS : {start : 7, len : 4, def : ' ' },
			SER : {start : 7, len : 4, def : ' ' },
			VIS : {start : 7, len : 4, def : ' ' },
			MIX : {start : 7, len : 4, def : ' ' },
			MAP : {start : 7, len : 4, def : ' ' },
			SCO : {start : 7, len : 4, def : ' ' },
			REC : {start : 7, len : 4, def : ' ' },
			COM : {start : 7, len : 4, def : ' ' },
		},
	},
	Date2 : {
		_8 : {
			BKS : {start : 11, len : 4, def : ' ' },
			SER : {start : 11, len : 4, def : '9' },
			VIS : {start : 11, len : 4, def : ' ' },
			MIX : {start : 11, len : 4, def : ' ' },
			MAP : {start : 11, len : 4, def : ' ' },
			SCO : {start : 11, len : 4, def : ' ' },
			REC : {start : 11, len : 4, def : ' ' },
			COM : {start : 11, len : 4, def : ' ' },
		},
	},
	LitF : {
		_8 : {
			BKS : {start : 33, len : 1, def : '0' },
		},
		_6 : {
			BKS : {start : 16, len : 1, def : '0' },
		}
	},
	Biog : {
		_8 : {
			BKS : {start : 34, len : 1, def : ' ' },
		},
		_6 : {
			BKS : {start : 17, len : 1, def : ' ' },
		}
	},
	Ills : {
		_8 : {
			BKS : {start : 18, len : 4, def : ' ' },
		},
		_6 : {
			BKS : {start : 1, len : 4, def : ' ' },
		}
	},
	Fest : {
		_8 : {
			BKS : {start : 30, len : 1, def : '0' },
		},
		_6 : {
			BKS : {start : 13, len : 1, def : '0' },
		}
	},
	Conf : {
		_8 : {
			BKS : {start : 24, len : 4, def : ' ' },
			SER : {start : 25, len : 3, def : ' ' },
		},
		_6 : {
			BKS : {start : 7, len : 4, def : ' ' },
			SER : {start : 8, len : 3, def : ' ' },
		}
	},
	GPub : {
		_8 : {
			BKS : {start : 28, len : 1, def : ' ' },
			SER : {start : 28, len : 1, def : ' ' },
			VIS : {start : 28, len : 1, def : ' ' },
			MAP : {start : 28, len : 1, def : ' ' },
			COM : {start : 28, len : 1, def : ' ' },
		},
		_6 : {
			BKS : {start : 11, len : 1, def : ' ' },
			SER : {start : 11, len : 1, def : ' ' },
			VIS : {start : 11, len : 1, def : ' ' },
			MAP : {start : 11, len : 1, def : ' ' },
			COM : {start : 11, len : 1, def : ' ' },
		}
	},
	Audn : {
		_8 : {
			BKS : {start : 22, len : 1, def : ' ' },
			SER : {start : 22, len : 1, def : ' ' },
			VIS : {start : 22, len : 1, def : ' ' },
			SCO : {start : 22, len : 1, def : ' ' },
			REC : {start : 22, len : 1, def : ' ' },
			COM : {start : 22, len : 1, def : ' ' },
		},
		_6 : {
			BKS : {start : 5, len : 1, def : ' ' },
			SER : {start : 5, len : 1, def : ' ' },
			VIS : {start : 5, len : 1, def : ' ' },
			SCO : {start : 5, len : 1, def : ' ' },
			REC : {start : 5, len : 1, def : ' ' },
			COM : {start : 5, len : 1, def : ' ' },
		}
	},
	Form : {
		_8 : {
			BKS : {start : 23, len : 1, def : ' ' },
			SER : {start : 23, len : 1, def : ' ' },
			VIS : {start : 29, len : 1, def : ' ' },
			MIX : {start : 23, len : 1, def : ' ' },
			MAP : {start : 29, len : 1, def : ' ' },
			SCO : {start : 23, len : 1, def : ' ' },
			REC : {start : 23, len : 1, def : ' ' },
		},
		_6 : {
			BKS : {start : 6, len : 1, def : ' ' },
			SER : {start : 6, len : 1, def : ' ' },
			VIS : {start : 12, len : 1, def : ' ' },
			MIX : {start : 6, len : 1, def : ' ' },
			MAP : {start : 12, len : 1, def : ' ' },
			SCO : {start : 6, len : 1, def : ' ' },
			REC : {start : 6, len : 1, def : ' ' },
		}
	},
	'S/L' : {
		_8 : {
			SER : {start : 34, len : 1, def : '0' },
		},
		_6 : {
			SER : {start : 17, len : 1, def : '0' },
		}
	},
	'Alph' : {
		_8 : {
			SER : {start : 33, len : 1, def : ' ' },
		},
		_6 : {
			SER : {start : 16, len : 1, def : ' ' },
		}
	},
};

function recordType (rec) {
	var _l = rec.leader.toString();

	var _t = _l.substr(ff_pos.Type.ldr.BKS.start, ff_pos.Type.ldr.BKS.len);
	var _b = _l.substr(ff_pos.BLvl.ldr.BKS.start, ff_pos.BLvl.ldr.BKS.len);

	for (var t in rec_type) {
		if (_t.match(rec_type[t].Type) && _b.match(rec_type[t].BLvl)) {
			document.getElementById('recordTypeLabel').value = t;
			_record_type = t;
			return t;
		}
	}
}

function toggleFFE () {
	var grid = document.getElementById('leaderGrid');
	if (grid.hidden) {
		grid.hidden = false;
	} else {
		grid.hidden = true;
	}
	return true;
}

function changeFFEditor (type) {
	var grid = document.getElementById('leaderGrid');
	grid.setAttribute('type',type);
}

function fillFixedFields (rec) {
	var grid = document.getElementById('leaderGrid');

	var rtype = _record_type;

	var _l = rec.leader.toString();
	var _6 = rec.controlfield.(@tag=='006').toString();
	var _7 = rec.controlfield.(@tag=='007').toString();
	var _8 = rec.controlfield.(@tag=='008').toString();

	var list = [];
	var pre_list = grid.getElementsByTagName('label');
	for (var i in pre_list) {
		if ( pre_list[i].getAttribute && pre_list[i].getAttribute('set').indexOf(grid.getAttribute('type')) > -1 ) {
			list.push( pre_list[i] );
		}
	}

	for (var i in list) {
		var name = list[i].getAttribute('name');

		if (!ff_pos[name])
			continue;

		var value = '';
		if ( ff_pos[name].ldr && ff_pos[name].ldr[rtype] )
			value = _l.substr(ff_pos[name].ldr[rtype].start, ff_pos[name].ldr[rtype].len);

		if ( ff_pos[name]._8 && ff_pos[name]._8[rtype] )
			value = _8.substr(ff_pos[name]._8[rtype].start, ff_pos[name]._8[rtype].len);

		if ( !value && ff_pos[name]._6 && ff_pos[name]._6[rtype] )
			value = _6.substr(ff_pos[name]._6[rtype].start, ff_pos[name]._6[rtype].len);

		if ( ff_pos[name]._7 && ff_pos[name]._7[rtype] )
			value = _7.substr(ff_pos[name]._7[rtype].start, ff_pos[name]._7[rtype].len);
		
		if (!value) {
			var d;
			var p;
			if (ff_pos[name].ldr && ff_pos[name].ldr[rtype]) {
				d = ff_pos[name].ldr[rtype].def;
				p = 'ldr';
			}

			if (ff_pos[name]._8 && ff_pos[name]._8[rtype]) {
				d = ff_pos[name]._8[rtype].def;
				p = '_8';
			}

			if (!value && ff_pos[name]._6 && ff_pos[name]._6[rtype]) {
				d = ff_pos[name]._6[rtype].def;
				p = '_6';
			}

			if (ff_pos[name]._7 && ff_pos[name]._7[rtype]) {
				d = ff_pos[name]._7[rtype].def;
				p = '_7';
			}

			if (!value) {
				for (var j = 0; j < ff_pos[name][p][rtype].len; j++) {
					value += d;
				}
			}
		}

		list[i].nextSibling.value = value;
	}

	return true;
}

function updateFixedFields (element) {
	var grid = document.getElementById('leaderGrid');
	var recGrid = document.getElementById('recGrid');

	var rtype = _record_type;
	var new_value = element.value;

	var parts = {
		ldr : _record.leader,
		_6 : _record.controlfield.(@tag=='006'),
		_7 : _record.controlfield.(@tag=='007'),
		_8 : _record.controlfield.(@tag=='008'),
	};

	var name = element.getAttribute('name');
	for (var i in ff_pos[name]) {

		if (!ff_pos[name][i][rtype])
			continue;

		var before = parts[i].substr(0, ff_pos[name][i][rtype].start);
		var after = parts[i].substr(ff_pos[name][i][rtype].start + ff_pos[name][i][rtype].len);

		for (var j = 0; new_value.length < ff_pos[name][i][rtype].len; j++) {
			new_value += ff_pos[name][i][rtype].def;
		}

		parts[i].setChildren( before + new_value + after );
		recGrid.getElementsByAttribute('tag',i)[0].lastChild.value = parts[i].toString();
	}

	return true;
}

function marcLeader (leader) {
	var row = createRow(
		{ class : 'marcLeaderRow',
		  tag : 'ldr' },
		createLabel(
			{ value : 'LDR',
			  class : 'marcTag',
			  tooltiptext : "MARC Leader" } ),
		createLabel(
			{ value : '',
			  class : 'marcInd1' } ),
		createLabel(
			{ value : '',
			  class : 'marcInd2' } ),
		createLabel(
			{ value : leader.text(),
			  class : 'marcLeader' } )
	);

	return row;
}

function marcControlfield (field) {
	tagname = field.@tag.toString().substr(2);
	var row = createRow(
		{ class : 'marcControlfieldRow',
		  tag : '_' + tagname },
		createLabel(
			{ value : field.@tag,
			  class : 'marcTag',
			  onmouseover : 'getTooltip(this, "tag");',
			  tooltipid : 'tag' + field.@tag } ),
		createLabel(
			{ value : field.@ind1,
			  class : 'marcInd1',
			  onmouseover : 'getTooltip(this, "ind1");',
			  tooltipid : 'tag' + field.@tag + 'ind1val' + field.@ind1 } ),
		createLabel(
			{ value : field.@ind2,
			  class : 'marcInd2',
			  onmouseover : 'getTooltip(this, "ind2");',
			  tooltipid : 'tag' + field.@tag + 'ind2val' + field.@ind2 } ),
		createLabel(
			{ value : field.text(),
			  class : 'marcControlfield' } )
	);

	return row;
}

function stackSubfields(checkbox) {
	var list = document.getElementsByAttribute('name','sf_box');

	var o = 'vertical';
	if (checkbox.checked) o = 'horizontal';
	
	for (var i in list) {
		if (list[i]) list[i].setAttribute('orient',o);
	}
}

function marcDatafield (field) {
	var row = createRow(
		{ class : 'marcDatafieldRow' },
		createMARCTextbox(
			field.@tag,
			{ value : field.@tag,
			  class : 'plain marcTag',
			  name : 'marcTag',
			  context : 'tags_popup',
			  oninput : 'if (this.value.length == 3) { this.nextSibling.focus(); }',
			  size : 3,
			  maxlength : 3,
			  onmouseover : 'current_focus = this; getTooltip(this, "tag");' } ),
		createMARCTextbox(
			field.@ind1,
			{ value : field.@ind1,
			  class : 'plain marcInd1',
			  name : 'marcInd1',
			  oninput : 'if (this.value.length == 1) { this.nextSibling.focus(); }',
			  size : 1,
			  maxlength : 1,
			  onmouseover : 'current_focus = this; getContextMenu(this, "ind1"); getTooltip(this, "ind1");',
			  oncontextmenu : 'getContextMenu(this, "ind1");' } ),
		createMARCTextbox(
			field.@ind2,
			{ value : field.@ind2,
			  class : 'plain marcInd2',
			  name : 'marcInd2',
			  oninput : 'if (this.value.length == 1) { this.nextSibling.firstChild.firstChild.focus(); }',
			  size : 1,
			  maxlength : 1,
			  onmouseover : 'current_focus = this; getContextMenu(this, "ind2"); getTooltip(this, "ind2");',
			  oncontextmenu : 'getContextMenu(this, "ind2");' } ),
		createHbox({ name : 'sf_box' })
	);

	if (!current_focus && field.@tag == '') current_focus = row.childNodes[0];
	if (!current_focus && field.@ind1 == '') current_focus = row.childNodes[1];
	if (!current_focus && field.@ind2 == '') current_focus = row.childNodes[2];

	var sf_box = row.lastChild;
	if (document.getElementById('stackSubfields').checked)
		sf_box.setAttribute('orient','vertical');

	sf_box.addEventListener(
		'click',
		function (e) {
			if (sf_box === e.target) {
				sf_box.lastChild.lastChild.focus();
			} else if (e.target.parentNode === sf_box) {
				e.target.lastChild.focus();
			}
		},
		false
	);


	for (var i in field.subfield) {
		var sf = field.subfield[i];
		sf_box.appendChild(
			marcSubfield(sf)
		);

		if (sf.@code == '' && (!current_focus || current_focus.className.match(/Ind/)))
			current_focus = sf_box.lastChild.childNodes[1];
	}

	return row;
}

function marcSubfield (sf) {			
	return createHbox(
		{ class : 'marcSubfieldBox' },
		createLabel(
			{ value : "\u2021",
			  class : 'plain marcSubfieldDelimiter',
			  onmouseover : 'getTooltip(this.nextSibling, "subfield");',
			  oncontextmenu : 'getContextMenu(this.nextSibling, "subfield");',
	  		  //onclick : 'this.nextSibling.focus();',
	  		  onfocus : 'this.nextSibling.focus();',
			  size : 2 } ),
		createMARCTextbox(
			sf.@code,
			{ value : sf.@code,
			  class : 'plain marcSubfieldCode',
			  name : 'marcSubfieldCode',
			  onmouseover : 'current_focus = this; getContextMenu(this, "subfield"); getTooltip(this, "subfield");',
			  oncontextmenu : 'getContextMenu(this, "subfield");',
			  oninput : 'if (this.value.length == 1) { this.nextSibling.focus(); }',
			  size : 2,
			  maxlength : 1 } ),
		createMARCTextbox(
			sf,
			{ value : sf.text(),
			  class : 'plain marcSubfield', 
			  onmouseover : 'getTooltip(this, "subfield");',
			  size : new String(sf.text()).length + 2,
			  oninput : "this.setAttribute('size', this.value.length + 2);",
			} )
	);
}

function loadRecord(rec) {
	_record = rec;
	var grid_rows = document.getElementById('recGrid').lastChild;

	grid_rows.appendChild( marcLeader( rec.leader ) );

	for (var i in rec.controlfield) {
		grid_rows.appendChild( marcControlfield( rec.controlfield[i] ) );
	}

	for (var i in rec.datafield) {
		grid_rows.appendChild( marcDatafield( rec.datafield[i] ) );
	}

	grid_rows.getElementsByAttribute('class','marcDatafieldRow')[0].firstChild.focus();
	changeFFEditor(recordType(rec));
	fillFixedFields(rec);
}

var context_menus = createComplexXULElement('popupset');
document.documentElement.appendChild( context_menus );

var tag_menu = createPopup({position : 'after_start', id : 'tags_popup'});
context_menus.appendChild( tag_menu );

tag_menu.appendChild(
	createMenuitem(
		{ label : 'Add Row',
		  oncommand : 
			'var e = document.createEvent("KeyEvents");' +
			'e.initKeyEvent("keypress",1,1,null,1,0,0,0,13,0);' +
			'current_focus.inputField.dispatchEvent(e);',
		 }
	)
);

tag_menu.appendChild(
	createMenuitem(
		{ label : 'Remove Row',
		  oncommand : 
			'var e = document.createEvent("KeyEvents");' +
			'e.initKeyEvent("keypress",1,1,null,1,0,0,0,46,0);' +
			'current_focus.inputField.dispatchEvent(e);',
		}
	)
);

tag_menu.appendChild( createComplexXULElement( 'separator' ) );



function genToolTips () {
	for (var i in bib_data.field) {
		var f = bib_data.field[i];
	
		tag_menu.appendChild(
			createMenuitem(
				{ label : f.@tag,
				  oncommand : 
				  	'current_focus.value = "' + f.@tag + '";' +
					'var e = document.createEvent("MutationEvents");' +
					'e.initMutationEvent("change",1,1,null,0,0,0,0);' +
					'current_focus.inputField.dispatchEvent(e);',
				  disabled : f.@tag < '010' ? "true" : "false",
				  tooltiptext : f.description }
			)
		);
	
		var i1_popup = createPopup({position : 'after_start', id : 't' + f.@tag + 'i1' });
		context_menus.appendChild( i1_popup );
	
		var i2_popup = createPopup({position : 'after_start', id : 't' + f.@tag + 'i2' });
		context_menus.appendChild( i2_popup );
	
		var sf_popup = createPopup({position : 'after_start', id : 't' + f.@tag + 'sf' });
		context_menus.appendChild( sf_popup );
	
		tooltip_hash['tag' + f.@tag] = f.description;
		for (var j in f.indicator) {
			var ind = f.indicator[j];
			tooltip_hash['tag' + f.@tag + 'ind' + ind.@position + 'val' + ind.@value] = ind.description;
	
			if (ind.@position == 1) {
				i1_popup.appendChild(
					createMenuitem(
						{ label : ind.@value,
						  oncommand : 
				  			'current_focus.value = "' + ind.@value + '";' +
							'var e = document.createEvent("MutationEvents");' +
							'e.initMutationEvent("change",1,1,null,0,0,0,0);' +
							'current_focus.inputField.dispatchEvent(e);',
						  tooltiptext : ind.description }
					)
				);
			}
	
			if (ind.@position == 2) {
				i2_popup.appendChild(
					createMenuitem(
						{ label : ind.@value,
						  oncommand : 
				  			'current_focus.value = "' + ind.@value + '";' +
							'var e = document.createEvent("MutationEvents");' +
							'e.initMutationEvent("change",1,1,null,0,0,0,0);' +
							'current_focus.inputField.dispatchEvent(e);',
						  tooltiptext : ind.description }
					)
				);
			}
		}
	
		for (var j in f.subfield) {
			var sf = f.subfield[j];
			tooltip_hash['tag' + f.@tag + 'sf' + sf.@code] = sf.description;
	
			sf_popup.appendChild(
				createMenuitem(
					{ label : sf.@code,
					  oncommand : 
			  			'current_focus.value = "' + sf.@code + '";' +
						'var e = document.createEvent("MutationEvents");' +
						'e.initMutationEvent("change",1,1,null,0,0,0,0);' +
						'current_focus.inputField.dispatchEvent(e);',
					  tooltiptext : sf.description,
					}
				)
			);
		}
	}
}

var p = createComplexXULElement('popupset');
document.documentElement.appendChild( p );

function getTooltip (target, type) {

	var tt = '';
	if (type == 'subfield')
		tt = 'tag' + target.parentNode.parentNode.parentNode.firstChild.value + 'sf' + target.parentNode.childNodes[1].value;

	if (type == 'ind1')
		tt = 'tag' + target.parentNode.firstChild.value + 'ind1val' + target.value;

	if (type == 'ind2')
		tt = 'tag' + target.parentNode.firstChild.value + 'ind2val' + target.value;

	if (type == 'tag')
		tt = 'tag' + target.parentNode.firstChild.value;

	if (!document.getElementById( tt )) {
		p.appendChild(
			createTooltip(
				{ id : tt,
				  flex : "1",
				  orient : 'vertical',
				  onpopupshown : 'this.width = this.firstChild.boxObject.width + 10; this.height = this.firstChild.boxObject.height + 10;',
				  class : 'tooltip' },
				createDescription({}, document.createTextNode( tooltip_hash[tt] ) )
			)
		);
	}

	target.tooltip = tt;
	return true;
}

function getContextMenu (target, type) {

	var tt = '';
	if (type == 'subfield')
		tt = 't' + target.parentNode.parentNode.parentNode.firstChild.value + 'sf';

	if (type == 'ind1')
		tt = 't' + target.parentNode.firstChild.value + 'i1';

	if (type == 'ind2')
		tt = 't' + target.parentNode.firstChild.value + 'i2';

	target.setAttribute('context', tt);
	return true;
}


