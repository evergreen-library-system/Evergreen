dump('entering test/test.js\n');

if (typeof test == 'undefined') var test = {};
test.test = {};

test.test.EXPORT_OK	= [ 'hello_world' ];
test.test.EXPORT_TAGS	= { ':all' : test.test.EXPORT_OK };

test.test.hello_world = function () {
	alert('Hello World');
}

dump('exiting test/test.js\n');
