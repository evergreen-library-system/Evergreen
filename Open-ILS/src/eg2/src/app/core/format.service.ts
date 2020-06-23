import {Injectable, Pipe, PipeTransform} from '@angular/core';
import {DatePipe, CurrencyPipe, getLocaleDateFormat, getLocaleTimeFormat, getLocaleDateTimeFormat, FormatWidth} from '@angular/common';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {LocaleService} from '@eg/core/locale.service';
import * as moment from 'moment-timezone';

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
    timezoneContextOrg?: number;
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
        private org: OrgService,
        private locale: LocaleService
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
                let tz;
                if (params.idlField === 'dob') {
                    // special case: since dob is the only date column that the
                    // IDL thinks of as a timestamp, the date object comes over
                    // as a UTC value; apply the correct timezone rather than the
                    // local one
                    tz = 'UTC';
                } else {
                    tz = this.wsOrgTimezone;
                }
                const date = moment(value).tz(tz);
                if (!date.isValid()) {
                    console.error('Invalid date in format service', value);
                    return '';
                }
                let fmt = this.dateFormat || 'shortDate';
                if (params.datePlusTime) {
                    fmt = this.dateTimeFormat || 'short';
                }
                return this.datePipe.transform(date.toISOString(true), fmt, date.format('ZZ'));

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
    /**
     * Create an IDL-friendly display version of a human-readable date
     */
    idlFormatDate(date: string, timezone: string): string { return this.momentizeDateString(date, timezone).format('YYYY-MM-DD'); }

    /**
     * Create an IDL-friendly display version of a human-readable datetime
     */
    idlFormatDatetime(datetime: string, timezone: string): string { return this.momentizeDateTimeString(datetime, timezone).toISOString(); }

    /**
     * Create a Moment from an ISO string
     */
    momentizeIsoString(isoString: string, timezone: string): moment.Moment {
        return (isoString.length) ? moment(isoString, timezone) : moment();
    }

    /**
     * Turn a date string into a Moment using the date format org setting.
     */
    momentizeDateString(date: string, timezone: string, strict?, locale?): moment.Moment {
        return this.momentize(date, this.makeFormatParseable(this.dateFormat, locale), timezone, strict);
    }

    /**
     * Turn a datetime string into a Moment using the datetime format org setting.
     */
    momentizeDateTimeString(date: string, timezone: string, strict?, locale?): moment.Moment {
        return this.momentize(date, this.makeFormatParseable(this.dateTimeFormat, locale), timezone, strict);
    }

    /**
     * Turn a string into a Moment using the provided format string.
     */
    private momentize(date: string, format: string, timezone: string, strict: boolean): moment.Moment {
        if (format.length) {
            const result = moment.tz(date, format, true, timezone);
            if (!result.isValid()) {
                if (strict) {
                    throw new Error('Error parsing date ' + date);
                }
                return moment.tz(date, format, false, timezone);
            }
        return moment(new Date(date), timezone);
        }
    }

    /**
     * Takes a dateFormat or dateTimeFormat string (which uses Angular syntax) and transforms
     * it into a format string that MomentJs can use to parse input human-readable strings
     * (https://momentjs.com/docs/#/parsing/string-format/)
     *
     * Returns a blank string if it can't do this transformation.
     */
    private makeFormatParseable(original: string, locale?: string): string {
        if (!original) { return ''; }
        if (!locale) { locale = this.locale.currentLocaleCode(); }
        switch (original) {
            case 'short': {
                const template = getLocaleDateTimeFormat(locale, FormatWidth.Short);
                const date = getLocaleDateFormat(locale, FormatWidth.Short);
                const time = getLocaleTimeFormat(locale, FormatWidth.Short);
                original = template
                    .replace('{1}', date)
                    .replace('{0}', time)
                    .replace(/\'(\w+)\'/, '[$1]');
                break;
            }
            case 'medium': {
                const template = getLocaleDateTimeFormat(locale, FormatWidth.Medium);
                const date = getLocaleDateFormat(locale, FormatWidth.Medium);
                const time = getLocaleTimeFormat(locale, FormatWidth.Medium);
                original = template
                    .replace('{1}', date)
                    .replace('{0}', time)
                    .replace(/\'(\w+)\'/, '[$1]');
                break;
            }
            case 'long': {
                const template = getLocaleDateTimeFormat(locale, FormatWidth.Long);
                const date = getLocaleDateFormat(locale, FormatWidth.Long);
                const time = getLocaleTimeFormat(locale, FormatWidth.Long);
                original = template
                    .replace('{1}', date)
                    .replace('{0}', time)
                    .replace(/\'(\w+)\'/, '[$1]');
                break;
            }
            case 'full': {
                const template = getLocaleDateTimeFormat(locale, FormatWidth.Full);
                const date = getLocaleDateFormat(locale, FormatWidth.Full);
                const time = getLocaleTimeFormat(locale, FormatWidth.Full);
                original = template
                    .replace('{1}', date)
                    .replace('{0}', time)
                    .replace(/\'(\w+)\'/, '[$1]');
                break;
            }
            case 'shortDate': {
                original = getLocaleDateFormat(locale, FormatWidth.Short);
                break;
            }
            case 'mediumDate': {
                original = getLocaleDateFormat(locale, FormatWidth.Medium);
                break;
            }
            case 'longDate': {
                original = getLocaleDateFormat(locale, FormatWidth.Long);
                break;
            }
            case 'fullDate': {
                original = getLocaleDateFormat(locale, FormatWidth.Full);
                break;
            }
            case 'shortTime': {
                original = getLocaleTimeFormat(locale, FormatWidth.Short);
                break;
            }
            case 'mediumTime': {
                original = getLocaleTimeFormat(locale, FormatWidth.Medium);
                break;
            }
            case 'longTime': {
                original = getLocaleTimeFormat(locale, FormatWidth.Long);
                break;
            }
            case 'fullTime': {
                original = getLocaleTimeFormat(locale, FormatWidth.Full);
                break;
            }
        }
        return original
            .replace(/a+/g, 'a') // MomentJs can handle all sorts of meridian strings
            .replace(/d/g, 'D') // MomentJs capitalizes day of month
            .replace(/EEEEEE/g, '') // MomentJs does not handle short day of week
            .replace(/EEEEE/g, '') // MomentJs does not handle narrow day of week
            .replace(/EEEE/g, 'dddd') // MomentJs has different syntax for long day of week
            .replace(/E{1,3}/g, 'ddd') // MomentJs has different syntax for abbreviated day of week
            .replace(/L/g, 'M') // MomentJs does not differentiate between month and month standalone
            .replace(/W/g, '') // MomentJs uses W for something else
            .replace(/y/g, 'Y') // MomentJs capitalizes year
            .replace(/ZZZZ|z{1,4}/g, '[GMT]Z') // MomentJs doesn't put "UTC" in front of offset
            .replace(/Z{2,3}/g, 'Z'); // MomentJs only uses 1 Z
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

