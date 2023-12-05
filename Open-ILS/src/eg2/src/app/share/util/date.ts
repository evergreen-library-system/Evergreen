
/* Utility code for dates */

export interface YmdParts {
    year: number;
    month: number;
    day: number;
}

export class DateUtil {

    /**
     * Converts an interval string to seconds.
     *
     * intervalToSeconds('1 min 2 seconds')) => 62
     * intervalToSeconds('2 days')) => 172800 (except across time changes)
     * intervalToSeconds('02:00:23')) => 7223
     */
    static intervalToSeconds(interval: string): number {
        const d = new Date();
        const start = d.getTime();
        const parts = interval.split(' ');

        for (let i = 0; i < parts.length; i += 2)  {

            if (!parts[i + 1]) {
                // interval is a bare hour:min:sec string
                const times = parts[i].split(':');
                d.setHours(d.getHours() + Number(times[0]));
                d.setMinutes(d.getMinutes() + Number(times[1]));
                d.setSeconds(d.getSeconds() + Number(times[2]));
                continue;
            }

            const count = Number(parts[i]);
            const partType = parts[i + 1].replace(/s?,?$/, '');

            if (partType.match(/^s/)) {
                d.setSeconds(d.getSeconds() + count);
            } else if (partType.match(/^min/)) {
                d.setMinutes(d.getMinutes() + count);
            } else if (partType.match(/^h/)) {
                d.setHours(d.getHours() + count);
            } else if (partType.match(/^d/)) {
                d.setDate(d.getDate() + count);
            } else if (partType.match(/^mon/)) {
                d.setMonth(d.getMonth() + count);
            } else if (partType.match(/^y/)) {
                d.setFullYear(d.getFullYear() + count);
            }
        }

        return Number((d.getTime() - start) / 1000);
    }

    // Create a date in the local time zone with selected YMD values.
    // Note that new Date(ymd) produces a date in UTC.  This version
    // produces a date in the local time zone.
    static localDateFromYmd(ymd: string): Date {
        const parts = ymd.split('-');
        return new Date(
            Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }

    // Note that date.toISOString() produces a UTC date, which can have
    // a different YMD value than a date in the local time zone.
    // This variation returns values for the local time zone.
    // Defaults to 'now' if no date is provided.
    static localYmdFromDate(date?: Date): string {
        const now = date || new Date();
        return now.getFullYear() + '-' +
            ((now.getMonth() + 1) + '').padStart(2, '0') + '-' +
            (now.getDate() + '').padStart(2, '0');
    }

    static localYmdPartsFromDate(date?: Date): YmdParts {
        const ymd = DateUtil.localYmdFromDate(date);
        const parts = ymd.split(/-/);
        return {
            year: Number(parts[0]),
            month: Number(parts[1]),
            day: Number(parts[2])
        };
    }

    // Return a string in the format -0700 or +0200,
    // like what we might see at the end of a timestamp
    // in a pcrud message from OpenSRF
    static getOpenSrfTzOffsetString(): string {
        const offsetInMinutes = new Date().getTimezoneOffset();

        // Confusingly, if getTimezoneOffset returns a negative number,
        // it means that it is *after* UTC, and should get a plus sign.
        const sign = offsetInMinutes < 0 ? '+' : '-';
        const hours = Math.floor(Math.abs(offsetInMinutes / 60));
        const minutes = Math.abs(offsetInMinutes % 60);
        return sign + String(hours).padStart(2, '0') + String(minutes).padStart(2, '0');
    }
}

