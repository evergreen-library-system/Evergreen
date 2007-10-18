// Constants ...
load_lib('phys_char.js');
load_lib('fixed_fields.js');
load_lib('JSON_v1.js');

function recordType (rec) {

	var marcns = new Namespace("http://www.loc.gov/MARC21/slim");
	var _l = rec.marcns::leader.toString();

	var _t = _l.substr(ff_pos.Type.ldr.BKS.start, ff_pos.Type.ldr.BKS.len);
	var _b = _l.substr(ff_pos.BLvl.ldr.BKS.start, ff_pos.BLvl.ldr.BKS.len);

	for (var t in rec_type) {
		if (_t.match(rec_type[t].Type) && _b.match(rec_type[t].BLvl)) {
			return t;
		}
	}
}

function videorecordingFormatName (rec) {
	var marcns = new Namespace("http://www.loc.gov/MARC21/slim");
	var _7 = rec.marcns::controlfield.(@tag.match(/007/)).text().toString();

	if (_7.match(/^v/)) {
		var _v_e = _7.substr(
			physical_characteristics.v.subfields.e.start,
			physical_characteristics.v.subfields.e.len
		);

		return physical_characteristics.v.subfields.e.values[ _v_e ];
	}

	return null;
}

function videorecordingFormatCode (rec) {
	var marcns = new Namespace("http://www.loc.gov/MARC21/slim");
	var _7 = rec.marcns::controlfield.(@tag.match(/007/)).text().toString();

	if (_7.match(/^v/)) {
		return _7.substr(
			physical_characteristics.v.subfields.e.start,
			physical_characteristics.v.subfields.e.len
		);
	}

	return null;
}


function extractFixedField (rec, field) {

	var marcns = new Namespace("http://www.loc.gov/MARC21/slim");
	var _l = rec.marcns::leader.toString();
	var _8 = rec.marcns::controlfield.(@tag.match(/008/)).text().toString();
	var _6 = rec.marcns::controlfield.(@tag.match(/006/)).text().toString();

	var rtype = recordType(rec);

	var val;

	if (ff_pos[field].ldr) {
		if (ff_pos[field].ldr[rtype]) {
			val = _l.substr(
				ff_pos[field].ldr[rtype].start,
				ff_pos[field].ldr[rtype].len
			);
		}
	} else if (ff_pos[field]._8) {
		if (ff_pos[field]._8[rtype]) {
			val = _8.substr(
				ff_pos[field]._8[rtype].start,
				ff_pos[field]._8[rtype].len
			);
		}
	}

	if (!val && ff_pos[field]._6) {
		if (ff_pos[field]._6[rtype]) {
			val = _6.substr(
				ff_pos[field]._6[rtype].start,
				ff_pos[field]._6[rtype].len
			);
		}
	}
		
	return val;
}

