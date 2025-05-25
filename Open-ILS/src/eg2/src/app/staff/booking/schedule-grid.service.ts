import {Injectable} from '@angular/core';
import {Observable, of, switchMap} from 'rxjs';
import {NgbTimeStruct} from '@ng-bootstrap/ng-bootstrap';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {GridRowFlairEntry} from '@eg/share/grid/grid';
import {DateRange} from '@eg/share/daterange-select/daterange-select.component';

import * as moment from 'moment-timezone';

export interface ReservationPatron {
  patronId: number;
  patronLabel: string;
  reservationId: number;
}

interface ScheduleRowPatrons {
    [key: string]: ReservationPatron[];
}

export interface ScheduleRow {
    time: moment.Moment;
    patrons: ScheduleRowPatrons;
}

// Various methods that fetch data for and process the schedule of reservations

@Injectable({providedIn: 'root'})
export class ScheduleGridService {

    constructor(
        private auth: AuthService,
        private pcrud: PcrudService,
    ) {
    }
    hoursOfOperation = (date: Date): Observable<{startOfDay: NgbTimeStruct, endOfDay: NgbTimeStruct}> => {
        const defaultStartHour = 9;
        const defaultEndHour = 17;
        return this.pcrud.retrieve('aouhoo', this.auth.user().ws_ou())
            .pipe(switchMap((hours) => {
                const startArray = hours[this.evergreenStyleDow(date) + '_open']().split(':');
                const endArray = hours[this.evergreenStyleDow(date) + '_close']().split(':');
                return of({
                    startOfDay: {
                        hour: ('00' === startArray[0]) ? defaultStartHour : +startArray[0],
                        minute: +startArray[1],
                        second: 0},
                    endOfDay: {
                        hour: ('00' === endArray[0]) ? defaultEndHour : +endArray[0],
                        minute: +endArray[1],
                        second: 0}
                });
            }));
    };

    resourceAvailabilityIcon = (row: ScheduleRow, numResources: number): GridRowFlairEntry => {
        let icon = {icon: 'event_busy', title: 'All resources are reserved at this time'};
        let busyColumns = 0;
        for (const key in row.patrons) {
            if (row.patrons[key] instanceof Array && row.patrons[key].length) {
                busyColumns += 1;
            }
        }
        if (busyColumns < numResources) {
            icon = {icon: 'event_available', title: 'Resources are available at this time'};
        }
        return icon;
    };

    fetchRelevantResources = (resourceTypeId: number, owningLibraries: number[], selectedAttributes: number[]): Observable<IdlObject> => {
        const where = {
            type: resourceTypeId,
            owner: owningLibraries,
        };

        if (selectedAttributes.length) {
            where['id'] = {'in':
                {'from': 'bram', 'select': {'bram': ['resource']},
                    'where': {'value':  selectedAttributes}}};
        }
        return this.pcrud.search('brsrc', where, {
            order_by: 'barcode ASC',
            flesh: 1,
            flesh_fields: {'brsrc': ['attr_maps']},
        });
    };

    momentizeDateRange = (range: DateRange, timezone: string): {startTime: moment.Moment, endTime: moment.Moment} => {
        return {
            startTime: moment.tz([
                range.fromDate.year,
                range.fromDate.month - 1,
                range.fromDate.day],
            timezone),
            endTime: moment.tz([
                range.toDate.year,
                range.toDate.month - 1,
                range.toDate.day + 1],
            timezone)
        };
    };
    momentizeDay = (date: Date, start: NgbTimeStruct, end: NgbTimeStruct, timezone: string):
        {startTime: moment.Moment, endTime: moment.Moment} => {
        return {
            startTime: moment.tz([
                date.getFullYear(),
                date.getMonth(),
                date.getDate(),
                start.hour,
                start.minute],
            timezone),
            endTime: moment.tz([
                date.getFullYear(),
                date.getMonth(),
                date.getDate(),
                end.hour,
                end.minute],
            timezone)
        };
    };

    createBasicSchedule = (range: {startTime: moment.Moment, endTime: moment.Moment}, granularity: number): ScheduleRow[] => {
        const currentTime = range.startTime.clone();
        const schedule = [];
        while (currentTime < range.endTime) {
            schedule.push({'time': currentTime.clone()});
            currentTime.add(granularity, 'minutes');
        }
        return schedule;
    };

    fetchReservations = (range: {startTime: moment.Moment, endTime: moment.Moment}, resourceIds: number[]): Observable<IdlObject> => {
        return this.pcrud.search('bresv', {
            '-or': {'target_resource': resourceIds, 'current_resource': resourceIds},
            'end_time': {'>': range.startTime.toISOString()},
            'start_time': {'<': range.endTime.toISOString()},
            'return_time': null,
            'cancel_time': null },
        {'flesh': 1, 'flesh_fields': {'bresv': ['current_resource', 'usr']}});
    };

    addReservationToSchedule = (reservation: IdlObject, schedule: ScheduleRow[], granularity: number, timezone: string): ScheduleRow[] => {
        for (let index = 0; index < schedule.length; index++) {
            const start = schedule[index].time;
            const end = (index + 1 < schedule.length) ?
                schedule[index + 1].time :
                schedule[index].time.clone().add(granularity, 'minutes');
            if ((moment.tz(reservation.start_time(), timezone).isBefore(end)) &&
                (moment.tz(reservation.end_time(), timezone).isAfter(start))) {
                if (!schedule[index]['patrons']) { schedule[index].patrons = {}; }
                if (!schedule[index].patrons[reservation.current_resource().barcode()]) {
                    schedule[index].patrons[reservation.current_resource().barcode()] = [];
                }
                if (schedule[index].patrons[reservation.current_resource().barcode()]
                    .findIndex(patron => patron.patronId === reservation.usr().id()) === -1) {
                    schedule[index].patrons[reservation.current_resource().barcode()].push(
                        {'patronLabel': reservation.usr().usrname(),
                            'patronId': reservation.usr().id(),
                            'reservationId': reservation.id()});
                }
            }

        }
        return schedule;

    };

    // Evergreen uses its own day of week style, where dow_0 = Monday and dow_6 = Sunday
    private evergreenStyleDow = (original: Date): string => {
        const daysInAWeek = 7;
        const offset = 6;
        return 'dow_' + (original.getDay() + offset) % daysInAWeek;
    };


}

