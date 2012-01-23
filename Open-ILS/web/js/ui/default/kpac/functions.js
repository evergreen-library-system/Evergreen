
function __$(str) { return document.getElementById(str); }
function attachEvt(type, el, evt) { // object, function
	if(window.addEventListener) {
	  if(type.toLowerCase()=='mousewheel') el.addEventListener('DOMMouseScroll', evt, false);
	  el.addEventListener(type, evt, false);  // standard event attaching
	}
	else if(window.attachEvent) el.attachEvent('on'+type, evt);  // IE 5+
	else el['on'+type] = evt;  // if all else fails...
}

function getElementsByClass(str, parent) {
	var arr = [];
	var p = parent || document;
	var els = p.getElementsByTagName("*");
	var len = els.length;
	
	for(var i=0; i<len; i++) {
		var it = els.item(i);
		if(typeof it.className != "undefined" && it.className.indexOf(str) >= 0)
			arr.push(it);
	}
	
	return arr;
}


function helpPopup(str, target, evt) {
	var el = __$(str); if(!el || !target) return;
	var maxWidth = 400;
	
	if(el.style.display!="none" && el.style.display!="") {
		el.style.display="none";
		el.style.top = "0px";
		el.style.left= "0px";
		el.parentNode.style.zIndex="-1";
		return;
	}
	
	var src = evt.target || evt.srcElement;
	var sTop = document.documentElement.scrollTop;
	var sLeft = document.documentElement.scrollLeft;
	el.style.display="block";
	
	var content = getElementsByClass("popup_content", el);
	if(content[0].offsetWidth>maxWidth) content[0].style.width=maxWidth+"px";
	
	var elRect = el.getBoundingClientRect();
	var tRect = target.getBoundingClientRect();
	var elWidth = el.offsetWidth;
	var elHeight = el.offsetHeight;
	var tWidth = target.offsetWidth;
	var tHeight = target.offsetHeight;
	
	var top = tRect.top - elRect.top - elHeight + 10;
	var left = tRect.left - elRect.left - (elWidth/2 - (tWidth/2));

	el.style.top = top+"px";
	el.style.left= left+"px";
	el.parentNode.style.zIndex = "100000";
	el.origSrc = src;
}

function bodyClick(evt) {
// hide any visible help popups
	var popups = getElementsByClass("popup_wrapper_inner");
	var len = popups.length;
	var src = evt.target || evt.srcElement;
	
	for(var i=0; i<len; i++) {
		var it = popups[i];
		if(it.origSrc && it.origSrc!=src) {
			it.style.display="none";
			it.style.top = "0px";
			it.style.left= "0px";
			it.parentNode.style.zIndex="-1";
		}
	}
}

attachEvt('click', document, bodyClick);

