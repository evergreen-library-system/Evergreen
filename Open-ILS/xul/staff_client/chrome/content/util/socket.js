dump('entering util/socket.js\n');
// vim:noet:sw=4:ts=4:

/*
    Usage example:

    Install netcat on a server and as root do:  nc -l -p 5000

    Then, in the staff client, load Admin -> For Developers -> Javascript Shell

    Enter:

    JSAN.use('util.socket');
    var s = new util.socket('server hostname or IP address here', 5000);
    s.write('hello\n');

    On the server, reply with world<enter>

    Back in the javascript shell, use

    s.read();

*/

if (typeof util == 'undefined') util = {};
util.socket = function (host,port,listener) {

    try {
        if (!host && !port) {
            throw('host = ' + host + '  port = ' + port);
        }

        this.host = host;
        this.port = port;
        if (listener) {
            this.listener = listener;
        } else {
            this._create_listener = true;
        }

        this.init();

    } catch(E) {
        alert('error in util.socket constructor: ' + E);
        throw(E);
    }

    return this;
};

util.socket.prototype = {
    '_data' : '',
    '_onStartRequest' : null,
    'onStartRequest' : function(callback) {
        this._onStartRequest = callback;
    },
    '_onDataAvailable' : null,
    'onDataAvailable' : function(callback) {
        this._onDataAvailable = callback;
    },
    '_onStopRequest' : null,
    'onStopRequest' : function(callback) {
        this._onStopRequest = callback;
    },
    '_reconnectOnStop' : false,
    'dataCallback' : function(callback) {
        this._dataCallback = callback;
    },
    'init' : function() {
        const Cc = Components.classes;
        const Ci = Components.interfaces;
        const socket_Cc = "@mozilla.org/network/socket-transport-service;1";
        var transportService = Cc[socket_Cc].getService(
            Ci.nsISocketTransportService
        );
        this.socket = transportService.createTransport(
            null,0,this.host,this.port,null);
        this.outputStream = this.socket.openOutputStream(0,0,0);
        this.rawInputStream = this.socket.openInputStream(0,0,0);
        const istream_Cc = "@mozilla.org/scriptableinputstream;1";
        this.inputStream = Cc[istream_Cc].createInstance(
            Ci.nsIScriptableInputStream
        ).init(
            this.rawInputStream
        );

        if (this._create_listener) {
            this.listener = this.generate_listener();
        }
        const pump_Cc = "@mozilla.org/network/input-stream-pump;1";
        this.pump = Cc[pump_Cc].createInstance(Ci.nsIInputStreamPump);
        this.pump.init(this.rawInputStream,-1,-1,0,0,true);
        this.pump.asyncRead(this.listener,null);
    },
    'close' : function() {
        dump('util.socket.close() on page ' + location.href + '\n');
        try {
            this.pump.cancel(true);
            this.socket.close(true);
        } catch(E) {
            dump('Error in util.socket.close(): ' + E + '\n');
        }
    },
    'generate_listener' : function() {
        var obj = this;
        Components.utils.import("resource://gre/modules/NetUtil.jsm");
        return {
            onStartRequest : function(request,context) {
                dump('util.socket.pump.onStartRequest on page ' + location.href + '\n');
                if (obj._onStartRequest) {
                    obj._onStartRequest(request,context);
                }
            },
            onDataAvailable : function(request,context,stream,offset,count) {
                dump('util.socket.pump.onDataAvailable on page ' + location.href + '\n');
                if (obj._onDataAvailable) {
                    dump('util.socket.pump.onDataAvailable using _onDataAvailable\n');
                    obj._onDataAvailable(request,context,stream,offset,count);
                }
                var data = NetUtil.readInputStreamToString(stream,count);
                dump(data + '\n');
                if (obj._dataCallback) {
                    dump('util.socket.pump.onDataAvailable using _dataCallback\n');
                    obj._dataCallback(data);
                } else {
                    dump('util.socket.pump.onDataAvailable no _dataCallback to use\n');
                    obj._data += data;
                }
            },
            onStopRequest : function(request,context,result) {
                dump('util.socket.pump.onStopRequest on page ' + location.href + '\n');
                if (!Components.isSuccessCode(result)) {
                    dump(result + '\n');
                }
                if (obj._onStopRequest) {
                    obj._onStopRequest(request,context,result);
                } else if (obj._reconnectOnStop) {
                    // FIXME - cannot get this to work, but you
                    // can overwrite the socket with a new socket
                    // within  _onStopRequest
                }
            }
        };
    },
    'write' : function(s) {
        this.outputStream.write(s,s.length);
    },
    'read' : function(peek) {
        var data = this._data;
        if (!peek) {
            this._data = '';
        }
        return data;
    }
}

dump('exiting util/socket.js\n');
