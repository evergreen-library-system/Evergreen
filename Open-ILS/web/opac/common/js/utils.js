function $(id) { return getId(id); }
function getId(id) {
	return document.getElementById(id);
}

function swapCSSClass(obj, old, newc ) {
	removeCSSClass(obj, old );
	addCSSClass(obj, newc );
}


function addCSSClass(e,c) {
	if(!e || !c) return;

	var css_class_string = e.className;
	var css_class_array;

	if(css_class_string)
		css_class_array = css_class_string.split(/\s+/);

	var string_ip = ""; /*strip out nulls*/
	for (var css_class in css_class_array) {
		if (css_class_array[css_class] == c) { return; }
		if(css_class_array[css_class] !=null)
			string_ip += css_class_array[css_class] + " ";
	}
	string_ip += c;
	e.className = string_ip;
}

function removeCSSClass(e, c) {
	if(!e || !c) return;

	var css_class_string = '';

	var css_class_array = e.className;
	if( css_class_array )
		css_class_array = css_class_array.split(/\s+/);

	var first = 1;
	for (var css_class in css_class_array) {
		if (css_class_array[css_class] != c) {
			if (first == 1) {
				css_class_string = css_class_array[css_class];
				first = 0;
			} else {
				css_class_string = css_class_string + ' ' +
					css_class_array[css_class];
			}
		}
	}
	e.className = css_class_string;
}


/*returns the character code pressed that caused the event */
function grabCharCode(evt) {
   evt = (evt) ? evt : ((window.event) ? event : null); 
   if( evt ) {
      return (evt.charCode ? evt.charCode : 
         ((evt.which) ? evt.which : evt.keyCode ));
   } else { return -1; }
}       


/* returns true if the user pressed enter */
function userPressedEnter(evt) {
   var code = grabCharCode(evt);
   if(code==13||code==3) return true;
   return false;
}   

/* Using setTimeout in the following function means that goTo is threaded,
   and multiple calls to it will be processed indeterminately.  Since goTo
   should effectively end the page, we will only honor the first call. */
var goToHasRun = false;
function goTo(url) {
	if (goToHasRun) {
		return false;
	}

	goToHasRun = true;
	/* setTimeout because ie sux */
	setTimeout( function(){ location.href = url; }, 0 );
}


function removeChildren(dom) {
	if(!dom) return;
	while(dom.childNodes[0])
		dom.removeChild(dom.childNodes[0]);
}

function appendClear(node, child) {
	if(typeof child =='string') child = text(child);
	removeChildren(node);
	node.appendChild(child);
}


function instanceOf(object, constructorFunction) {

   if(!IE) {
      while (object != null) {
         if (object == constructorFunction.prototype)
            return true;
         object = object.__proto__;
      }
   } else {
      while(object != null) {
         if( object instanceof constructorFunction )
            return true;
         object = object.__proto__;
      }
   }
   return false;
}         


/* ------------------------------------------------------------------------------------------- */
/* detect my browser */
var isMac, NS, NS4, NS6, IE, IE4, IEmac, IE4plus, IE5, IE5plus, IE6, IEMajor, ver4, Safari;
function detect_browser() {       

   isMac = (navigator.appVersion.indexOf("Mac")!=-1) ? true : false;
   NS = (navigator.appName == "Netscape") ? true : false;
   NS4 = (document.layers) ? true : false;
   IE = (navigator.appName == "Microsoft Internet Explorer") ? true : false;
   IEmac = ((document.all)&&(isMac)) ? true : false;
   IE4plus = (document.all) ? true : false;
   IE4 = ((document.all)&&(navigator.appVersion.indexOf("MSIE 4.")!=-1)) ? true : false;
   IE5 = ((document.all)&&(navigator.appVersion.indexOf("MSIE 5.")!=-1)) ? true : false;
   IE6 = ((document.all)&&(navigator.appVersion.indexOf("MSIE 6.")!=-1)) ? true : false;
   ver4 = (NS4 || IE4plus) ? true : false;
   NS6 = (!document.layers) && (navigator.userAgent.indexOf('Netscape')!=-1)?true:false;
   Safari = navigator.userAgent.match(/Safari/);

   IE5plus = IE5 || IE6;
   IEMajor = 0;

   if (IE4plus) {
      var start = navigator.appVersion.indexOf("MSIE");
      var end = navigator.appVersion.indexOf(".",start);
      IEMajor = parseInt(navigator.appVersion.substring(start+5,end));
      IE5plus = (IEMajor>=5) ? true : false;
   }
}  
detect_browser();
/* ------------------------------------------------------------------------------------------- */


function text(t) {
	if(t == null) t = "";
	return document.createTextNode(t);
}

function elem(name, attrs, txt) {
    var e = document.createElement(name);
    if (attrs) {
        for (key in attrs) {
			  if( key == 'id') e.id = attrs[key];
			  else e.setAttribute(key, attrs[key]);
        }
    }
    if (txt) e.appendChild(text(txt));
    return e;
}                   


/* sel is the selector object, sets selected on the 
	option with the given value. case does not matter...*/
function setSelector( sel, value ) {
	if(sel && value != null) {
		for( var i = 0; i!= sel.options.length; i++ ) { 
			if( sel.options[i] ) {
				var val = sel.options[i].value;
				if( val == null || val == "" ) /* for IE */
					val = sel.options[i].innerHTML;
				value += ""; /* in case of number */ 
				if( val && val.toLowerCase() == value.toLowerCase() ) {
					sel.selectedIndex = i;
					sel.options[i].selected = true;
					return true;
				}
			}
		}
	}
	return false;
}

function setSelectorRegex( sel, regex ) {
	if(sel && regex != null) {
		for( var i = 0; i!= sel.options.length; i++ ) { 
			if( sel.options[i] ) {
				var val = sel.options[i].value;
				if( val == null || val == "" ) /* for IE */
					val = sel.options[i].innerHTML;
				value += ""; /* in case of number */ 
				if( val && val.match(regex) ) {
					sel.selectedIndex = i;
					sel.options[i].selected = true;
					return true;
				}
			}
		}
	}
	return false;
}

function getSelectorVal( sel ) {
	if(!sel) return null;
	var idx = sel.selectedIndex;
	if( idx < 0 ) return null;
	var o = sel.options[idx];
	var v = o.value; 
	if(v == null) v = o.innerHTML;
	return v;
}

function getSelectorName( sel ) {
	var o = sel.options[sel.selectedIndex];
	var v = o.name;
	if(v == null || v == undefined || v == "") v = o.innerHTML;
	return v;
}

function setSelectorByName( sel, name ) {
	for( var o in sel.options ) {
		var opt = sel.options[o];
		if( opt.name == name || opt.innerHTML == name ) {
			sel.selectedIndex = o;
			opt.selected = true;
		}
	}
}

function findSelectorOptByValue( sel, val ) {
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		if( opt.value == val ) return opt;
	}
	return null;
}

function debugSelector(sel) {
	var s = 'Selector\n';
	for( var i = 0; i != sel.options.length; i++ ) {
		var o = sel.options[i];
		s += "\t" + o.innerHTML + "\n";
	}
	return s;
}

function findParentByNodeName(node, name) {
	while( ( node = node.parentNode) ) 
		if (node.nodeName == name) return node;
	return null;
}

/* returns only elements in nodes childNodes list, not sub-children */
function getElementsByTagNameFlat( node, name ) {
	var elements = [];
	for( var e in node.childNodes ) {
		var n = node.childNodes[e];
		if( n && n.nodeName == name ) elements.push(n);
	}
	return elements;
}

/* expects a tree with a id() method on each node and a 
children() method to get to each node */
function findTreeItemById( tree, id ) {
	if( tree.id() == id ) return tree;
	for( var c in tree.children() ) {
		var found = findTreeItemById( tree.children()[c], id );
		if(found) return found;
	}
	return null;
}

/* returns null if none of the tests are true.  returns sub-array of 
matching array items otherwise */
function grep( arr, func ) {
	var results = [];
	if(!arr) return null;
	if( arr.constructor == Array ) {
		for( var i = 0; i < arr.length; i++ ) {
			if( func(arr[i]) ) 
				results.push(arr[i]);
		}
	} else {
		for( var i in arr ) {
			if( func(arr[i]) ) 
				results.push(arr[i]);
		}
	}
	if(results.length > 0) return results;
	return null;
}

function ogrep( obj, func ) {
	var results = {};
	var found = false;
	for( var i in obj ) {
		if( func(obj[i]) ) {
			results[i] = obj[i];
			found = true;
		}
	}
	if(found) return results;
	return null;
}

function doSelectorActions(sel) {
	if((IE || Safari) && sel) { 
		sel.onchange = function() {
			var o = sel.options[sel.selectedIndex];
			if(o && o.onclick) o.onclick()
		}
	}
}

/* if index < 0, the item is pushed onto the end */
function insertSelectorVal( selector, index, name, value, action, indent ) {
	if( index < 0 ) index = selector.options.length;
	var a = [];
	for( var i = selector.options.length; i != index; i-- ) 
		a[i] = selector.options[i-1];

	var opt = setSelectorVal( selector, index, name, value, action, indent );

	for( var i = index + 1; i < a.length; i++ ) 
		selector.options[i] = a[i];

	return opt;
}

/* changes the value of the option at the specified index */
function setSelectorVal( selector, index, name, value, action, indent ) {
	if(!indent || indent < 0) indent = 0;
	indent = parseInt(indent);

	var option;

	if(IE) {
		var pre = elem("pre");
		for( var i = 0; i != indent; i++ )
			pre.appendChild(text("   "));

		pre.appendChild(text(name));
		option = new Option("", value);
		selector.options[index] = option;
		option.appendChild(pre);
	
	} else {
		indent = indent * 14;
		option= new Option(name, value);
		option.setAttribute("style", "padding-left: "+indent+'px;');
		selector.options[index] = option;
		if(action) option.onclick = action;
	}

	if(action) option.onclick = action;
	return option;
}


/* split on spaces.  capitalize the first /\w/ character in
   each substring */
function normalize(val) {
	return val; /* disable me for now */

   if(!val) return ""; 

   var newVal = '';
   try {val = val.split(' ');} catch(E) {return val;}
   var reg = /\w/;

   for( var c = 0; c < val.length; c++) {

      var string = val[c];
      var cap = false; 
      for(var x = 0; x != string.length; x++) {

         if(!cap) {
            var ch = string.charAt(x);
            if(reg.exec(ch + "")) {
               newVal += string.charAt(x).toUpperCase();
               cap = true;
               continue;
            }
         }

         newVal += string.charAt(x).toLowerCase();
      }
      if(c < (val.length-1)) newVal += " ";
   }

   newVal = newVal.replace(/\s*\.\s*$/,'');
   newVal = newVal.replace(/\s*\/\s*\/\s*$/,' / ');
   newVal = newVal.replace(/\s*\/\s*$/,'');

   return newVal;
}


/* returns true if n is null or stringifies to 'undefined' */
function isNull(n) {
	if( n == null || n == undefined || n.toString().toLowerCase() == "undefined" 
		|| n.toString().toLowerCase() == "null" )
		return true;
	return false;
}


/* find nodes with an attribute of 'name' that equals nodeName */

function $n( root, nodeName ) { return findNodeByName(root,nodeName); }

function findNodeByName(root, nodeName) {
	if( !root || !nodeName) return null;

	if(root.nodeType != 1) return null;

	if(root.getAttribute("name") == nodeName || root.name == nodeName ) 
		return root;

	var children = root.childNodes;

	for( var i = 0; i != children.length; i++ ) {
		var n = findNodeByName(children[i], nodeName);
		if(n) return n;
	}

	return null;
}


/* truncates the string at 'size' characters and appends a '...' to the end */
function truncate(string, size) {
	if(string && size != null && 
			size > -1 && string.length > size) 
		return string.substr(0, size) + "... "; 
	return string;
}


/* style sheets must have a 'name' attribute for these functions to work */
function setActivateStyleSheet(name) {
	var i, a, main;
	for (i = 0; (a = document.getElementsByTagName ("link")[i]); i++) {
		if (a.getAttribute ("rel").indexOf ("style") != -1 && a.getAttribute ("name")) {
			a.disabled = true;
			if (a.getAttribute ("name").indexOf(name) != -1)
				a.disabled = false;
		}
	}
}


/* ----------------------------------------------------- */
var currentFontSize;
function scaleFonts(type) {

	var size		= "";
	var ssize	= "";
	var size2	= "";
	var a;
	
	if(!currentFontSize) currentFontSize = 'regular';
	if(currentFontSize == 'regular' && type == 'regular' ) return;
	if( currentFontSize == type ) return;
	currentFontSize = type;

	switch(type) {
		case "large":  /* these are arbitrary.. but they seem to work ok in FF/IE */
			size = "142%"; 
			size2 = "107%"; 
			ssize = "94%";
			break;
	}

	document.getElementsByTagName('body')[0].style.fontSize = size;
	for (i = 0; (a = document.getElementsByTagName ("td")[i]); i++) a.style.fontSize = size;;
	for (i = 0; (a = document.getElementsByTagName ("div")[i]); i++) a.style.fontSize = ssize;
	for (i = 0; (a = document.getElementsByTagName ("option")[i]); i++) a.style.fontSize = ssize;
	for (i = 0; (a = document.getElementsByTagName ("li")[i]); i++) a.style.fontSize = ssize;
	for (i = 0; (a = document.getElementsByTagName ("span")[i]); i++) a.style.fontSize = ssize;
	for (i = 0; (a = document.getElementsByTagName ("select")[i]); i++) a.style.fontSize = ssize;
	for (i = 0; (a = document.getElementsByTagName ("a")[i]); i++) a.style.fontSize = size2;
}


function sortWordsIgnoreCase(a, b) {
	a = a.toLowerCase();
	b = b.toLowerCase();
	if(a>b) return 1;
	if(a<b) return -1;
	return 0;
}


function getSelectedList(sel) {
	if(!sel) return [];
	var vals = [];
	for( var i = 0; i != sel.options.length; i++ ) {
		if(sel.options[i].selected)
			vals.push(sel.options[i].value);
	}
	return vals;
}


function setEnterFunc(node, func) {
	if(!(node && func)) return;
	node.onkeydown = function(evt) {
		if( userPressedEnter(evt)) func();
	}
}

function iterate( arr, callback ) {
	for( var i = 0; arr && i < arr.length; i++ ) 
		callback(arr[i]);
}




/* taken directly from the JSAN util.date library */
/* but changed from the util.date.interval_to_seconds invocation, 
because JSAN will assume the whole library is already loaded if 
it sees that, and the staff client uses both this file and the
JSAN library*/
function interval_to_seconds( $interval ) {

	$interval = $interval.replace( /and/, ',' );
	$interval = $interval.replace( /,/, ' ' );
	
	var $amount = 0;
	var results = $interval.match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/g);  
	for( var i = 0; i < results.length; i++ ) {
		if(!results[i]) continue;
		var result = results[i].match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/ );
		if (result[2] == 's') $amount += result[1] ;
		if (result[2] == 'm') $amount += 60 * result[1] ;
		if (result[2] == 'h') $amount += 60 * 60 * result[1] ;
		if (result[2] == 'd') $amount += 60 * 60 * 24 * result[1] ;
		if (result[2] == 'w') $amount += 60 * 60 * 24 * 7 * result[1] ;
		if (result[2] == 'M') $amount += ((60 * 60 * 24 * 365)/12) * result[1] ;
		if (result[2] == 'y') $amount += 60 * 60 * 24 * 365 * result[1] ;
	}
	return $amount;
}


function openWindow( data ) {
	if( isXUL() ) {
		var data = window.escape(
			'<html><head><title></title></head><body>' + data + '</body></html>');

		xulG.window_open(
			'data:text/html,' + data,
			'', 
			'chrome,resizable,width=700,height=500'); 

	} else {
		win = window.open('','', 'resizable,width=700,height=500,scrollbars=1,chrome'); 
		win.document.body.innerHTML = data;
	}
}


/* alerts the innerhtml of the node with the given id */
function alertId(id) {
	var node = $(id);
	if(node) alert(node.innerHTML);
}

function alertIdText(id, text) {
	var node = $(id);
   if(!node) return;
   if(text)
      alert(text + '\n\n' + node.innerHTML);
   else 
	   alert(node.innerHTML);
}

function confirmId(id) {
	var node = $(id);
	if(node) return confirm(node.innerHTML);
}


function goBack() { history.back(); }
function goForward() { history.forward(); }


function uniquify(arr) {
	if(!arr) return [];
	var newarr = [];
	for( var i = 0; i < arr.length; i++ ) {
		var item = arr[i];
		if( ! grep( newarr, function(x) {return (x == item);}))
			newarr.push(item);
	}
	return newarr;
}

function contains(arr, item) {
	for( var i = 0; i < arr.length; i++ ) 
		if( arr[i] == item ) return true;
	return false;
}

function isTrue(i) {
	return (i && !(i+'').match(/f/i) );
}


/* builds a JS date object with the given info.  The given data
	has to be valid (e.g. months == 30 is not valid).  Returns NULL on 
	invalid date 
	Months are 1-12 (unlike the JS date object)
	*/

function buildDate( year, month, day, hours, minutes, seconds ) {

	if(!year) year = 0;
	if(!month) month = 1;
	if(!day) day = 1;
	if(!hours) hours = 0;
	if(!minutes) minutes = 0;
	if(!seconds) seconds = 0;

	var d = new Date(year, month - 1, day, hours, minutes, seconds);
	
	_debug('created date with ' +
		(d.getYear() + 1900) +'-'+
		(d.getMonth() + 1) +'-'+
		d.getDate()+' '+
		d.getHours()+':'+
		d.getMinutes()+':'+
		d.getSeconds());


	if( 
		(d.getYear() + 1900) == year &&
		d.getMonth()	== (month - 1) &&
		d.getDate()		== new Number(day) &&
		d.getHours()	== new Number(hours) &&
		d.getMinutes() == new Number(minutes) &&
		d.getSeconds() == new Number(seconds) ) {
		return d;
	}

	return null;
}

function mkYearMonDay(date) {
	if(!date) date = new Date();
	var y = date.getYear() + 1900;
	var m = (date.getMonth() + 1)+'';
	var d = date.getDate()+'';
	if(m.length == 1) m = '0'+m;
	if(d.length == 1) d = '0'+d;
	return y+'-'+m+'-'+d;
}


function debugFMObject(obj) {
	if(typeof obj != 'object' ) return obj;
	_debug("---------------------");
	var keys = fmclasses[obj.classname];
	if(!keys) { _debug(formatJSON(js2JSON(obj))); return; }

	keys.sort();
	for( var i = 0; i < keys.length; i++ ) {
		var key = keys[i];
		while( key.length < 12 ) key += ' ';
		var val = obj[keys[i]]();
		if( typeof val == 'object' ) {
			_debug(key+' :=\n');
			_debugFMObject(val);
		} else {
			_debug(key+' = ' +val);
		}

	}
	_debug("---------------------");
}


function getTableRows(tbody) {
    var rows = [];
    if(!tbody) return rows;

    var children = tbody.childNodes;
    if(!children) return rows;

    for(var i = 0; i < children.length; i++) {
        var child = children[i];
        if(child.nodeName.match(/^tr$/i)) 
            rows.push(child);
    }
    return rows;
}

function getObjectKeys(obj) {
    keys = []
    for(var k in obj)
        keys.push(k)
    return keys;
}
