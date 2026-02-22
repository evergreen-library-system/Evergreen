import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldComponent, HoldRequestStats } from './hold.component';
import { ActivatedRoute } from '@angular/router';
import { EMPTY, from, of } from 'rxjs';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { PermService } from '@eg/core/perm.service';
import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { CatalogService } from '@eg/share/catalog/catalog.service';
import { StaffCatalogService } from '../catalog.service';
import { HoldsService } from '@eg/staff/share/holds/holds.service';
import { PatronService } from '@eg/staff/share/patron/patron.service';
import { WorkLogService } from '@eg/staff/share/worklog/worklog.service';
import { StoreService } from '@eg/core/store.service';
import { MockGenerators } from 'test_data/mock_generators';
import { NO_ERRORS_SCHEMA } from '@angular/core';

describe('HoldComponent', () => {
    let component: HoldComponent;
    let fixture: ComponentFixture<HoldComponent>;
    let testbed: TestBed;

    beforeEach(async () => {
        testbed = await TestBed.configureTestingModule({
            declarations: [
                HoldComponent
            ],
            providers: [
                { provide: ActivatedRoute, useValue: {
                    paramMap: of({ get: () => 'C' }),
                    snapshot: {
                        params: { type: 'C' },
                        queryParams: { target: [], holdFor: 'patron' }
                    }
                } },
                { provide: NetService, useValue: MockGenerators.netService({}) },
                { provide: AuthService, useValue: { user: () => MockGenerators.idlObject({usrname: 'test', id: 1, ws_ou: 1}) } },
                { provide: PcrudService, useValue: MockGenerators.pcrudService({ }) },
                { provide: PermService, useValue: {} },
                { provide: OrgService, useValue: MockGenerators.orgService() },
                { provide: ServerStoreService, useValue: { getItemBatch: () => Promise.resolve({}) } },
                { provide: CatalogService, useValue: {} },
                { provide: StaffCatalogService, useValue: {} },
                { provide: HoldsService, useValue: MockGenerators.holdsService() },
                { provide: PatronService, useValue: MockGenerators.patronService() },
                { provide: WorkLogService, useValue: jasmine.createSpyObj<WorkLogService>(['record']) },
                { provide: StoreService, useValue: {} }
            ],
            schemas: [NO_ERRORS_SCHEMA]
        });
    });

    describe('when there are no hold groups', () => {
        beforeEach(() => {
            testbed.compileComponents();
            fixture = TestBed.createComponent(HoldComponent);
            component = fixture.componentInstance;
            fixture.detectChanges();
        });

        it('should create', () => {
            expect(component).toBeTruthy();
        });

        it('displays "Place hold for patron by barcode" label', () => {
            const labelElement = fixture.nativeElement.querySelector('label');
            expect(labelElement.textContent).toContain('Place hold for patron by barcode');
        });

        it('displays patron and staff hold options', () => {
            const radioButtons = fixture.nativeElement.querySelectorAll('input[type="radio"]');
            expect(radioButtons.length).toBe(2);
            expect(radioButtons[0].value).toBe('patron');
            expect(radioButtons[1].value).toBe('staff');
        });

        it('displays notification options', () => {
            const notificationCheckboxes = fixture.nativeElement.querySelectorAll('.list-group-item input[type="checkbox"]');
            expect(notificationCheckboxes.length).toBeGreaterThanOrEqual(2);
            expect(notificationCheckboxes[0].id).toBe('notifyEmail');
            expect(notificationCheckboxes[1].id).toBe('notifyPhone');
        });

        it('displays the Suspend Hold checkbox', () => {
            const suspendCheckbox = fixture.nativeElement.querySelector('#suspend');
            expect(suspendCheckbox).toBeTruthy();
        });

        it('greys out the Place Holds button when form is invalid', () => {
            const placeHoldsButton = fixture.nativeElement.querySelector('button.btn-success');
            expect(placeHoldsButton.disabled).toBeTrue();
        });

        it('displays return button', () => {
            const returnButton = fixture.nativeElement.querySelector('button.btn-info');
            expect(returnButton.textContent).toContain('Return');
        });

        describe('placeHolds()', () => {
            it('calls placeHold with correct parameters', async () => {
                const expectedParams = {
                    holdTarget: 333_444,
                    holdType: 'C',
                    recipient: 456,
                    requestor: 1,
                    pickupLib: 789,
                    notifyEmail: true,
                    notifyPhone: null,
                    notifySms: null,
                    override: undefined,
                    smsCarrier: null,
                    thawDate: null,
                    frozen: false,
                    holdableFormats: null,
                    holdGroup: false,
                    holdGroupId: null
                };
                component.holdContexts = [
                    {
                        holdMeta: {
                            target: 333_444
                        },
                        holdTarget: 333_444,
                        lastRequest: undefined,
                        processing: false,
                        selectedFormats: {formats: {}, langs: {}},
                        success: false,
                        clone: function (target: number): any {},
                        stats: new HoldRequestStats()
                    }
                ];
                component.pickupLib = 789;
                component.user = MockGenerators.idlObject({id: 456, family_name: 'Name'});
                component.notifyPhone = null;

                component.placeHolds();

                expect(component['holds'].placeHold).toHaveBeenCalledWith(expectedParams);
            });
        });

        describe('onReset()', () => {
            it('calls resetForm() then resets holdFor to patron', async () => {
                component.holdFor = 'staff';
                spyOn(component, 'resetRecipient');

                await component.onReset();

                expect(component.resetRecipient).toHaveBeenCalled();
                expect(component.holdFor).toBe('patron');
            });
        });
    });

    describe('when there are hold groups', () => {
        beforeEach(() => {
            testbed.overrideProvider(PcrudService, {useValue: MockGenerators.pcrudService({ search: [
                MockGenerators.idlObject({id: 27, name: 'Hold Group 1'}),
                MockGenerators.idlObject({id: 35, name: 'Hold Group 2'}),
            ] })});
            testbed.compileComponents();
            fixture = TestBed.createComponent(HoldComponent);
            component = fixture.componentInstance;

            fixture.detectChanges();
        });
        it('should display patron, staff, and group hold options', () => {
            const radioButtons = fixture.nativeElement.querySelectorAll('input[type="radio"]');
            expect(radioButtons.length).toBe(3);
            expect(radioButtons[0].value).toBe('patron');
            expect(radioButtons[1].value).toBe('staff');
            expect(radioButtons[2].value).toBe('group');
        });
        it('displays Override all hold-blocking conditions possible?', () => {
            expect(fixture.nativeElement.textContent).toContain('Override all hold-blocking conditions possible?');
        });
        it('greys out Override all hold-blocking conditions possible? by default', () => {
            const checkbox = fixture.nativeElement.querySelector('#override-many');
            expect(checkbox.disabled).toBeTrue();
        });
        it('greys out the Place Hold button if a group is not selected', () => {
            component.holdFor = 'group';
            component.holdForChanged();
            expect(component.readyToPlaceHolds()).toBeFalse();
        });
        it('allows users to click the Place Hold button if a group is selected', () => {
            component.holdFor = 'group';
            component.selectedHoldGroup = {id: 777, label: 'Excellent book club'};
            component.holdForChanged();
            expect(component.readyToPlaceHolds()).toBeTrue();
        });
        describe('when the user wants to place a hold for a hold group', () => {
            beforeEach(() => {
                component.holdFor = 'group';
                fixture.detectChanges();
            });
            it('does not grey out Override all hold-blocking conditions possible?', () => {
                const checkbox = fixture.nativeElement.querySelector('#override-many');
                expect(checkbox.disabled).toBeFalse();
            });
        });
        describe('holdGroupsAsComboboxEntries getter', () => {
            it('returns 2 combobox entries', () => {
                expect(component.holdGroupsAsComboboxEntries.length).toEqual(2);
                expect(component.holdGroupsAsComboboxEntries[0].label).toEqual('Hold Group 1');
                expect(component.holdGroupsAsComboboxEntries[1].label).toEqual('Hold Group 2');
            });
        });
        describe('placeHolds()', () => {
            it('calls placeHold with hold group-related parameters', async () => {
                const expectedParams = {
                    holdGroup: true,
                    holdGroupId: 777,
                    holdTarget: 333_444,
                    holdType: 'C',
                    recipient: 456,
                    requestor: 1,
                    pickupLib: 789,
                    notifyEmail: true,
                    notifyPhone: null,
                    notifySms: null,
                    override: true,
                    smsCarrier: null,
                    thawDate: null,
                    frozen: false,
                    holdableFormats: null
                };
                component.holdContexts = [
                    {
                        holdMeta: {
                            target: 333_444
                        },
                        holdTarget: 333_444,
                        lastRequest: undefined,
                        processing: false,
                        selectedFormats: {formats: {}, langs: {}},
                        success: false,
                        clone: function (target: number): any {},
                        stats: new HoldRequestStats()
                    }
                ];
                component.pickupLib = 789;
                component.user = MockGenerators.idlObject({id: 456, family_name: 'Name'});
                component.notifyPhone = null;
                component.holdFor = 'group';
                component.selectedHoldGroup = {id: 777, label: 'Excellent book club'};

                component.placeHolds();

                expect(component['holds'].placeHold).toHaveBeenCalledWith(expectedParams);
            });
        });
    });

    describe('when some holds in a group succeed and others fail', () => {
        beforeEach(() => {
            const holdsService = jasmine.createSpyObj<HoldsService>(['getHoldTargetMeta', 'placeHold']);
            holdsService.placeHold.and.returnValue(from([{
                holdType: 'B',
                holdTarget: 1,
                recipient: 2,
                requestor: 3,
                pickupLib: 4,
                result: { success: true } // The perl code includes an initial, often inaccurate "summary" message
            }, {
                holdType: 'B',
                holdTarget: 1,
                recipient: 2,
                requestor: 3,
                pickupLib: 4,
                result: { success: true, holdId: 345 }
            }, {
                holdType: 'B',
                holdTarget: 1,
                recipient: 46,
                requestor: 3,
                pickupLib: 4,
                result: { success: false }
            }
            ]));
            holdsService.getHoldTargetMeta.and.returnValue(EMPTY);
            testbed.overrideProvider(PcrudService, {useValue: MockGenerators.pcrudService({ search: [
                MockGenerators.idlObject({id: 27, name: 'Hold Group 1'}),
                MockGenerators.idlObject({id: 35, name: 'Hold Group 2'}),
            ] })});
            testbed.overrideProvider(HoldsService, {useValue: holdsService});
            testbed.compileComponents();
            fixture = TestBed.createComponent(HoldComponent);
            component = fixture.componentInstance;

            fixture.detectChanges();
        });

        it('summarizes it as SomeHoldsPlaced', () => {
            component.holdContexts = [
                {
                    holdMeta: {
                        target: 333_444
                    },
                    holdTarget: 333_444,
                    lastRequest: undefined,
                    processing: false,
                    selectedFormats: {formats: {}, langs: {}},
                    success: false,
                    clone: function (target: number): any {},
                    stats: new HoldRequestStats()
                }
            ];
            component.pickupLib = 789;
            component.user = MockGenerators.idlObject({id: 456, family_name: 'Name'});
            component.notifyPhone = null;
            component.holdFor = 'group';
            component.selectedHoldGroup = {id: 777, label: 'Excellent book club'};

            component.placeHolds();
            const ctx = component.holdContexts.pop();
            const summary = ctx.stats.summary();
            expect(summary.overall).toEqual('SomeHoldsPlaced');
            if (summary.overall !== 'SomeHoldsPlaced') { return; };
            expect(summary.successes).toEqual(1); // it knows to disregard the initial summary
            expect(summary.attempts).toEqual(2);
        });
    });
});
