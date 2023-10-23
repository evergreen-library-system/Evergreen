/* eslint-disable no-case-declarations, no-magic-numbers */
import {Injectable, Pipe, PipeTransform} from '@angular/core';
import {DatePipe, DecimalPipe, getLocaleDateFormat, getLocaleTimeFormat, getLocaleDateTimeFormat, FormatWidth} from '@angular/common';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {LocaleService} from '@eg/core/locale.service';
import * as moment from 'moment-timezone';
import {DateUtil} from '@eg/share/util/date';

/**
 * Format IDL vield values for display.
 */

declare var OpenSRF; // eslint-disable-line no-var

export interface FormatParams {
    value: any;
    idlClass?: string;
    idlField?: string;
    datatype?: string;
    orgField?: string; // 'shortname' || 'name'
    datePlusTime?: boolean;
    timezoneContextOrg?: number;
    dateOnlyInterval?: string;
}

@Injectable({providedIn: 'root'})
export class FormatService {

    dateFormat = 'shortDate';
    dateTimeFormat = 'short';
    wsOrgTimezone: string = OpenSRF.tz;
    tzCache: {[orgId: number]: string} = {};

    constructor(
        private datePipe: DatePipe,
        private decimalPipe: DecimalPipe,
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
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

                    // We have an object with no display selector
                    // Display its pkey instead to avoid showing [object Object]

                    const pkey = this.idl.classes[params.idlClass].pkey;
                    if (pkey && typeof value[pkey] === 'function') {
                        return value[pkey]();
                    }

                    return '';
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
                    if (params.timezoneContextOrg) {
                        tz = this.getOrgTz( // support ID or object
                            this.org.get(params.timezoneContextOrg).id());
                    } else {
                        tz = this.wsOrgTimezone;
                    }
                }

                if (value === 'now') {
                    return '';
                }
                const date = moment(value).tz(tz);
                if (!date || !date.isValid()) {
                    console.error(
                        'Invalid date in format service; date=', value, 'tz=', tz);
                    return '';
                }

                let fmt = this.dateFormat || 'shortDate';

                if (params.datePlusTime) {
                    // Time component directly requested
                    fmt = this.dateTimeFormat || 'short';

                } else if (params.dateOnlyInterval) {
                    // Time component displays for non-day-granular intervals.
                    const secs = DateUtil.intervalToSeconds(params.dateOnlyInterval);
                    if (secs !== null && secs % 86400 !== 0) {
                        fmt = this.dateTimeFormat || 'short';
                    }
                }

                return this.datePipe.transform(date.toISOString(true), fmt, date.format('ZZ'));

            case 'money':
                // TODO: this used to use CurrencyPipe, but that injected
                // an assumption that the default currency is always going to be
                // USD. Since CurrencyPipe doesn't have an apparent way to specify
                // that that currency symbol shouldn't be displayed at all, it
                // was switched to DecimalPipe
                return this.decimalPipe.transform(value, '1.2-2');

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
    Fetch the org timezone from cache when available.  Otherwise,
    get the timezone from the org unit setting.  The first time
    this call is made, it may return the incorrect value since
    it's not a promise-returning method (because format() is not a
    promise-returning method).  Future calls will return the correct
    value since it's locally cached.  Since most format() calls are
    repeated many times for Angular digestion, the end result is that
    the correct value will be used in the end.
    */
    getOrgTz(orgId: number): string {

        if (this.tzCache[orgId] === null) {
            // We are still waiting for the value to be returned
            // from the server.
            return this.wsOrgTimezone;
        }

        if (this.tzCache[orgId] !== undefined) {
            // We have a cached value.
            return this.tzCache[orgId];
        }

        // Avoid duplicate parallel lookups by indicating we
        // are loading the value from the server.
        this.tzCache[orgId] = null;

        this.org.settings(['lib.timezone'], orgId)
            .then(sets => this.tzCache[orgId] = sets['lib.timezone']);

        // Use the local timezone while we wait for the real value
        // to load from the server.
        return this.wsOrgTimezone;
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
        return (isoString?.length) ? moment(isoString).tz(timezone) : moment();
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
                    .replace(/'(\w+)'/, '[$1]');
                break;
            }
            case 'medium': {
                const template = getLocaleDateTimeFormat(locale, FormatWidth.Medium);
                const date = getLocaleDateFormat(locale, FormatWidth.Medium);
                const time = getLocaleTimeFormat(locale, FormatWidth.Medium);
                original = template
                    .replace('{1}', date)
                    .replace('{0}', time)
                    .replace(/'(\w+)'/, '[$1]');
                break;
            }
            case 'long': {
                const template = getLocaleDateTimeFormat(locale, FormatWidth.Long);
                const date = getLocaleDateFormat(locale, FormatWidth.Long);
                const time = getLocaleTimeFormat(locale, FormatWidth.Long);
                original = template
                    .replace('{1}', date)
                    .replace('{0}', time)
                    .replace(/'(\w+)'/, '[$1]');
                break;
            }
            case 'full': {
                const template = getLocaleDateTimeFormat(locale, FormatWidth.Full);
                const date = getLocaleDateFormat(locale, FormatWidth.Full);
                const time = getLocaleTimeFormat(locale, FormatWidth.Full);
                original = template
                    .replace('{1}', date)
                    .replace('{0}', time)
                    .replace(/'(\w+)'/, '[$1]');
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

@Pipe({name: 'egOrgDateInContext'})
export class OrgDateInContextPipe implements PipeTransform {
    constructor(private formatter: FormatService) {}

    transform(value: string, orgId?: number, interval?: string ): string {
        return this.formatter.transform({
            value: value,
            datatype: 'timestamp',
            timezoneContextOrg: orgId,
            dateOnlyInterval: interval
        });
    }
}

@Pipe({name: 'egDueDate'})
export class DueDatePipe implements PipeTransform {
    constructor(private formatter: FormatService) {}

    transform(circ: IdlObject): string {
        return this.formatter.transform({
            value: circ.due_date(),
            datatype: 'timestamp',
            timezoneContextOrg: circ.circ_lib(),
            dateOnlyInterval: circ.duration()
        });
    }
}

@Pipe({name: 'egOrUnderscores'})
export class OrUnderscoresPipe implements PipeTransform {
    constructor() {}
    // Add other filter params as needed to fill in the FormatParams
    transform(value: string, datatype: string): string {
        return value !== '' && value !== null ? value : '________';
    }
}

@Pipe({ name: 'js2json'})
export class Js2JsonPipe implements PipeTransform {
    transform(value: any): string {
        return JSON.stringify(value, null, 2); // spacing level = 2
    }
}

/* TODO: this should probably be moved elsewhere, within the acq/ hierarchy */
@Pipe({ name: 'fundLabel', pure: false })
export class FundLabelPipe implements PipeTransform {
    private cache = new Map<number, string>();

    constructor(private pcrud: PcrudService, private org: OrgService,) {}

    transform(fundId: number): string {
        if (this.cache.has(fundId)) {
            return this.cache.get(fundId);
        }

        /* I loathed pulling in LineitemService here, so some code duplication */
        /* .toPromise() is also deprecated here */
        this.pcrud.retrieve('acqf',fundId).toPromise().then(fund => {
            if (fund) {
                const label = `${fund.code()} (${fund.year()}) (${this.org.get(fund.org()).shortname()})`;
                this.cache.set(fundId, label);
            }
        });

        return ''; // default value until the fund is loaded
    }
}
