dump('entering example.template.js\n');

if (typeof example == 'undefined') example = {};
example.template = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
    } catch(E) {
        dump('example.template: ' + E + '\n');
    }
}

example.template.prototype = {

    'init' : function( params ) {

        try {
            var obj = this;

            JSAN.use('util.controller'); obj.controller = new util.controller();
            obj.controller.init(
                {
                    control_map : {
                        'cmd_broken' : [
                            ['command'],
                            function() { alert('Not Yet Implemented'); }
                        ],
                    }
                }
            );

        } catch(E) {
            this.error.sdump('D_ERROR','example.template.init: ' + E + '\n');
        }
    },
}

dump('exiting example.template.js\n');
