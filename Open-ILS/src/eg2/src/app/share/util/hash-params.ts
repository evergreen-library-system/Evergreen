import {ParamMap} from '@angular/router';


/**
 * Class to map a generic hash to an Angular ParamMap.
 */
export class HashParams implements ParamMap {
    private params: {[key: string]: any[]};

    public get keys(): string[] {
        return Object.keys(this.params);
    }

    constructor(params: {[key: string]: any}) {
        this.params = params || {};
    }

    has(key: string): boolean {
        return key in this.params;
    }

    get(key: string): string | null {
        return this.has(key) ? [].concat(this.params[key])[0] : null;
    }

    getAll(key: string): string[] {
        return this.has(key) ? [].concat(this.params[key]) : [];
    }
}
