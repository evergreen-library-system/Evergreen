import { ComponentFixture, TestBed, waitForAsync } from '@angular/core/testing';
import { SubscriptionSelectorComponent } from './subscription-selector.component';
import { NO_ERRORS_SCHEMA } from '@angular/core';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { CommonModule, formatDate } from '@angular/common';
import { FormatService } from '@eg/core/format.service';
import { MockGenerators } from 'test_data/mock_generators';
import { DateUtil } from '@eg/share/util/date';

const utcOffset = DateUtil.getOpenSrfTzOffsetString();
const mockSubscription = MockGenerators.idlObject({
    id: 12,
    start_date: `2020-01-01T10:00:00${utcOffset}`,
    end_date: `2025-12-31T23:00:00${utcOffset}`,
    owning_lib: MockGenerators.idlObject({shortname: 'MYLIB'})
});

const mockAuth = MockGenerators.authService();
const mockPcrud = MockGenerators.pcrudService({search: mockSubscription});
const mockFormat = jasmine.createSpyObj<FormatService>(['transform']);
mockFormat.transform.and.callFake((date) => formatDate(date.value, 'shortDate', 'en-us'));


describe('SubscriptionSelectorComponent', () => {
    let component: SubscriptionSelectorComponent;
    let fixture: ComponentFixture<SubscriptionSelectorComponent>;

    beforeEach(async () => {
        TestBed.overrideComponent(SubscriptionSelectorComponent, {set: {
            imports: [CommonModule],
            schemas: [NO_ERRORS_SCHEMA],
            providers: [
                {provide: AuthService, useValue: mockAuth},
                {provide: PcrudService, useValue: mockPcrud},
                {provide: FormatService, useValue: mockFormat}
            ]
        }});
        fixture = TestBed.createComponent(SubscriptionSelectorComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    describe('findSubscriptions()', () => {
        it('defaults to limiting to the workstation org unit', () => {
            component.bibRecordId = 1234;
            component.ngOnInit();

            component.findSubscriptions();

            expect(mockPcrud.search).toHaveBeenCalledWith(
                'ssub',
                {record_entry: 1234, owning_lib: [10]},
                { flesh: 1, flesh_fields: {ssub: ['owning_lib'] } }
            );

        });

        it('includes any selected org units in the pcrud query', () => {
            component.bibRecordId = 1234;
            component.selectedOrgUnits = {primaryOrgId: 3, includeDescendants: true, orgIds: [1, 3, 5, 10]};

            component.findSubscriptions();

            expect(mockPcrud.search).toHaveBeenCalledWith(
                'ssub',
                {record_entry: 1234, owning_lib: [1, 3, 5, 10]},
                { flesh: 1, flesh_fields: {ssub: ['owning_lib'] } }
            );
        });

        it('sets subscriptionList property', () => {
            component.ngOnInit();
            component.findSubscriptions();
            fixture.detectChanges();
            expect(component.subscriptionList).toEqual([{id: 12, label: 'Subscription 12 at MYLIB (1/1/20-12/31/25)'}]);
        });
    });

    describe('when subscriptions have not yet loaded', () => {
        beforeEach(() => {
            component.subscriptionList = [];
            fixture.detectChanges();
        });

        it('does not show a dropdown', () => {
            expect(fixture.nativeElement.querySelector('select')).toEqual(null);
        });

        it('does not show a notice', () => {
            expect(fixture.nativeElement.querySelector('.alert.alert-primary')).toEqual(null);
        });
    });

    describe('when subscriptions have loaded, but are empty', () => {
        beforeEach(() => {
            component.findSubscriptions();

            // Reset the subscriptionList to an empty array, to simulate
            // the case when pcrud returned no results
            component.subscriptionList = [];
            fixture.detectChanges();
        });

        it('does not show a dropdown', () => {
            expect(fixture.nativeElement.querySelector('select')).toEqual(null);
        });

        it('shows a notice', () => {
            expect(fixture.nativeElement.querySelector('.alert.alert-primary').innerText)
                .toContain('There is no serials subscription');
        });
    });

    describe('when subscriptions have loaded, and there is at least one', () => {
        beforeEach(() => {
            component.findSubscriptions();
            fixture.detectChanges();
        });

        it('shows a dropdown', () => {
            expect(fixture.nativeElement.querySelector('select')).toBeTruthy();
            expect(fixture.nativeElement.querySelectorAll('option')).toHaveSize(1);
        });

        it('does not show a notice', () => {
            expect(fixture.nativeElement.querySelector('.alert.alert-primary')).toEqual(null);
        });
    });

    describe('Continue button', () => {
        it('emits the selected id', waitForAsync(() => {
            spyOn(component.subscriptionSelected, 'emit');
            component.findSubscriptions();
            fixture.whenStable();
            fixture.detectChanges();

            fixture.nativeElement.querySelector('button').click();
            expect(component.subscriptionSelected.emit).toHaveBeenCalledWith(12);
        }));
    });
});
