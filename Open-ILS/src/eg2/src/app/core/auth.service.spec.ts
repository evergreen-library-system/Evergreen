import { MockGenerators } from 'test_data/mock_generators';
import { AuthService } from './auth.service';
import { TestBed } from '@angular/core/testing';
import { EventService } from './event.service';
import { NetService } from './net.service';
import { StoreService } from './store.service';

describe('auth service', () => {
    describe('testAuthToken()', () => {
        beforeEach(() => {
            TestBed.configureTestingModule({providers: [
                AuthService,
                {provide: EventService, useValue: null},
                {provide: NetService, useValue: null},
                {provide: StoreService, useValue: MockGenerators.storeService(null)}
            ]});
        });
        it('does not set token() if the store service can find no existing token', async () => {
            const service = TestBed.inject(AuthService);
            await expectAsync(service.testAuthToken()).toBeRejected();

            expect(service.token()).toBeNull();
        });
        it('does not think there is a provisional token if the store service can find no existing token', async () => {
            const service = TestBed.inject(AuthService);
            await expectAsync(service.testAuthToken()).toBeRejected();

            expect(service.provisional()).toBeFalse();
        });
    });
});
