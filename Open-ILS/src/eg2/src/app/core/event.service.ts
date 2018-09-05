import {Injectable} from '@angular/core';

export class EgEvent {
    code: number;
    textcode: string;
    payload: any;
    desc: string;
    debug: string;
    note: string;
    servertime: string;
    ilsperm: string;
    ilspermloc: number;
    success: Boolean = false;

    toString(): string {
        let s = `Event: ${this.code}:${this.textcode} -> ${this.desc}`;
        if (this.ilsperm) {
            s += `  ${this.ilsperm}@${this.ilspermloc}`;
        }
        if (this.note) {
            s += `\n${this.note}`;
        }
        return s;
    }
}

@Injectable({providedIn: 'root'})
export class EventService {

    /**
     * Returns an Event if 'thing' is an event, null otherwise.
     */
    parse(thing: any): EgEvent {

        // All events have a textcode
        if (thing && typeof thing === 'object' && 'textcode' in thing) {

            const evt = new EgEvent();

            ['textcode', 'payload', 'desc', 'note', 'servertime', 'ilsperm']
                .forEach(field => { evt[field] = thing[field]; });

            evt.debug = thing.stacktrace;
            evt.code = +(thing.ilsevent || -1);
            evt.ilspermloc = +(thing.ilspermloc || -1);
            evt.success = thing.textcode === 'SUCCESS';

            return evt;
        }

        return null;
    }
}


