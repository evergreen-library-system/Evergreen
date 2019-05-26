import {Injectable, Pipe, PipeTransform} from '@angular/core';
import {DatePipe, CurrencyPipe} from '@angular/common';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';

/**
 * Format IDL vield values for display.
 */

declare var OpenSRF;

export interface FormatParams {
    value: any;
    idlClass?: string;
    idlField?: string;
    datatype?: string;
    orgField?: string; // 'shortname' || 'name'
    datePlusTime?: boolean;
}

@Injectable({providedIn: 'root'})
export class FormatService {

    dateFormat = 'shortDate';
    dateTimeFormat = 'short';
    wsOrgTimezone: string = OpenSRF.tz;

    constructor(
        private datePipe: DatePipe,
        private currencyPipe: CurrencyPipe,
        private idl: IdlService,
        private org: OrgService
    ) {

        // Create an inilne polyfill for Number.isNaN, which is
        // not available in PhantomJS for unit testing.
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/isNaN
        if (!Number.isNaN) {
            // "The following works because NaN is the only value
            // in javascript which is not equal to itself."
            Number.isNaN = (value: any) => {
                return value !== value;
            };
        }
    }

    /**
     * Create a human-friendly display version of any field type.
     */
    transform(params: FormatParams): string {
        const value = params.value;

        if (   value === undefined
            || value === null
            || value === ''
            || Number.isNaN(value)) {
            return '';
        }

        let datatype = params.datatype;

        if (!datatype) {
            if (params.idlClass && params.idlField) {
                datatype = this.idl.classes[params.idlClass]
                    .field_map[params.idlField].datatype;
            } else {
                // Assume it's a primitive value
                return value + '';
            }
        }

        switch (datatype) {

            case 'link':
                if (typeof value !== 'object') {
                    return value + ''; // no fleshed value here
                }

                if (!params.idlClass || !params.idlField) {
                    // Without a full accounting of the field data,
                    // we can't determine the linked selector field.
                    return value + '';
                }

                const selector =
                    this.idl.getLinkSelector(params.idlClass, params.idlField);

                if (selector && typeof value[selector] === 'function') {
                    const val = value[selector]();

                    if (Array.isArray(val)) {
                        // Typically has_many links will not be fleshed,
                        // but in the off-chance the are, avoid displaying
                        // an array reference value.
                        return '';
                    } else {
                        return val + '';
                    }

                } else {
                    return value + '';
                }

            case 'org_unit':
                const orgField = params.orgField || 'shortname';
                const org = this.org.get(value);
                return org ? org[orgField]() : '';

            case 'timestamp':
                const date = new Date(value);
                if (Number.isNaN(date.getTime())) {
                    console.error('Invalid date in format service', value);
                    return '';
                }
                let fmt = this.dateFormat || 'shortDate';
                if (params.datePlusTime) {
                    fmt = this.dateTimeFormat || 'short';
                }
                return this.datePipe.transform(date, fmt);

            case 'money':
                return this.currencyPipe.transform(value);

            case 'bool':
                // Slightly better than a bare 't' or 'f'.
                // Note the caller is better off using an <eg-bool/> for
                // boolean display.
                return Boolean(
                    value === 't' || value === 1 ||
                    value === '1' || value === true
                ).toString();

            default:
                return value + '';
        }
    }
}


// Pipe-ify the above formating logic for use in templates
@Pipe({name: 'formatValue'})
export class FormatValuePipe implements PipeTransform {
    constructor(private formatter: FormatService) {}
    // Add other filter params as needed to fill in the FormatParams
    transform(value: string, datatype: string): string {
        return this.formatter.transform({value: value, datatype: datatype});
    }
}

