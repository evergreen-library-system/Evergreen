/*
var stpicopen	= '../../../../images/slimtree/folder.gif';
var stpicclose = '../../../../images/slimtree/folderopen.gif';
*/
var stpicopen	= '../../../../images/slimtree/folder2.gif';
var stpicclose = '../../../../images/slimtree/folderopen2.gif';
var stpicblank = '../../../../images/slimtree/page.gif';
var stpicline	= '../../../../images/slimtree/line.gif';
var stpicjoin	= '../../../../images/slimtree/join.gif';
var stpicjoinb = '../../../../images/slimtree/joinbottom.gif';

var stimgopen;
var stimgclose;
var stimgblank;
var stimgline;
var stimgjoin;

function _apc(root,node) { root.appendChild(node); }

function SlimTree(context, handle, rootimg) { 
	
	if(!stimgopen) {
		stimgopen       = elem('img',{src:stpicopen,border:0, style:'height:13px;width:31px;'});
		stimgclose      = elem('img',{src:stpicclose,border:0, style:'height:13px;width:31px;'});
		stimgblank      = elem('img',{src:stpicblank,border:0, style:'height:18px;width:18px;'});
		stimgline       = elem('img',{src:stpicline,border:0, style:'height:18px;width:18px;'});
		stimgjoin       = elem('img',{src:stpicjoin,border:0, style:'display:inline;height:18px;width:18px;'});
	}

	this.context	= context; 
	this.handle		= handle;
	this.cache		= new Object();
	if(rootimg) 
		this.rootimg = elem('img', 
			{src:rootimg,border:0,style:'padding-right: 4px;'});
}

SlimTree.prototype.addCachedChildren = function(pid) {
	var child;
	while( child = this.cache[pid].shift() ) 
		this.addNode( child.id, child.pid, 
			child.name, child.action, child.title );
	this.cache[pid] = null;
}

SlimTree.prototype.addNode = function( id, pid, name, action, title, cls ) {

	if( pid != -1 && !$(pid)) {
		if(!this.cache[pid]) this.cache[pid] = new Array();
		this.cache[pid].push(
			{id:id,pid:pid,name:name,action:action,title:title });
		return;
	}

	if(!action)
		action='javascript:'+this.handle+'.toggle("'+id+'");';

	var actionref;
	if( typeof action == 'string' )
		actionref = elem('a',{href:action}, name);
	else {
		actionref = elem('a',{href:'javascript:void(0);'}, name);
		actionref.onclick = action;
	}

	var div			= elem('div',{id:id});
	var topdiv		= elem('div',{style:'vertical-align:middle'});
	var link			= elem('a', {id:'stlink_' + id}); 
	var contdiv		= elem('div',{id:'stcont_' + id});

	if(cls) addCSSClass(actionref, cls);

	//actionref.setAttribute('href',action);
	if(title) actionref.setAttribute('title',title);
	else actionref.setAttribute('title',name);

	_apc(topdiv,link);
	_apc(topdiv,actionref);
	_apc(div,topdiv);
	_apc(div,contdiv);

	if( pid == -1 ) { 

		this.rootid = id;
		_apc(this.context,div);
		if(this.rootimg) _apc(link,this.rootimg.cloneNode(true));
		else _apc(link,stimgblank.cloneNode(true));

	} else {

		if(pid == this.rootid) this.open(pid);
		else this.close(pid);
		$(pid).setAttribute('haschild','1');
		_apc(link,stimgblank.cloneNode(true));
		div.style.paddingLeft = '18px';
		div.style.backgroundImage = 'url('+stpicjoinb+')';
		div.style.backgroundRepeat = 'no-repeat';
		_apc($('stcont_' + pid), div);
		if (div.previousSibling) stMakePaths(div);
	}
	if(this.cache[id]) this.addCachedChildren(id);
}

function stMakePaths(div) {
	_apc(div.previousSibling.firstChild,stimgjoin.cloneNode(true));
	_apc(div.previousSibling.firstChild,div.previousSibling.firstChild.firstChild);
	_apc(div.previousSibling.firstChild,div.previousSibling.firstChild.firstChild);
	div.previousSibling.firstChild.firstChild.style.marginLeft = '-18px';
	div.previousSibling.style.backgroundImage = 'url('+stpicline+')';
	div.previousSibling.style.backgroundRepeat = 'repeat-y';
}

SlimTree.prototype.expandAll = function() { this.flex(this.rootid, 'open'); }
SlimTree.prototype.closeAll = function() { this.flex(this.rootid,'close'); }
SlimTree.prototype.flex = function(id, type) {
	if(type=='open') this.open(id);
	else { if (id != this.rootid) this.close(id); }
	var n = $('stcont_' + id);
	for( var c = 0; c != n.childNodes.length; c++ ) {
		var ch = n.childNodes[c];
		if(ch.nodeName.toLowerCase() == 'div') {
			if($(ch.id).getAttribute('haschild') == '1') 
				this.flex(ch.id, type);
		}
	}
}

SlimTree.prototype.toggle = function(id) {
	if($(id).getAttribute('ostate') == '1') this.open(id);
	else if($(id).getAttribute('ostate') == '2') this.close(id);
}

SlimTree.prototype.open = function(id) {
	if($(id).getAttribute('ostate') == '2') return;
	var link = $('stlink_' + id);
	if(!link) return;
	if(id != this.rootid || !this.rootimg) {
		removeChildren(link);
		_apc(link,stimgclose.cloneNode(true));
	}
	link.setAttribute('href','javascript:' + this.handle + '.close("'+id+'");');
	unHideMe($('stcont_' + id));
	$(id).setAttribute('ostate','2');
}

SlimTree.prototype.close = function(id) {
	var link = $('stlink_' + id);
	if(!link) return;
	if(id != this.rootid || !this.rootimg) {
		removeChildren(link);
		_apc(link,stimgopen.cloneNode(true));
	}
	link.setAttribute('href','javascript:' + this.handle + '.open("'+id+'");');
	hideMe($('stcont_' + id));
	$(id).setAttribute('ostate','1');
}

