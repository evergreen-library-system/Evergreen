/* --------------------------------------------------------------------- 
	Represents a set of values, an inputWidget collects data and a 
	multi-select displays the data and allows the user to remove items
	--------------------------------------------------------------------- */
function oilsRptSetWidget(args) {
	this.node = args.node;
    this.seedValue = args.value;
	this.inputWidget = new args.inputWidget(args);
    this.readonly = Boolean(args.readonly);
    this.asyncInput = args.async;
	this.dest = elem('select',
		{multiple:'multiple','class':'oils_rpt_small_info_selector'});
    this.dest.disabled = this.readonly;
}

oilsRptSetWidget.prototype.draw = function() {

	this.addButton = elem('input',{type:'submit',value:"Add"})
	this.delButton = elem('input',{type:'submit',value:"Del"})
	this.addButton.disabled = this.readonly;
	this.delButton.disabled = this.readonly;

	var obj = this;
	this.addButton.onclick = function() {
		obj.addDisplayItems(obj.inputWidget.getDisplayValue());
        if (obj.inputWidget instanceof oilsRptTextWidget) {
            // clear the value
            obj.inputWidget.dest.value = '';
        }
	}

	this.delButton.onclick = function(){obj.removeSelected()};

	removeChildren(this.node);

    var this_ = this;
    var post_draw = function() {
        if (this_.seedValue && this_.seedValue.length) {
            if (this_.inputWidget instanceof oilsRptTextWidget) {
                // add each seed value to the input widget, then 
                // propagate the value into our multiselect.
                // when done, clear the value from the text widget.
                dojo.forEach(this_.seedValue, function(val) {
                    this_.inputWidget.dest.value = val;
                    this_.addButton.onclick();
                });
                this_.inputWidget.dest.value = '';

            } else {
                this_.addButton.onclick();
            }
        }
    }

	this.inputWidget.draw(null, post_draw);
	this.node.appendChild(elem('br'))
	this.node.appendChild(this.addButton);
	this.node.appendChild(this.delButton);
	this.node.appendChild(elem('br'))
	this.node.appendChild(this.dest);

    if (!this.asyncInput) post_draw();

}

oilsRptSetWidget.prototype.addDisplayItems = function(list) {
	if( list.constructor != Array ) list = [list];
	for(var i = 0; i < list.length; i++) {
		var item = list[i];

		/* no dupes */
		var exists = false;
		iterate(this.dest.options, 
			function(o){if(o.getAttribute('value') == item.value) {exists = true; return;}});
		if(exists) continue;

		_debug('Inserting SetWidget values ' + js2JSON(item));
		insertSelectorVal(this.dest, -1, item.label, this.objToStr(item.value));
	}
}

oilsRptSetWidget.prototype.removeSelected = function() {
	oilsDelSelectedItems(this.dest);
}

oilsRptSetWidget.prototype.getValue = function() {
	var vals = [];
	var obj = this;
	iterate(this.dest, function(i){vals.push(obj.strToObj(i.getAttribute('value')))});
	return vals;
}

oilsRptSetWidget.prototype.objToStr = function(obj) {
	if( typeof obj == 'string' ) return obj;
	//return ':'+obj.transform+':'+obj.params[0];
	var str = ':'+obj.transform;
	for( var i = 0; i < obj.params.length; i++ ) 
		str += ':' + obj.params[i];
	_debug("objToStr(): built string " + str);
	return str;

}

oilsRptSetWidget.prototype.strToObj = function(str) {
	if( str.match(/^:.*/) ) {
		var parts = str.split(/:/);
		_debug("strToObj(): " + str + ' : ' + parts);
		parts.shift();
		var tform = parts.shift();
		//var tform = str.replace(/^:(.*):.*/,'$1');
		//var param = str.replace(/^:.*:(.*)/,'$1');
		return { transform : tform, params : parts };
	}
	return str;
}


/* --------------------------------------------------------------------- 
	represents a widget that has start and end values.  start and end
	are gathered from start/end widgets
	--------------------------------------------------------------------- */
function oilsRptBetweenWidget(args) {
	this.node = args.node;
	var seedValue = args.value;
	if (seedValue) args.value = seedValue[0];
	this.startWidget = new args.startWidget(args);
	if (seedValue) args.value = seedValue[1];
	this.endWidget = new args.endWidget(args);
}
oilsRptBetweenWidget.prototype.draw = function() {
	removeChildren(this.node);
	this.startWidget.draw();
	this.node.appendChild(elem('hr'));
	this.node.appendChild(elem('div',
		{style:'text-align:center;width:100%;font-weight:bold'},' - And - '));
	this.node.appendChild(elem('hr'));
	this.endWidget.draw();
}
oilsRptBetweenWidget.prototype.getValue = function() {
	return [
		this.startWidget.getValue(),
		this.endWidget.getValue()
	];
}




/* --------------------------------------------------------------------- 
	ATOMIC WIDGETS
	--------------------------------------------------------------------- */


/* --------------------------------------------------------------------- 
	Atomic text input widget
	--------------------------------------------------------------------- */
function oilsRptTextWidget(args) {
	this.node = args.node;
    this.seedValue = args.value;
	this.dest = elem('input',{type:'text',size:12});
    this.dest.disabled = Boolean(args.readonly);
	oilsRptMonitorWidget(this.dest);
}
oilsRptTextWidget.prototype.draw = function() {
	this.node.appendChild(this.dest);
    if (this.seedValue) {
        this.dest.value = this.seedValue;
        this.dest.onchange(); // validation
    }
}

/* returns the "real" value for the widget */
oilsRptTextWidget.prototype.getValue = function() {
	return this.dest.value;
}

/* returns the label and "real" value for the widget */
oilsRptTextWidget.prototype.getDisplayValue = function() {
	return { label : this.getValue(), value : this.getValue() };
}



/* --------------------------------------------------------------------- 
	Atomic bool input widget
	--------------------------------------------------------------------- */
function oilsRptBoolWidget(args) {
	this.node = args.node;
    this.seedValue = args.value;
	this.selector = elem('select');
	insertSelectorVal(this.selector, -1,'True','t');
	insertSelectorVal(this.selector, -1,'False','f');
    this.selector.disabled = Boolean(args.readonly);
}

oilsRptBoolWidget.prototype.draw = function() {
	this.node.appendChild(this.selector);
    if (this.seedValue)  
        setSelector(this.selector, this.seedValue);
}

/* returns the "real" value for the widget */
oilsRptBoolWidget.prototype.getValue = function() {
	return getSelectorVal(this.selector);
}

/* returns the label and "real" value for the widget */
oilsRptBoolWidget.prototype.getDisplayValue = function() {
	var val = getSelectorVal(this.selector);
	var label = 'True';
	if (val == 'f') labal = 'False';
	return { label : label, value : val };
}


/* If you monitor a text widget with this function, it 
	will style the input differently to indicate the
	field needs data.  If a regex is provided, it will
	style the field differently until the data matches 
	the regex.  The style comes from OILS_RPT_INVALID_DATA. */
function oilsRptMonitorWidget(input, regex) {
	addCSSClass(input, OILS_RPT_INVALID_DATA);
	var func = function() {
		var val = input.value;
		if(!val) {
			addCSSClass(input, OILS_RPT_INVALID_DATA);
		} else {
			if( regex ) {
				if( val && val.match(regex) ) 
					removeCSSClass(input, OILS_RPT_INVALID_DATA);
				else
					addCSSClass(input, OILS_RPT_INVALID_DATA);
			} else {
				removeCSSClass(input, OILS_RPT_INVALID_DATA);
			}
		}
	}

	input.onkeyup = func;
	input.onchange = func;
}




/* --------------------------------------------------------------------- 
	Atomic calendar widget
	--------------------------------------------------------------------- */
function oilsRptCalWidget(args) {
	this.node = args.node;
	this.calFormat = args.calFormat;
	this.input = elem('input',{type:'text',size:12});
    this.seedValue = args.value;
    this.input.disabled = Boolean(args.readonly);

	oilsRptMonitorWidget(this.input, args.regex);

	if( args.inputSize ) {
		this.input.setAttribute('size',args.inputSize);
		this.input.setAttribute('maxlength',args.inputSize);
	}
}

oilsRptCalWidget.prototype.draw = function() {
	this.button = DOM.generic_calendar_button.cloneNode(true);
	this.button.id = oilsNextId();
	this.input.id = oilsNextId();

	this.node.appendChild(this.button);
	this.node.appendChild(this.input);
	unHideMe(this.button);

	_debug('making calendar widget with format ' + this.calFormat);

	Calendar.setup({
		inputField	: this.input.id,
		ifFormat		: this.calFormat,
		button		: this.button.id,
		align			: "Tl",	
		singleClick	: true
	});

    if (this.seedValue) {
        this.input.value = this.seedValue;
        this.input.onchange(); // validation
    }
}

oilsRptCalWidget.prototype.getValue = function() {
	return this.input.value;
}

oilsRptCalWidget.prototype.getDisplayValue = function() {
	return { label : this.getValue(), value : this.getValue() };
}


/* --------------------------------------------------------------------- 
	Atomic org widget
	--------------------------------------------------------------------- */
function oilsRptOrgSelector(args) {
	this.node = args.node;
    this.seedValue = args.value;
	this.selector = elem('select',
		{multiple:'multiple','class':'oils_rpt_small_info_selector'});
    this.selector.disabled = Boolean(args.readonly);
}

oilsRptOrgSelector.prototype.draw = function(org) {
	if(!org) org = globalOrgTree;
	var opt = insertSelectorVal( this.selector, -1, 
		org.shortname(), org.id(), null, findOrgDepth(org) );
	if( org.id() == oilsRptCurrentOrg && !this.seedValue)
		opt.selected = true;
	
	/* sometimes we need these choices 
	if( !isTrue(findOrgType(org.ou_type()).can_have_vols()) )
		opt.disabled = true;
		*/

	if( org.children() ) {
		for( var c = 0; c < org.children().length; c++ )
			this.draw(org.children()[c]);
	}
	this.node.appendChild(this.selector);

    if (this.seedValue) {
        if (dojo.isArray(this.seedValue)) {
            for (var i = 0; i < this.selector.options.length; i++) {
                var opt = this.selector.options[i];
                if (this.seedValue.indexOf(opt.value) > -1)
                    opt.selected = true;
            }
        } else {
            setSelector(this.selector, this.seedValue);
        }
    }
}

oilsRptOrgSelector.prototype.getValue = function() {
	var vals = [];
	iterate(this.selector, /* XXX this.selector.options?? */
		function(o){
			if( o.selected )
				vals.push(o.getAttribute('value'))
		}
	);
	return vals;
}

oilsRptOrgSelector.prototype.getDisplayValue = function() {
	var vals = [];
	iterate(this.selector,
		function(o){
			if( o.selected )
				vals.push({ label : o.innerHTML, value : o.getAttribute('value')});
		}
	);
	return vals;
}


/* --------------------------------------------------------------------- 
	Atomic age widget
	--------------------------------------------------------------------- */
function oilsRptAgeWidget(args) {
	this.node = args.node;
    this.seedValue = args.value;
	this.count = elem('select');
	this.type = elem('select');
    this.count.disabled = Boolean(args.readonly);
    this.type.disabled = Boolean(args.readonly);
}

oilsRptAgeWidget.prototype.draw = function() {

	//insertSelectorVal(this.count, -1, ' -- Select One -- ', '');
	for( var i = 1; i < 25; i++ )
		insertSelectorVal(this.count, -1, i, i);

	//insertSelectorVal(this.type, -1, ' -- Select One -- ', '');
	insertSelectorVal(this.type, -1, rpt_strings.WIDGET_DAYS, 'days');
	insertSelectorVal(this.type, -1, rpt_strings.WIDGET_MONTHS, 'months');
	insertSelectorVal(this.type, -1, rpt_strings.WIDGET_YEARS, 'years');
	this.node.appendChild(this.count);
	this.node.appendChild(this.type);

    if (this.seedValue) { 
        // e.g. "2months"
        var count = this.seedValue.match(/(\d+)([^\d]+)/)[1];
        var type = this.seedValue.match(/(\d+)([^\d]+)/)[2];
        setSelector(this.count, count);
        setSelector(this.type, type);
    }
}

oilsRptAgeWidget.prototype.getValue = function() {
	var count = getSelectorVal(this.count);
	var type = getSelectorVal(this.type);
	return count+''+type;
}

oilsRptAgeWidget.prototype.getDisplayValue = function() {
	var val = { value : this.getValue() };
	var label = getSelectorVal(this.count) + ' ';
	for( var i = 0; i < this.type.options.length; i++ ) {
		var opt = this.type.options[i];
		if( opt.selected )
			label += opt.innerHTML;
	}
	val.label = label;
	return val;
}



/* --------------------------------------------------------------------- 
	Atomic substring picker
	--------------------------------------------------------------------- */
function oilsRptSubstrWidget(args) {
	this.node = args.node
    this.seedValue = args.value;
	this.data = elem('input',{type:'text',size:12})
	this.offset = elem('input',{type:'text',size:5})
	this.length = elem('input',{type:'text',size:5})
    this.offset.disabled = Boolean(args.readonly);
    this.length.disabled = Boolean(args.readonly);
}

oilsRptSubstrWidget.prototype.draw = function() {
	this.node.appendChild(text('string: '))
	this.node.appendChild(this.data);
	this.node.appendChild(elem('br'));
	this.node.appendChild(text('offset: '))
	this.node.appendChild(this.offset);
	this.node.appendChild(elem('br'));
	this.node.appendChild(text('length: '))
	this.node.appendChild(this.length);

    if (this.seedValue) { 
        // TODO: unested; substring currently not supported.
        this.data.value = this.seedValue[0];
        this.offset.value = this.seedValue[1];
        this.length.value = this.seedValue[2];
    }
}

oilsRptSubstrWidget.prototype.getValue = function() {
	return {
		transform : 'substring',
		params : [ this.data.value, this.offset.value, this.length.value ]
	};
}

oilsRptSubstrWidget.prototype.getDisplayValue = function() {
	return {
		label : this.data.value + ' : ' + this.offset.value + ' : ' + this.length.value,
		value : this.getValue()
	};
}


/* --------------------------------------------------------------------- 
	Atomic number picker
	--------------------------------------------------------------------- */
function oilsRptNumberWidget(args) {
	this.node = args.node;
    this.seedValue = args.value;
	this.size = args.size || 32;
	this.start = args.start;
	this.selector = elem('select');
    this.selector.disabled = Boolean(args.readonly);
}
oilsRptNumberWidget.prototype.draw = function() {
	//insertSelectorVal(this.selector, -1, ' -- Select One -- ', '');
	for( var i = this.start; i < (this.size + this.start); i++ )
		insertSelectorVal(this.selector, -1, i, i);
	this.node.appendChild(this.selector);
	var obj = this;

    if (this.seedValue)
        setSelector(this.selector, this.seedValue);
}

oilsRptNumberWidget.prototype.getValue = function() {
	return getSelectorVal(this.selector);
}

oilsRptNumberWidget.prototype.getDisplayValue = function() {
	return { label : this.getValue(), value : this.getValue() };
}

function oilsRptNullWidget(args) {
    this.node = args.node;
    this.type = args.type;
}
oilsRptNullWidget.prototype.draw = function() {}
oilsRptNullWidget.prototype.getValue = function() {
    return null;
}

function oilsRptTemplateWidget(args) {
    this.node = args.node;
    this.value = args.value;
}
oilsRptTemplateWidget.prototype.draw = function() {
    this.node.appendChild(text(''+this.value));
}

/* --------------------------------------------------------------------- 
	Relative dates widget
	-------------------------------------------------------------------- */
function oilsRptTruncPicker(args) {
	this.node = args.node;
	this.type = args.type;
    this.seedValue = args.value;
	this.realSpan = elem('span');
	this.relSpan = elem('span');
	hideMe(this.relSpan);
	args.node = this.realSpan;
	this.calWidget = new oilsRptCalWidget(args);
	args.node = this.node;

	this.selector = elem('select');
	insertSelectorVal(this.selector,-1,rpt_strings.WIDGET_REAL_DATE,1);
	insertSelectorVal(this.selector,-1,rpt_strings.WIDGET_RELATIVE_DATE,2);
    this.selector.disabled = Boolean(args.readonly);

	this.numberPicker = 
		new oilsRptNumberWidget(
            {node:this.relSpan,size:90,start:1,readonly:args.readonly});

	this.label = 'Day(s)';
	if(this.type == 'month') this.label = rpt_strings.WIDGET_MONTHS;
	if(this.type == 'quarter') this.label = rpt_strings.WIDGET_QUARTERS;
	if(this.type == 'year') this.label = rpt_strings.WIDGET_YEARS;
	if(this.type == 'date') this.label = rpt_strings.WIDGET_DAYS;
}

oilsRptTruncPicker.prototype.draw = function() {
	this.node.appendChild(this.selector);
	this.node.appendChild(this.realSpan);
	this.node.appendChild(this.relSpan);
	this.calWidget.draw();
	this.numberPicker.draw();
	this.relSpan.appendChild(text(this.label+' ago'));

	var obj = this;
	this.selector.onchange = function() {
		if( getSelectorVal(obj.selector) == 1 ) {
			unHideMe(obj.realSpan);
			hideMe(obj.relSpan);
		} else {
			unHideMe(obj.relSpan);
			hideMe(obj.realSpan);
		}
	}

    if (seed = this.seedValue) {
        if (typeof seed == 'string') {
            this.calWidget.value = seed;
        } else {
            // relative date transform
            if (seed.transform.match(/relative/)) {
                setSelector(this.selector, 2)
                setSelector(this.numberPicker.selector, 
                    Math.abs(seed.params[0]));
			    unHideMe(this.relSpan);
			    hideMe(this.realSpan);
            }
        }
    }
}

oilsRptTruncPicker.prototype.getValue = function() {
	if( getSelectorVal(this.selector) == 2) {
		var val = this.numberPicker.getValue();
		var tform = 'relative_' + this.type;
		return { transform : tform, params : ['-'+val] };
	}
	return this.calWidget.getValue();
}

oilsRptTruncPicker.prototype.getDisplayValue = function() {
	if( getSelectorVal(this.selector) == 2) {
		var num = this.numberPicker.getValue();
		return { label : num +' '+this.label+' ago', value : this.getValue() };
	}
	return this.calWidget.getDisplayValue();
}


/* --------------------------------------------------------------------- 
	Atomic remote object picker
	--------------------------------------------------------------------- */

function oilsRptRemoteWidget(args) {
	this.node	= args.node;
	this.class	= args.class;
	this.field	= args.field;
	this.column = args.column;
    this.seedValue = args.value;
	this.source = elem('select',
		{multiple:'multiple','class':'oils_rpt_small_info_selector'});
    this.source.disabled = Boolean(args.readonly);
}

// selected is unused
oilsRptRemoteWidget.prototype.draw = function(selected, callback) {
	var orgcol;
	iterate(oilsIDL[this.class].fields,
		function(i) {
			if(i.type == 'link' && i.class == 'aou') 
				orgcol = i.name;
		}
	);

	if(orgcol) _debug("found org column for remote widget: " + orgcol);

	var orgs = [];
	iterate(oilsRptMyOrgs,function(i){orgs.push(i.id());});
	var req = new Request(OILS_RPT_MAGIC_FETCH, SESSION, {
		hint:this.class,
		org_column : orgcol,
		org : orgs
	}); 

	var obj = this;
	this.node.appendChild(this.source);
	req.callback(function(r){
        // render selects values from seed data if necessary
        obj.render(r.getResultObject());
        if (callback) {
            // presence of a callback suggests there is a container widget
            // (e.g. SetWidget) for tracking our values.  Callback lets 
            // the container extract the selected values, then we deselect
            // in the input widget (us) since it's redundant.
            callback();
            dojo.forEach(obj.source.options, function(o) {
                o.selected = false;
            });
        }
    });
	req.send();
}

oilsRptRemoteWidget.prototype.render = function(objs) {
	var selector = this.field.selector;
	objs.sort(
		function(a,b){
			if (a[selector]() > b[selector]())
				return 1;
			else
				return -1;
		});
	for( var i = 0; i < objs.length; i++ ) {
		var obj = objs[i];
		var label = obj[this.field.selector]();
		var value = obj[this.column]();
		_debug("inserted remote object "+label + ' : ' + value);
		var opt = insertSelectorVal(this.source, -1, label, value);
        if (this.seedValue && (
                this.seedValue.indexOf(Number(value)) > -1 
                || this.seedValue.indexOf(''+value) > -1
            )) {
            opt.selected = true;
        }
	}
}

oilsRptRemoteWidget.prototype.getDisplayValue = function() {
	var vals = [];
	iterate(this.source,
		function(o){
			if( o.selected )
				vals.push({ label : o.innerHTML, value : o.getAttribute('value')});
		}
	);
	return vals;
}

oilsRptRemoteWidget.prototype.getValue = function() {
	var vals = [];
	iterate(this.source,
		function(o){
			if( o.selected )
				vals.push(o.getAttribute('value'))
		}
	);
	return vals;
}




/* --------------------------------------------------------------------- 
	CUSTOM WIDGETS
	--------------------------------------------------------------------- */

/* --------------------------------------------------------------------- 
	custom my-orgs picker 
	--------------------------------------------------------------------- */
function oilsRptMyOrgsWidget(node, orgid, maxorg) {
	_debug('fetching my orgs with max org of ' + maxorg);
	this.node = node;
	this.orgid = orgid;
	this.maxorg = maxorg || 1;
	this.active = true;
	if( maxorg < 1 ) {
		this.node.disabled = true;
		this.active = false;
	}
}

oilsRptMyOrgsWidget.prototype.draw = function() {
	if(!oilsRptMyOrgs) {
		var req = new Request(OILS_RPT_FETCH_ORG_FULL_PATH, this.orgid);
		var obj = this;
		req.callback(
			function(r) { obj.drawWidget(r.getResultObject()); }
		);
		req.send();
	} else {
		this.drawWidget(oilsRptMyOrgs);
	}
}

oilsRptMyOrgsWidget.prototype.drawWidget = function(orglist) {
	var sel = this.node;
	var started = false;
	oilsRptMyOrgs = orglist;
	for( var i = 0; i < orglist.length; i++ ) {
		var org = orglist[i];
		var opt = insertSelectorVal( this.node, -1, 
			org.name(), org.id(), null, findOrgDepth(org) );
		if( org.id() == this.orgid )
			opt.selected = true;
		if(!started) {
			if( org.id() == this.maxorg ) 
				started = true;
			else opt.disabled = true;
		}
	}
}

oilsRptMyOrgsWidget.prototype.getValue = function() {
	return getSelectorVal(this.node);
}


