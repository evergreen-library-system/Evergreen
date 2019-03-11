import {Injectable, EventEmitter, HostListener} from '@angular/core';

export interface AccessKeyAssignment {
    key: string;      // keyboard command
    desc: string;     // human-friendly description
    ctx: string;      // template context
    action: Function; // handler function
}

@Injectable()
export class AccessKeyService {

    // Assignments stored as an array with most recently assigned
    // items toward the front.  Most recent items have precedence.
    assignments: AccessKeyAssignment[] = [];

    constructor() {}

    assign(assn: AccessKeyAssignment): void {
        this.assignments.unshift(assn);
    }

    /**
     * Compress a set of single-fire keyboard events into single
     * string.  For example:  Control and 't' becomes 'ctrl+t'.
     */
    compressKeys(evt: KeyboardEvent): string {
        if (!evt.key) {
            return null;
        }
        let s = '';
        if (evt.ctrlKey || evt.metaKey) { s += 'ctrl+'; }
        if (evt.altKey) { s += 'alt+'; }
        s += evt.key.toLowerCase();

        return s;
    }

    /**
     * Checks for a key assignment and fires the assigned action.
     */
    fire(evt: KeyboardEvent): void {
        const keySpec = this.compressKeys(evt);
        for (const i in this.assignments) { // for-loop to exit early
            if (keySpec === this.assignments[i].key) {
                const assign = this.assignments[i];
                console.debug(`AccessKey assignment found for ${assign.key}`);
                // Allow the current digest cycle to complete before
                // firing the access key action.
                setTimeout(assign.action, 0);
                evt.preventDefault();
                return;
            }
        }
    }

    /**
     * Returns a simplified key assignment list containing just
     * the key spec and the description.  Useful for inspecting
     * without exposing the actions.
     */
    infoIze(): any[] {
        return this.assignments.map(a => {
            return {key: a.key, desc: a.desc, ctx: a.ctx};
        });
    }

}

