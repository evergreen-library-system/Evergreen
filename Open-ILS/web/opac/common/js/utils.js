function getId(id) {
	return document.getElementById(id);
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
	string_ip = string_ip + c;
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


function goTo(url) {location.href = url;}


function removeChildren(dom) {
	if(!dom) return;
	while(dom.childNodes[0])
		dom.removeChild(dom.childNodes[0]);
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
var isMac, NS, NS4, NS6, IE, IE4, IE4mac, IE4plus, IE5, IE5plus, IE6, IEMajor, ver4;
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

function elem(name, attrs, text) {
    var e = createAppElement(name);
    if (attrs) {
        for (key in attrs) {
			  if( key == 'id') e.id = attrs[key];
			  else e.setAttribute(key, attrs[key]);
        }
    }
    if (text) e.appendChild(text(text));
    return e;
}                   


/* sel is the selector object, sets selected on the 
	option with the given value. case does not matter...*/
function setSelector( sel, value ) {
	if(sel && value != null) {
		for( var i = 0; i!= sel.options.length; i++ ) { 
			if( sel.options[i] ) {
				var val = sel.options[i].value;
				value += ""; /* in case of number */ 
				if( val && val.toLowerCase() == value.toLowerCase() ) {
					sel.selectedIndex = i;
					sel.options[i].selected = true;
				}
			}
		}
	}
}


/* split on spaces.  capitalize the first /\w/ character in
   each substring */
function normalize(val) {

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
	if( n == null || n.toString().toLowerCase() == "undefined" 
		|| n.toString().toLowerCase() == "null" )
		return true;
	return false;
}


/* find nodes with an attribute of 'name' that equals nodeName */

function findNodeByName(root, nodeName) {
	if( !root || !nodeName) return null;

	if(root.nodeType != 1) return null;

	if(root.getAttribute("name") == nodeName ||
			root.name == nodeName ) {
		return root;
	}

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
function scaleFonts(type) {

	var size = "";
	switch(type) {
		case "large": size = "113%"; break;
		case "small": size = "87%"; break;
	}

	document.body.style.fontSize = size;
	for (i = 0; (a = document.getElementsByTagName ("table")[i]); i++) a.style.fontSize = size;
}


function sortWordsIgnoreCase(a, b) {
	a = a.toLowerCase();
	b = b.toLowerCase();
	if(a>b) return 1;
	if(a<b) return -1;
	return 0;
}






