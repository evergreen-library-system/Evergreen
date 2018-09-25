import {Injectable} from '@angular/core';
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

            case 'org_unit':
                const orgField = params.orgField || 'shortname';
                const org = this.org.get(value);
                return org ? org[orgField]() : '';

            case 'timestamp':
                const date = new Date(value);
                let fmt = this.dateFormat || 'shortDate';
                if (params.datePlusTime) {
                    fmt = this.dateTimeFormat || 'short';
                }
                return this.datePipe.transform(date, fmt);

            case 'money':
                return this.currencyPipe.transform(value);

            case 'bool':
                // Slightly better than a bare 't' or 'f'.
                // Should probably add a global true/false string.
                return Boolean(
                    value === 't' || value === 1 ||
                    value === '1' || value === true
                ).toString();

            default:
                return value + '';
        }
    }
}

