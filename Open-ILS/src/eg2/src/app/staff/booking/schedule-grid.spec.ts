import { TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { ScheduleGridService, ScheduleRow } from './schedule-grid.service';
import * as moment from 'moment-timezone';

describe('ScheduleGridService', () => {
    let service: ScheduleGridService;
    beforeEach(() => {
        const authServiceStub = {};
        const pcrudServiceStub = {};
        TestBed.configureTestingModule({
            providers: [
                ScheduleGridService,
                { provide: AuthService, useValue: authServiceStub },
                { provide: PcrudService, useValue: pcrudServiceStub }
            ]
        });
        service = TestBed.get(ScheduleGridService);
    });

    it('should recognize when a row is completely busy', () => {
        const busyRow: ScheduleRow = {
            'time': moment(),
            'patrons': {
                'barcode1': [{patronLabel: 'Joe', patronId: 1, reservationId: 3}],
                'barcode2': [{patronLabel: 'Jill', patronId: 2, reservationId: 5}],
                'barcode3': [{patronLabel: 'James', patronId: 3, reservationId: 12},
                             {patronLabel: 'Juanes', patronId: 4, reservationId: 18}]
             }
        };
        expect(service.resourceAvailabilityIcon(busyRow, 3).icon).toBe('event_busy');
    });

    it('should recognize when a row has some availability', () => {
        const rowWithAvailability: ScheduleRow = {
            'time': moment(),
            'patrons': {
                'barcode3': [{patronLabel: 'James', patronId: 3, reservationId: 11},
                             {patronLabel: 'Juanes', patronId: 4, reservationId: 17}]
            }
        };
        expect(service.resourceAvailabilityIcon(rowWithAvailability, 3).icon).toBe('event_available');
    });

    it('should recognize 4 February 2019 as a Monday', () => {
        const date = new Date(2019, 1, 4);
        expect(service['evergreenStyleDow'](date)).toBe('dow_0');
    });

    it('should recognize 3 February 2019 as a Sunday', () => {
        const date = new Date(2019, 1, 3);
        expect(service['evergreenStyleDow'](date)).toBe('dow_6');
    });
});
