import {Injectable} from '@angular/core';

interface StringAssignment {
    key: string;     // keyboard command
    resolver: (ctx: any) => Promise<string>;
}

interface PendingInterpolation {
    key: string;
    ctx: any;
    resolve: (string) => any;
    reject: (string) => any;
}

@Injectable()
export class StringService {

    strings: {[key: string]: StringAssignment} = {};

    // This service can only interpolate one string at a time, since it
    // maintains only one string component instance.  Avoid clobbering
    // in-process interpolation requests by maintaining a request queue.
    private pending: PendingInterpolation[];

    constructor() {
        this.pending = [];
    }

    register(assn: StringAssignment) {
        this.strings[assn.key] = assn;
    }

    interpolate(key: string, ctx?: any): Promise<string> {

        if (!this.strings[key]) {
            return Promise.reject(`String key not found: "${key}"`);
        }

        return new Promise( (resolve, reject) => {
            const pend: PendingInterpolation = {
                key: key,
                ctx: ctx,
                resolve: resolve,
                reject: reject
            };

            this.pending.push(pend);

            // Avoid launching the pending string processer with >1
            // pending, because the processor will have already started.
            if (this.pending.length === 1) {
                this.processPending();
            }
        });
    }

    processPending() {
        const pstring = this.pending[0];

        console.debug('STRING', pstring.key, pstring.ctx);

        this.strings[pstring.key].resolver(pstring.ctx).then(
            txt => {
                pstring.resolve(txt);
                this.pending.shift();
                if (this.pending.length) {
                    this.processPending();
                }
            },
            err => {
                pstring.reject(err);
                this.pending.shift();
                if (this.pending.length) {
                    this.processPending();
                }
            }
        );
    }
}


