/**
 * Core Service - egEvent
 *
 * Models / tests event objects returned by many server APIs. 
 * E.g.
 * {
 *  "stacktrace":"..."
 *  "ilsevent":"1575",
 *  "pid":"28258",
 *  "desc":"The requested container_biblio_record_entry_bucket was not found",
 *  "payload":"2",
 *  "textcode":"CONTAINER_BIBLIO_RECORD_ENTRY_BUCKET_NOT_FOUND",
 *  "servertime":"Wed Nov 6 16:05:50 2013"
 * }
 *
 * var evt = egEvent.parse(thing);
 * if (evt) console.error(evt);
 *
 */

angular.module('egCoreMod')

.factory('egEvent', function() {

    return {
        parse : function(thing) {

            function EGEvent(args) {
                this.code = args.ilsevent;
                this.textcode = args.textcode;
                this.desc = args.desc;
                this.payload = args.payload;
                this.debug = args.stacktrace;
                this.servertime = args.servertime;
                this.ilsperm = args.ilsperm;
                this.ilspermloc = args.ilspermloc;
                this.note = args.note;
                this.success = this.textcode == 'SUCCESS';
                this.toString = function() {
                    var s = 'Event: ' + (this.code || '') + ':' + 
                        this.textcode + ' -> ' + new String(this.desc);
                    if(this.ilsperm)
                        s += ' ' + this.ilsperm + '@' + this.ilspermloc;
                    if(this.note)
                        s += '\n' + this.note;
                    return s;
                }
            }
            
            if(thing && typeof thing == 'object' && 'textcode' in thing)
                return new EGEvent(thing);
            return null;
        }
    }
});
 
