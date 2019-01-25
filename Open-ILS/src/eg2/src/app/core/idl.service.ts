import {Injectable} from '@angular/core';

// Added globally by /IDL2js
declare var _preload_fieldmapper_IDL: Object;

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
    getLinkSelector(fmClass: string, field: string): string {
        const fieldDef = this.classes[fmClass].field_map[field];
        if (fieldDef.class) {
            const classDef = this.classes[fieldDef.class];
            if (classDef.pkey) {
                return classDef.field_map[classDef.pkey].selector || null;
            }
        }
        return null;
    }
}

