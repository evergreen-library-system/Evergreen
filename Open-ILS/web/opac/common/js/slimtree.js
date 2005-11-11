var stpicopen	= '../../../images/slimtree/folder.gif';
var stpicclose = '../../../images/slimtree/folderopen.gif';
var stpicblank = '../../../images/slimtree/page.gif';
var stpicline	= '../../../images/slimtree/line.gif';
var stpicjoin	= '../../../images/slimtree/join.gif';
var stpicjoinb = '../../../images/slimtree/joinbottom.gif';

var stimgopen	= elem('img',{src:stpicopen,border:0});
var stimgclose	= elem('img',{src:stpicclose,border:0});
var stimgblank	= elem('img',{src:stpicblank,border:0});
var stimgline	= elem('img',{src:stpicline,border:0});
var stimgjoin	= elem('img',{src:stpicjoin,border:0, style:'display:inline;'});

function _apc(root,node) { root.appendChild(node); }

function SlimTree(context, handle, rootimg) { 
	this.context	= context; 
	this.handle		= handle;
	this.cache		= new Object();
	if(rootimg) 
		this.rootimg = elem('img', {src:rootimg,border:0,style:'padding-right: 4px;'});
}

SlimTree.prototype.cacheMe = function( id, pid, name, action, title ) {
	if(this.cache[id]) return;
	this.cache[id]				= {};
	this.cache[id].pid		= pid
	this.cache[id].name		= name
	this.cache[id].action	= action
	this.cache[id].title		= title
}

SlimTree.prototype.flushCache = function() {
	for( var c in this.cache ) {
		var obj = this.cache[c];
		if(obj && getId(obj.pid)) {
			this.cache[c] = null;
			this.addNode(c,obj.pid, obj.name, obj.action,obj.title);
		}
	}
}

SlimTree.prototype.addNode = function( id, pid, name, action, title ) {

	if( pid != -1 && !getId(pid)) {
		if(this.cache[pid]) {
			var obj = this.cache[pid];
			this.addNode(pid, obj.pid,obj.name, obj.action,obj.title );
			this.cache[pid] = null;
		} else {
			this.cacheMe(id, pid, name, action, title);
			return;
		}
	}

	var div			= elem('div',{id:id});
	var topdiv		= elem('div',{style:'vertical-align:middle'});
	var link			= elem('a', {id:'stlink_' + id}); 
	var actionref	= elem('a',{href:action}, name);
	var contdiv		= elem('div',{id:'stcont_' + id});
	if(action) actionref.setAttribute('href',action);
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
		getId(pid).setAttribute('haschild','1');
		_apc(link,stimgblank.cloneNode(true));
		div.style.paddingLeft = '18px';
		div.style.backgroundImage = 'url('+stpicjoinb+')';
		div.style.backgroundRepeat = 'no-repeat';
		_apc(getId('stcont_' + pid), div);
		if (div.previousSibling) stMakePaths(div);
	}
	this.flushCache();
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
	var n = getId('stcont_' + id);
	for( var c = 0; c != n.childNodes.length; c++ ) {
		var ch = n.childNodes[c];
		if(ch.nodeName.toLowerCase() == 'div') {
			if(getId(ch.id).getAttribute('haschild') == '1') 
				this.flex(ch.id, type);
		}
	}
}

SlimTree.prototype.open = function(id) {
	var link = getId('stlink_' + id);
	if(id != this.rootid || !this.rootimg) {
		removeChildren(link);
		_apc(link,stimgclose.cloneNode(true));
	}
	link.setAttribute('href','javascript:' + this.handle + '.close("'+id+'");');
	unHideMe(getId('stcont_' + id));
}

SlimTree.prototype.close = function(id) {
	var link = getId('stlink_' + id);
	if(id != this.rootid || !this.rootimg) {
		removeChildren(link);
		_apc(link,stimgopen.cloneNode(true));
	}
	link.setAttribute('href','javascript:' + this.handle + '.open("'+id+'");');
	hideMe(getId('stcont_' + id));
}

