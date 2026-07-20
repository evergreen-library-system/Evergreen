import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldingsService } from '@eg/staff/share/holdings/holdings.service';
import { CopyAlertTypesComponent } from './copy-alert-types.component';
import { AuthService } from '@eg/core/auth.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { MockGenerators } from 'test_data/mock_generators';
import { IdlService } from '@eg/core/idl.service';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';
import { of } from 'rxjs';

const mockAlertType = (next_status: string) =>
    MockGenerators.idlObject({ next_status });

const mockCopyStatus = (id: number, name: string) =>
    MockGenerators.idlObject({ id, name });

const mockEvent = (value: number, checked: boolean) => ({
    target: { checked, value } as unknown as HTMLInputElement
} as unknown as Event);

const COPY_STATUSES = [
    mockCopyStatus(4, 'Missing'),
    mockCopyStatus(5, 'In Process'),
    mockCopyStatus(6, 'In Transit')
];

describe('CopyAlertTypesComponent', () => {
    let component: CopyAlertTypesComponent;
    let fixture: ComponentFixture<CopyAlertTypesComponent>;

    let mockPcrud: jasmine.SpyObj<PcrudService>;
    let mockHoldings: jasmine.SpyObj<HoldingsService>;

    beforeEach(async () => {
        mockPcrud = jasmine.createSpyObj(['search', 'retrieveAll']);
        mockPcrud.search.and.returnValue(of([]));
        mockPcrud.retrieveAll.and.returnValue(of(COPY_STATUSES));

        mockHoldings = jasmine.createSpyObj<HoldingsService>(
            ['getMagicCopyStatuses']
        );
        mockHoldings.getMagicCopyStatuses.and.resolveTo([COPY_STATUSES[2].id()]);

        await TestBed.configureTestingModule({
            imports: [ CopyAlertTypesComponent ],
            providers: [
                {provide: AuthService, useValue: MockGenerators.authService()},
                {provide: IdlService, useValue: MockGenerators.idlService({ccat: {pkey: 'id'}})},
                {provide: OrgService, useValue: MockGenerators.orgService()},
                {provide: PcrudService, useValue: mockPcrud},
            ]
        }).overrideComponent(CopyAlertTypesComponent,
            {
                remove: {
                    imports: [AdminPageComponent],
                    providers: [HoldingsService]
                },
                add: {
                    schemas: [CUSTOM_ELEMENTS_SCHEMA],
                    providers: [
                        {
                            provide: HoldingsService,
                            useValue: mockHoldings
                        }
                    ]
                }
            }).compileComponents();

        fixture = TestBed.createComponent(CopyAlertTypesComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
        await fixture.whenStable();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    describe('getCopyStatuses', () => {
        it('sets copyStatuses excluding magic statuses', () => {
            expect(component.copyStatuses?.map(ccs => ccs.id())).toEqual(
                [COPY_STATUSES[0].id(), COPY_STATUSES[1].id()]
            );
        });

        it ('sets statusDisplayMap excluding magic statuses', () => {
            expect(component.statusDisplayMap).toEqual({
                [COPY_STATUSES[0].id()]: COPY_STATUSES[0].name(),
                [COPY_STATUSES[1].id()]: COPY_STATUSES[1].name()
            });
        });
    });

    describe('getNextStatus', () => {
        it('returns empty array if next_status is falsy', () => {
            const ccat = mockAlertType('');
            const nextStatus = component.getNextStatus(ccat);

            expect(nextStatus).toEqual([]);
        });

        it('returns next_status as an array of ids', () => {
            const ccat = mockAlertType('{4,5}');
            const nextStatus = component.getNextStatus(ccat);

            expect(nextStatus).toEqual([4, 5]);
        });
    });

    describe('recordNextStatus', () => {
        it('adds the checked status to next_status on passed IDL', () => {
            const ccat = mockAlertType('{4}');
            const event = mockEvent(5, true);
            component.recordNextStatus(ccat, event);

            expect(ccat.next_status()).toBe('{4,5}');
        });

        it('removes the checked status to next_status on passed IDL', () => {
            const ccat = mockAlertType('{4,5}');
            const event = mockEvent(5, false);
            component.recordNextStatus(ccat, event);

            expect(ccat.next_status()).toBe('{4}');
        });

        it('does nothing if checked status already in next_status', () => {
            const ccat = mockAlertType('{4,5}');
            const event = mockEvent(5, true);
            component.recordNextStatus(ccat, event);

            expect(ccat.next_status()).toBe('{4,5}');
        });
    });

    describe('displayNextStatus', () => {
        it('returns next_status as a string of comma separated names', async () => {
            const ccat = mockAlertType('{4,5}');
            const names = component.displayNextStatus(ccat);

            expect(names).toBe(
                `${COPY_STATUSES[0].name()},${COPY_STATUSES[1].name()}`
            );
        });
    });
});
