import { MockGenerators } from 'test_data/mock_generators';
import { PendingListService, PendingPatron } from './pending-list.service';
import { AuthService } from '@eg/core/auth.service';
import { EgEvent, EventService } from '@eg/core/event.service';
import { NetService } from '@eg/core/net.service';
import { OrgService } from '@eg/core/org.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { TestBed } from '@angular/core/testing';
import { of } from 'rxjs';
import { Pager } from '@eg/share/util/pager';
import { DOCUMENT } from '@angular/common';
import { IdlObject } from '@eg/core/idl.service';

describe('PendingListService', () => {
    const mockPatron = () => ({
        user: MockGenerators.idlObject(
            { row_id: 1, home_ou: 2, usrname: 'test' }
        ),
        mailing_address: null,
        mailing_addresses: [
            MockGenerators.idlObject({ id: 1 })
        ]
    } as PendingPatron);

    let service: PendingListService;

    let mockAuth: jasmine.SpyObj<AuthService>;
    let mockEvt: jasmine.SpyObj<EventService>;
    let mockNet: jasmine.SpyObj<NetService>;
    let mockOrg: { get: (nodeOrOrgId: any) => IdlObject };
    let mockToast: jasmine.SpyObj<ToastService>;
    let mockWindow: jasmine.SpyObj<Window>;

    beforeEach(() => {
        mockAuth = MockGenerators.authService();
        mockEvt = jasmine.createSpyObj<EventService>(['parse']);
        mockNet = jasmine.createSpyObj<NetService>(['request']);
        mockOrg = MockGenerators.orgService();
        mockToast = jasmine.createSpyObj<ToastService>(['success', 'danger']);
        mockWindow = jasmine.createSpyObj<Window>(['open']);

        TestBed.configureTestingModule({
            providers: [
                PendingListService,
                { provide: AuthService, useValue: mockAuth },
                {
                    provide: DOCUMENT,
                    useValue: { defaultView: mockWindow }
                },
                { provide: EventService, useValue: mockEvt },
                { provide: NetService, useValue: mockNet },
                { provide: OrgService, useValue: mockOrg },
                { provide: ToastService, useValue: mockToast }
            ]
        });

        service = TestBed.inject(PendingListService);
    });

    describe('defaultContextOrg()', () => {
        it('should return ws_ou from auth user', () => {
            expect(service.defaultContextOrg()).toBe(mockAuth.user().ws_ou());
        });
    });

    describe('deletePendingPatrons()', () => {
        const patrons = [mockPatron()];
        const error = { textcode: 'SOME_ERROR' };
        const evt = new EgEvent();
        evt.textcode = 'SOME_ERROR';

        it('shows success toast on deletion', () => {
            mockNet.request.and.returnValue(of(['1']));
            mockEvt.parse.and.returnValue(null);
            service.deletePendingPatrons(patrons).subscribe();
            expect(mockToast.success).toHaveBeenCalled();
        });
        it('shows error toast if any deletions fail', () => {
            mockNet.request.and.returnValue(of(error));
            mockEvt.parse.and.returnValue(evt);
            service.deletePendingPatrons(patrons).subscribe();
            expect(mockToast.danger).toHaveBeenCalled();
        });
        it('doesn\'t emit if all deletions fail', () => {
            mockNet.request.and.returnValue(of(error));
            mockEvt.parse.and.returnValue(evt);
            let emitted = false;
            service.deletePendingPatrons(patrons)
                .subscribe(() => emitted = true);
            expect(emitted).toBeFalse();
        });
    });

    describe('getPendingPatrons()', () => {
        const orgId = 1;
        const pager = { limit: 10, offset: 0 } as Pager;

        it('should request pending patrons from net service', () => {
            mockNet.request.and.returnValue(of(mockPatron()));
            service.getPendingPatrons(orgId, pager).subscribe();
            expect(mockNet.request).toHaveBeenCalledWith(
                'open-ils.actor',
                'open-ils.actor.user.stage.retrieve.by_org',
                mockAuth.token(),
                orgId, pager.limit, pager.offset
            );
        });
        it('should flesh home_ou on staged users', () => {
            mockNet.request.and.returnValue(of(mockPatron()));
            service.getPendingPatrons(orgId, pager).subscribe(result => {
                expect(result.user.home_ou().shortname()).toBe('MYLIB');
            });
        });
        it('should map first mailing address', () => {
            mockNet.request.and.returnValue(of(mockPatron()));
            service.getPendingPatrons(orgId, pager).subscribe(result => {
                expect(result.mailing_address.id()).toBe(1);
            });
        });
        it('should show error toast and return empty on failure', () => {
            mockNet.request.and.returnValue(of(new Error()));
            let result: PendingPatron | undefined;
            service.getPendingPatrons(orgId, pager).subscribe(r => result = r);
            expect(mockToast.danger).toHaveBeenCalled();
            expect(result).toBeUndefined();
        });
    });

    describe('loadPendingPatron()', () => {
        const patron = mockPatron();
        const usrname = encodeURIComponent(patron.user.usrname());

        it('should navigate to patron edit page', () => {
            service.loadPendingPatron(patron);
            expect(mockWindow.open).toHaveBeenCalledWith(
                `/eg2/staff/circ/patron/register/stage/${usrname}`,
                '_blank'
            );
        });
    });
});
