function EventListenerList() {
    this._listeners = [];
    return this;
}

EventListenerList.prototype = {
    'add' : function(node, type, listener, useCapture) {
        try {
            node.addEventListener(type,listener,useCapture);
            this._listeners.push({
                'node' : node,
                'type' : type,
                'listener' : listener,
                'useCapture' : useCapture
            });
        } catch(E) {
            alert(location.href + ' Error adding event listener ' + type + ': ' + E);
        }
    },

    'removeAll' : function() {
        try {
            if (typeof this._listeners != 'undefined') {
                for (var i = this._listeners.length - 1; i >= 0; i--) {
                    this._listeners[i].node.removeEventListener(
                        this._listeners[i].type,
                        this._listeners[i].listener,
                        this._listeners[i].useCapture
                    );
                    this._listeners[i].listener = null;
                    delete this._listeners[i];
                }
                this._listeners = [];
            }
        } catch(E) {
            alert(location.href + ' Error in unloadEventListeners(): ' + E);
        }
    }
}

