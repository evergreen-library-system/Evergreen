import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute } from '@angular/router';
import { QuickReceiveComponent } from './quick-receive.component';
import { NO_ERRORS_SCHEMA } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';
import { EMPTY, from, of } from 'rxjs';
import { MockGenerators } from 'test_data/mock_generators';

const sitemMock = MockGenerators.idlObject({
    stream: MockGenerators.idlObject({id: 3}),
    issuance: MockGenerators.idlObject({date_published: '2020-01-01T10:00:00-0600'}),
});

describe('QuickReceiveComponent', () => {
    let component: QuickReceiveComponent;
    let fixture: ComponentFixture<QuickReceiveComponent>;
    const routeMock = { snapshot: { params: {bibRecordId: 1}}};
    const netMock = jasmine.createSpyObj<NetService>(['request']);
    netMock.request.and.returnValue(of());
    const authMock = MockGenerators.authService();

    beforeEach(async () => {
        TestBed.overrideComponent(QuickReceiveComponent, {set: {
            imports: [CommonModule],
            schemas: [NO_ERRORS_SCHEMA],
            providers: [
                {provide: ActivatedRoute, useValue: routeMock},
                {provide: AuthService, useValue: authMock},
                {provide: NetService, useValue: netMock}
            ]
        }});
        fixture = TestBed.createComponent(QuickReceiveComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    describe('checkForExpectedItems()', () => {
        it('calls the expected items OpenSRF methods', async () => {
            netMock.request.and.returnValue(of(sitemMock));
            await component.checkForExpectedItems(12);
            expect(netMock.request).toHaveBeenCalledWith(
                'open-ils.serial',
                'open-ils.serial.items.receivable.by_subscription',
                'MY_AUTH_TOKEN',
                12);
        });
        it('gives a notice if there are no receivable items', async () => {
            netMock.request.and.returnValues(EMPTY, of());
            component.checkForExpectedItems(12).catch(() => {
                fixture.detectChanges();

                expect(fixture.nativeElement.querySelector('[role="alert"]').innerText)
                    .toContain('This subscription doesn\'t have any expected items');
            });
        });
        it('does not show a notice if there is a receivable item', async () => {
            netMock.request.and.returnValue(of(sitemMock));
            await component.checkForExpectedItems(12);
            fixture.detectChanges();

            expect(fixture.nativeElement.querySelector('[role="alert"]')).toEqual(null);
        });
        describe('when there are multiple items on a given stream', () => {
            it('takes the one with the most recent issuance date', async () => {
                const earlierSitemMock = MockGenerators.idlObject({
                    stream: MockGenerators.idlObject({id: 3}),
                    issuance: MockGenerators.idlObject({date_published: '2019-12-25T10:00:00-0600'}),
                });
                netMock.request.and.returnValues(from([sitemMock, earlierSitemMock]));
                await component.checkForExpectedItems(12);

                expect(component.fleshedSitems).toEqual([earlierSitemMock]);
            });
        });
        describe('when there are multiple streams', () => {
            it('takes one item from each stream', async () => {
                const otherStreamMock = MockGenerators.idlObject({
                    stream: MockGenerators.idlObject({id: 12}),
                    issuance: MockGenerators.idlObject({date_published: '2019-12-25T10:00:00-0600'}),
                });
                netMock.request.and.returnValues(from([sitemMock, otherStreamMock]));
                await component.checkForExpectedItems(12);

                expect(component.fleshedSitems).toContain(sitemMock);
                expect(component.fleshedSitems).toContain(otherStreamMock);
                expect(component.fleshedSitems.length).toEqual(2);
            });
        });
    });
});
