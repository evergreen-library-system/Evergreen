// suck in what we need
perl_print('------------------------------LOAD---------------------------------------');
load_lib('xmlhttprequest.js');

perl_print('------------------------------START---------------------------------------');

perl_print("recordID is",params.recordID);

// xpath namespace resolver
var ns_res = new XPathNamespaceResolver(
	{ marc : "http://www.loc.gov/MARC21/slim",
	  mods : "http://www.loc.gov/mods/v3" }
);

// xmlhttprequest uses the perl xml parser to get the xml doc from 
var x = new XMLHttpRequest();
x.open('POST','http://dev.gapines.org/restgateway');
x.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
x.send('service=open-ils.storage&method=open-ils.storage.direct.biblio.record_entry.retrieve&param=' + params.recordID);


// use the DOM to parse the marc record
var marc = DOMImplementation.parseString(x.responseXML.evaluate('//marc/text()').singleNodeValue.data);



// and then get the title
var res = marc.evaluate(
	"/marc:record/marc:datafield[@tag='245']/marc:subfield[@code='a']/text()",
	marc,
	ns_res
);

// print the title we just grabbed
perl_print(res.singleNodeValue.data);

perl_print('------------------------------END---------------------------------------');

