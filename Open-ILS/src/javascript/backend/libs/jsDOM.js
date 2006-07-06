try {
	load_lib('jsOO.js')
	load_lib('xpath.js')
} catch (e) {}

function DOMException  (c) { this.code = c }
DOMException.INDEX_SIZE_ERR = 1;
DOMException.DOMSTRING_SIZE_ERR = 2;
DOMException.HIERARCHY_REQUEST_ERR = 3;
DOMException.WRONG_DOCUMENT_ERR = 4;
DOMException.INVALID_CHARACTER_ERR = 5;
DOMException.NO_DATA_ALLOWED_ERR = 6;
DOMException.NO_MODIFICATION_ALLOWED_ERR = 7;
DOMException.NOT_FOUND_ERR = 8;
DOMException.NOT_SUPPORTED_ERR = 9;
DOMException.INUSE_ATTRIBUTE_ERR = 10;
DOMException.INVALID_STATE_ERR = 11;
DOMException.SYNTAX_ERR = 12;
DOMException.INVALID_MODIFICATION_ERR = 13;
DOMException.NAMESPACE_ERR = 14;
DOMException.INVALID_ACCESS_ERR = 15;

function DOMImplementation () {
	this._features = {};
	this._features['CORE'] = {};
	this._features['CORE']['any'] = true;
	this._features['CORE']['1.0'] = true;
	this._features['CORE']['2.0'] = true;
	this._features['XML'] = {};
	this._features['XML']['any'] = true;
	this._features['XML']['1.0'] = true;
	this._features['XML']['2.0'] = true;
}

DOMImplementation.method('hasFeature', function (f, v) {
	if (!v) v = 'any';
	if (this._features[f] && this._features[f][v])
		return this._features[f][v];
	return false;
});
DOMImplementation.method('createDocumentType', function (n, p, s) {
	return null;
});
DOMImplementation.method('createDocument', function (ns,qn,dt) {
	var d = new Document(dt);
	d.documentElement = d.createElement(qn);
	d.appendChild(d.documentElement);
	if (ns)
		d.documentElement.namespaceURI = ns;

	installDOM3XPathSupport(d,new XPathParser());
	return d;
});

var __XMLDOC = {};
var __XMLDOCid = 0;
DOMImplementation.parseString = function (xml) {
	__XMLDOC['id' + __XMLDOCid] = {};
	try {
		_OILS_FUNC_xml_parse_string(xml, '__XMLDOC.id' + __XMLDOCid);
	} catch (e) {
		alert("Sorry, no string parsing support");
	}
	var x = __XMLDOC['id' + __XMLDOCid];
	__XMLDOCid++;
	return x;
}


// NodeList interface
function NodeList () {
	this.length = 0;
	//log_stdout(' --  NodeList constructor');
}

NodeList.method('item', function (idx) {
	return this[idx];
});
NodeList.method('push', function (node) {
	var idx = this.length;
	this[idx] = node;
	this.length++;
	return this[idx];
});




// NamedNodeMap interface
function NamedNodeMap () {
	this.length = 0;
	this._nodes = {};
	this._ns_nodes = {};
	//log_stdout(' --  NamedNodeMap constructor');
}

NamedNodeMap.method('item', function (idx) {
	return this.getNamedItem(idx);
});

NamedNodeMap.method('removeNamedItemNS', function (ns, name) {
	var x = this._ns_nodes[ns][name];
	for (var i in this._nodes) {
		if (this._nodes[i] === x) {
			this._nodes[i] = null;
		}
	}
	this._ns_nodes[ns][name] = null;
	return x;
});

NamedNodeMap.method('removeNamedItem', function (name) {
	var x = this._nodes[name];
	for (var i in this._nodes) {
		if (this._nodes[i] === x) {
			this._nodes[i] = null;
		}
	}
	return x;
});

NamedNodeMap.method('getNamedItem', function (name) {
	return this._nodes[name];
});

NamedNodeMap.method('getNamedItemNS', function (ns,name) {
	return this._ns_nodes[ns][name];
});

NamedNodeMap.method('setNamedItem', function (node) {
	if (node.nodeName == 'length') return null;
	this[node.nodeName] = node.value;
	this[this.length] = node.value;
	this._nodes[node.nodeName] = node;
	this._nodes[this.length] = node;
	this.length++;
});

NamedNodeMap.method('setNamedItemNS', function (node) {
	if (node.nodeName == 'length') return null;
	this[this.length] = node.value;
	if (!this._ns_nodes[node.namespaceURI]) this._ns_nodes[node.namespaceURI] = {};
	this._ns_nodes[node.namespaceURI][node.nodeName] = node;
	this._nodes[this.length] = node;
	this.length++;
});

// Node interface
function Node (name) {
	this.nodeName = name;
	this.nodeValue = null;
	this.nodeType = null;
	this.parentNode = null;
	this.childNodes = new NodeList();
	this.firstChild = null;
	this.lastChild = null;
	this.previousSibling = null;
	this.nextSibling = null;
	this.attributes = new NamedNodeMap();
	this.ownerDocument = null;
	this.namespaceURI = null;

	if (name) {
		var p = name.indexOf(':');
		if (p != -1) {
			this.prefix = name.substring(0,p);
			this.localName = name.substring(p + 1);
		} else {
			this.localName = name;
		}
	}

	//log_stdout(' --  Node constructor');
}
Node.ELEMENT_NODE = 1;
Node.ATTRIBUTE_NODE = 2;
Node.TEXT_NODE = 3;
Node.CDATA_SECTION_NODE = 4;
Node.ENTITY_REFERENCE_NODE = 5;
Node.ENTITY_NODE = 6;
Node.PROCESSING_INSTRUCTION_NODE = 7;
Node.COMMENT_NODE = 8;
Node.DOCUMENT_NODE = 9;
Node.DOCUMENT_TYPE_NODE = 10;
Node.DOCUMENT_FRAGMENT_NODE = 11;
Node.NOTATION_NODE = 12;
Node.NAMESPACE_DECL = 18;

Node.method('_childIndex', function (node) {
	for (var i = 0; i < this.childNodes.length; i++)
		if (this.childNodes[i] === node) return i;
});
Node.method('insertBefore', function (node, target) {

	if (node.nodeType == Node.DOCUMENT_FRAGMENT_NODE) {
		for (var i = 0; i < node.childNodes.length; i++)
			this.insertBefore(node.childNodes.item(i));
		return node;
	}

	node.parentNode = this;
	node.ownerDocument = this.ownerDocument;
	var i = this._childIndex(target);

	for (var j = this.childNodes.length; j > i; j--)
		this.childNodes[j] = this.childNodes[j - 1];

	this.childNodes[i] = node;

	if (i == 0) {
		this.firstChild = node;
	} else {
		this.childNodes[i - 1].nextSibling = node;
		node.previousSibling = this.childNodes[i + 1];
	}

	this.childNodes[i + 1].previousSibling = node;
	node.nextSibling = this.childNodes[i + 1];
	
	node._index = this.ownerDocument._nodes.length;
	this.ownerDocument._nodes[this.ownerDocument._nodes.length] = node;

	this.childNodes.length++;
	return node;
});

Node.method('removeChild', function (node) {
	node.parentNode = this;
	node.ownerDocument = this.ownerDocument;
	var i = this._childIndex(node);

	if (node === this.firstChild) {
		this.firstChild = node.nextSibling;
	} else {
		node.previousSibling.nextSibling = node.nextSibling;
		for (var j = i; j < this.childNodes.length; j++)
			this.childNodes[j - 1] = this.childNodes[j];
	}

	if (node === this.lastChild) {
		this.lastChild = node.previousSibling;
	} else {
		node.nextSibling.previousSibling = node.previousSibling;
	}

	this.ownerDocument._nodes[node._index] = null;
	
	this.childNodes.length--;
	return node;
});

Node.method('appendChild', function (node) {

	if (node.nodeType == Node.DOCUMENT_FRAGMENT_NODE) {
		for (var i = 0; i < node.childNodes.length; i++)
			this.appendChild(node.childNodes.item(i));
		return node;
	}

	node.parentNode = this;
	this.childNodes.push( node );
	this.lastChild = node;
	if (this.childNodes.length == 1) {
		this.firstChild = node;
	} else {
		this.lastChild.previousSibling = this.childNodes[this.childNodes.length - 2]
		this.lastChild.previousSibling.nextSibling = this.lastChild;
	}

	return node;
});

Node.method('hasChildNodes', function () {
	if (this.childNodes.length) return true;
	return false;
});

Node.method('hasAttributes', function () {
	if (this.attributes.length) return true;
	return false;
});

Node.method('cloneNode', function (deep) {
	//log_stdout(this.constructor);
	var newNode = new this.constructor( this.nodeName );
	newNode.ownerDocument = this.ownerDocument;
	newNode.namespaceURI = this.namespaceURI;
	newNode.prefix = this.prefix;

	if (deep) {
		for (var i = 0; i < this.childNodes.length; i++)
			newNode.appendChild( this.childNodes.item(i).cloneNode(deep) );
	}

	for (var i = 0; i < this.attributes.length; i++)
		newNode.attributes.setNamedItem( this.attributes.item(i) );

	return newNode;
});

function DocumentType (n,p,s) {
	this.uber('constructor');
	this.constructor = DocumentType;
	this.nodeType = Node.DOCUMENT_TYPE_NODE;
	this.name = n;
	this.entities = new NamedNodeMap();
	this.notations = new NamedNodeMap();
	this.publicId = p;
	this.systemId = s;
	this.internalSubset = null;
}
DocumentType.inherits(Node);

function Notation (p, s) {
	this.uber('constructor');
	this.constructor = Notation;
	this.nodeType = Node.NOTATION_NODE;
	this.publicId = p;
	this.systemId = s;
}
Notation.inherits(Node);

function ProcessingInstruction (target, data) {
	this.uber('constructor');
	this.constructor = ProcessingInstruction;
	this.nodeType = Node.PROCESSING_INSTRUCTION_NODE;
	this.target = target;
	this.data = data;
}
ProcessingInstruction.inherits(Node);

function Entity (p, s, n) {
	this.uber('constructor');
	this.constructor = Entity;
	this.nodeType = Node.ENTITY_NODE;
	this.publicId = p;
	this.systemId = s;
	this.notationName = n;
}
Entity.inherits(Node);

function EntityReference () {
	this.uber('constructor');
	this.constructor = EntityReference;
	this.nodeType = Node.ENTITY_REFERENCE_NODE;
}
EntityReference.inherits(Node);

// Document interface
function Document (dt) {
	this.uber('constructor');
	this.constructor = Document;
	this.nodeType = Node.DOCUMENT_NODE;
	this.doctype = dt;
	this.documentElement = null;
	this.implementation = new DOMImplementation();
	this._nodes = [];
	//log_stdout(' --  Document constructor');
}

Document.inherits(Node);
Document.method('createAttribute', function (tagName) {
	var node = new Attr(tagName);
	node.ownerDocument = this;
	return node;
});

Document.method('createAttributeNS', function (ns,tagName) {
	var node = this.createAttribute(tagName);
	node.namespaceURI = ns;
	return node;
});

Document.method('createElement', function (tagName) {
	var node = new Element(tagName);
	node.ownerDocument = this;
	node._index = this._nodes.length;
	this._nodes[this._nodes.length] = node;
	return node;
});

Document.method('createElementNS', function (ns,tagName) {
	var node = this.createElement(tagName);
	node.namespaceURI = ns;
	return node;
});

Document.method('importNode', function (node, deep) {
	var tmp = node.clone(deep);
	tmp.ownerDocument = this;
	var newNode = tmp.cloneNode(deep);
	return newNode;
});

Document.method('createDocumentFragment', function () {
	var x = new Node();
	x.nodeType = Node.DOCUMENT_FRAGMENT_NODE;
	x.ownerDocument = this;
});

Document.method('createTextNode', function (content) {
	var node = new Text(content);
	node.ownerDocument = this;
	return node;
});

Document.method('createComment', function (content) {
	var node = new Comment(content);
	node.ownerDocument = this;
	return node;
});

Document.method('createCDATASection', function (content) {
	var node = new CDATASection(content);
	node.ownerDocument = this;
	return node;
});

Document.method('getElementById', function (id) {
	for (var i in this._nodes) {
		//log_stdout(' id = ' + this._nodes[i].attributes.id);
		if (this._nodes[i] && this._nodes[i].attributes.id == id)
			return this._nodes[i];
	}
	return null;
});

Document.method('getElementsByTagName', function (tname) {
	var list = new NodeList();
	this.documentElement.getElementsByTagName(tname, list);
	return list;
});

Document.method('getElementsByTagNameNS', function (ns, tname) {
	var list = new NodeList();
	this.documentElement.getElementsByTagNameNS(ns, tname, list);
	return list;
});

// Attr interface
function Attr ( name, value ) {
	this.uber('constructor',name);
	this.constructor = Attr;
	this.nodeType = Node.ATTRIBUTE_NODE;
	this.name = name;
	this.value = this.nodeValue = value;
	this.specified = (this.value ? true : false);
	this.ownerElement = null;
	//log_stdout(' --  Attr constructor');
}
Attr.inherits(Node);


// Element interface
function Element ( name ) {
	this.uber('constructor',name);
	this.constructor = Element;
	this.nodeType = Node.ELEMENT_NODE;
	this.tagName = name;
	//log_stdout(' --  Element constructor')
}
Element.inherits(Node);

Element.method('getAttribute', function (aname) {
	var x = this.attributes.getNamedItem(aname);
	if (x) return x.value;
	return null;
});

Element.method('setAttribute', function (aname,aval) {
	var attr = new Attr(aname, aval);
	attr.ownerElement = this;
	return this.attributes.setNamedItem(attr);
});

Element.method('removeAttribute', function (aname) {
	this.attributes.removeNamedItem(aname);
	return null;
});

Element.method('getAttributeNode', function (aname) {
	return this.attributes.getNamedItem(aname);
});

Element.method('setAttributeNode', function (attr) {
	attr.ownerElement = this;
	attr.namespaceURI = (attr.namespaceURI ? attr.namespaceURI : this.namespaceURI);
	return this.attributes.setNamedItem(attr);
});

Element.method('removeAttributeNode', function (attr) {
	if (attr.namespaceURI) {
		return this.attributes.removeNamedItemNS(attr.namespaceURI, attr.name);
	} else {
		return this.attributes.removeNamedItem(attr.name);
	}
});

Element.method('getAttributeNS', function (ns,aname) {
	var x = this.attributes.getNamedItemNS(ns,aname);
	if (x) return x.value;
	return null;
});

Element.method('setAttributeNS', function (ns,aname,aval) {
	var attr = new Attr(aname, aval);
	attr.ownerElement = this;
	attr.namespaceURI = ns;
	return this.attributes.setNamedItem(ns,attr);
});

Element.method('removeAttributeNS', function (ns,aname) {
	this.attributes.removeNamedItemNS(ns,aname);
	return null;
});

Element.method('getAttributeNodeNS', function (ns, aname) {
	return this.attributes.getNamedItemNS(ns,aname);
});

Element.method('setAttributeNodeNS', function (attr) {
	attr.ownerElement = this;
	attr.namespaceURI = (attr.namespaceURI ? attr.namespaceURI : this.namespaceURI);
	return this.attributes.setNamedItemNS(attr);
});

Element.method('hasAttribute', function (name) {
	return ( this.getAttribute(name) ? true : false );
});

Element.method('hasAttributeNS', function (ns, name) {
	return ( this.getAttributeNS(ns, name) ? true : false );
});

Element.method('getElementsByTagName', function (tname, list) {
	if (!list) list = new NodeList();
	if (this.tagName == tname) list.push(this);
	//log_stdout(' --  ' + this.tagName + ' :: ' + this.childNodes.length);
	for (var i = 0;  i < this.childNodes.length; i++) {
		if (this.childNodes.item(i).nodeType == 1)
			this.childNodes.item(i).getElementsByTagName(tname, list);
	}
	return list;
});

Element.method('getElementsByTagNameNS', function (ns, tname, list) {
	if (!list) list = new NodeList();
	if (this.localName == tname && this.namespaceURI == ns) list.push(this);
	//log_stdout(' --  {' + this.namespaceURI + '}:' + this.localName + ' :: ' + this.childNodes.length);
	for (var i = 0;  i < this.childNodes.length; i++) {
		if (this.childNodes.item(i).nodeType == 1)
			this.childNodes.item(i).getElementsByTagNameNS(ns, tname, list);
	}
	return list;
});


// CharacterData interface
function CharacterData ( name, content ) {
	this.uber('constructor', name);
	this.constructor = CharacterData;
	this.setData(content);
	//log_stdout(' --  CharacterData constructor');
	//log_stdout(' --  CharacterData length == ' + this.length + ' :: ' + this.data);
}
CharacterData.inherits(Node);

CharacterData.method('setData', function (content) {
	this.data = this.nodeValue = content;
	if (this.data)
		this.length = this.data.length;
});
CharacterData.method('substringData', function (offset,count) {
	this.data.substring(offset,count);
});
CharacterData.method('appendData', function (txt) {
	this.data = this.nodeValue = this.data + txt;
	this.length = this.data.length;
});
CharacterData.method('insertData', function (offset,txt) {
	var b = this.data.substring(0,offset);
	var a = this.data.substring(offset);
	this.data = this.nodeValue = b + txt + a;
	this.length = this.data.length;
});
CharacterData.method('deleteData', function (offset,count) {
	var b = this.data.substring(0,offset);
	var a = this.data.substring(offset + count);
	this.data = this.nodeValue = b + a;
	this.length = this.data.length;
});
CharacterData.method('replaceData', function (offset,count,txt) {
	var b = this.data.substring(0,offset);
	var a = this.data.substring(offset + count);
	this.data = this.nodeValue = b + txt +  a;
	this.length = this.data.length;
});



// Text interface
function Text ( content ) {
	this.superclass.constructor.call(this, '#text', content);
	this.constructor = Text;
	this.nodeType = Node.TEXT_NODE;
	//log_stdout(' --  Text constructor :: ' + this.data);
}
Text.inherits(CharacterData);


// CDATASection interface
function CDATASection ( content ) {
	this.uber('constructor', '#cdata', content);
	this.constructor = CDATASection;
	this.nodeType = Node.COMMENT_NODE;
	//log_stdout(' --  Comment constructor');
}
CDATASection.inherits(Text);

// Comment interface
function Comment ( content ) {
	this.uber('constructor', '#comment', content);
	this.constructor = Comment;
	this.nodeType = Node.COMMENT_NODE;
	//log_stdout(' --  Comment constructor');
}
Comment.inherits(Text);



//////////////////////// XPath stuff /////////////////////////

function XPathNamespaceResolver (data) {
	this.data = data;
}
XPathNamespaceResolver.inherits(NamespaceResolver);

XPathNamespaceResolver.method('lookupNamespaceURI', function (prefix) {
	return this.data[prefix];
});
XPathNamespaceResolver.method('setNamespaceURI', function (prefix, uri) {
	this.data[prefix] = uri;
});

