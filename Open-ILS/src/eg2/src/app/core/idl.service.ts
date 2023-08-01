import {Injectable} from '@angular/core';

// Added globally by /IDL2js
declare var _preload_fieldmapper_IDL: Object; // eslint-disable-line no-var

/**
 * Every IDL object class implements this interface.
 */
export interface IdlObject {
    a: any[];
    classname: string;
    _isfieldmapper: boolean;
    // Dynamically appended functions from the IDL.
    [fields: string]: any;
}

@Injectable({providedIn: 'root'})
export class IdlService {

    classes: any = {}; // IDL class metadata
    constructors = {}; // IDL instance generators

    /**
     * Create a new IDL object instance.
     */
    create(cls: string, seed?: any[]): IdlObject {
        if (this.constructors[cls]) {
            return new this.constructors[cls](seed);
        }
        throw new Error(`No such IDL class ${cls}`);
    }

    parseIdl(): void {

        try {
            this.classes = _preload_fieldmapper_IDL;
        } catch (E) {
            console.error('IDL (IDL2js) not found.  Is the system running?');
            return;
        }

        /**
         * Creates the class constructor and getter/setter
         * methods for each IDL class.
         */
        const mkclass = (cls, fields) => {
            this.classes[cls].classname = cls;

            // This dance lets us encode each IDL object with the
            // IdlObject interface.  Useful for adding type restrictions
            // where desired for functions, etc.
            const generator: any = ((): IdlObject => {

                const x: any = function(seed) {
                    this.a = seed || [];
                    this.classname = cls;
                    this._isfieldmapper = true;
                };

                fields.forEach(function(field, idx) {
                    x.prototype[field.name] = function(n) {
                        if (arguments.length === 1) {
                            this.a[idx] = n;
                        }
                        return this.a[idx];
                    };

                    if (!field.label) {
                        field.label = field.name;
                    }

                    // Coerce 'aou' links to datatype org_unit for consistency.
                    if (field.datatype === 'link' && field.class === 'aou') {
                        field.datatype = 'org_unit';
                    }
                });

                return x;
            });

            this.constructors[cls] = generator();

            // global class constructors required for JSON_v1.js
            // TODO: polluting the window namespace w/ every IDL class
            // is less than ideal.
            window[cls] = this.constructors[cls];
        };

        Object.keys(this.classes).forEach(class_ => {
            mkclass(class_, this.classes[class_].fields);
        });
    }

    // Makes a deep copy of an IdlObject's / structures containing
    // IdlObject's.  Note we don't use JSON cross-walk because our
    // JSON lib does not handle circular references.
    // @depth specifies the maximum number of steps through IdlObject'
    // we will traverse.
    clone(source: any, depth?: number): any {
        if (depth === undefined) {
            depth = 100;
        }

        let result;
        if (typeof source === 'undefined' || source === null) {
            return source;

        } else if (source._isfieldmapper) {
            // same depth because we're still cloning this same object
            result = this.create(source.classname, this.clone(source.a, depth));

        } else {
            if (Array.isArray(source)) {
                result = [];
            } else if (typeof source === 'object') { // source is not null
                result = {};
            } else {
                return source; // primitive
            }

            for (const j in source) {
                if (source[j] === null || typeof source[j] === 'undefined') {
                    result[j] = source[j];
                } else if (source[j]._isfieldmapper) {
                    if (depth) {
                        result[j] = this.clone(source[j], depth - 1);
                    }
                } else {
                    result[j] = this.clone(source[j], depth);
                }
            }
        }

        return result;
    }

    // Given a field on an IDL class, returns the name of the field
    // on the linked class that acts as the selector for the linked class.
    // Returns null if no selector is found or the field is not a link.
    getLinkSelector(fmClass: string, field: string, strict: boolean = false): string {
        let fieldDef = this.classes[fmClass].field_map[field];

        if (!fieldDef) {
            console.warn(
                `No such field "${field}" for IDL class "${fmClass}"`);
            return null;
        }

        if (fieldDef.map) {
            // For mapped fields, we want the selector field on the
            // remotely linked object instead of the directly
            // linked object.
            const linkedClass = this.classes[fieldDef.class];
            fieldDef = linkedClass.field_map[fieldDef.map];
        }

        if (fieldDef.class) {
            return this.getClassSelector(fieldDef.class, strict);
        }
        return null;
    }

    // Return the selector field for the class.  If no selector is
    // defined, use 'name' if it exists as a field on the class. As
    // a last ditch fallback, if there's no selector but the primary
    // key is a text field, use that.
    getClassSelector(idlClass: string, strict: boolean = false): string {

        if (idlClass) {
            const classDef = this.classes[idlClass];

            if (classDef.pkey) {
                const selector = classDef.field_map[classDef.pkey].selector;
                if (selector) { return selector; }

                // If strict mode was requested, return null when there's
                // no selector defined.  This is a simple "safe table" test.
                if (strict) { return null; }

                // No selector defined in the IDL, try 'name'.
                if ('name' in classDef.field_map) { return 'name'; }

                // last ditch - if the primary key is a text field,
                // treat it as the selector
                if (classDef.field_map[classDef.pkey].datatype === 'text') {
                    return classDef.pkey;
                }

            }
        }

        return null;
    }

    toHash(obj: any, flatten?: boolean): any {

        if (typeof obj !== 'object' || obj === null) {
            return obj;
        }

        if (Array.isArray(obj)) {
            return obj.map(item => this.toHash(item));
        }

        const fieldNames = obj._isfieldmapper ?
            Object.keys(this.classes[obj.classname].field_map) :
            Object.keys(obj);

        const hash: any = {};
        fieldNames.forEach(field => {

            const val = this.toHash(
                typeof obj[field] === 'function' ?  obj[field]() : obj[field],
                flatten
            );

            if (val === undefined) { return; }

            if (flatten && val !== null &&
                typeof val === 'object' && !Array.isArray(val)) {

                Object.keys(val).forEach(key => {
                    const fname = field + '.' + key;
                    hash[fname] = val[key];
                });

            } else {
                hash[field] = val;
            }
        });

        return hash;
    }

    // Returns true if both objects have the same IDL class and pkey value.
    pkeyMatches(obj1: IdlObject, obj2: IdlObject) {
        if (!obj1 || !obj2) { return false; }
        const idlClass = obj1.classname;
        if (idlClass !== obj2.classname) { return false; }
        const pkeyField = this.classes[idlClass].pkey || 'id';
        return obj1[pkeyField]() === obj2[pkeyField]();
    }

    pkeyValue(obj: any): any {
        if (!obj || typeof obj === 'number') { return obj; }
        try {
            const idlClass = obj.classname;
            const pkeyField = this.classes[idlClass].pkey || 'id';
            return obj[pkeyField]();
        } catch(E) {
            if (typeof obj === 'object') {
                console.log('Error returning pkey value', obj);
            }
            return obj;
        }
    }

    // Sort an array of fields from the IDL (like you might get from calling
    // this.idlClasses[classname][fields])

    sortIdlFields(fields: any[], desiredOrder: string[]): any[] {
        let newList = [];

        desiredOrder.forEach(name => {
            const match = fields.filter(field => field.name === name)[0];
            if (match) { newList.push(match); }
        });

        // Sort remaining fields by label
        const remainder = fields.filter(f => !desiredOrder.includes(f.name));
        remainder.sort((a, b) => {
            if (a.label && b.label) {
                return (a.label < b.label) ? -1 : 1;
            } else if (a.label) {
                return -1;
            } else if (b.label) {
                return 1;
            }

            // If no order specified and no labels to sort by,
            // default to sorting by field name
            return (a.name < b.name) ? -1 : 1;
        });
        newList = newList.concat(remainder);
        return newList;
    }

    toBoolean(value) {
        if (typeof value === 'string') {
            if (value === 't') { return true; }
            if (value === 'f') { return false; }
            return null;
        } else {
            return value;
        }
    }
}

