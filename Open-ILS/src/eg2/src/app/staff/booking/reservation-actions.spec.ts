import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { PcrudService } from '@eg/core/pcrud.service';
import { ReservationActionsService } from './reservation-actions.service';
describe('ReservationActionsService', () => {
    let service: ReservationActionsService;
    let pcrudServiceStub: Partial<PcrudService>;
    const routerSpy = {
        navigate: jasmine.createSpy('navigate')
    };
    beforeEach(() => {
        pcrudServiceStub = {};
        TestBed.configureTestingModule({
            providers: [
                ReservationActionsService,
                { provide: Router, useValue: routerSpy },
                { provide: PcrudService, useValue: pcrudServiceStub }
            ]
        });
        service = TestBed.get(ReservationActionsService);
    });
    it('can open the manage by barcode route', () => {
        service.manageReservationsByResource('barcode123');
        expect(routerSpy.navigate).toHaveBeenCalledWith(
            ['/staff', 'booking', 'manage_reservations', 'by_resource', 'barcode123']);
    });
    it('recognizes 3 as one unique value', () => {
        expect(service.notOneUniqueSelected([3])).toBe(false);
    });
    it('recognizes 1 1 as one unique value', () => {
        expect(service.notOneUniqueSelected([1, 1])).toBe(false);
    });
    it('recognizes 2 3 as more than one unique value', () => {
        expect(service.notOneUniqueSelected([2, 3])).toBe(true);
    });
});
