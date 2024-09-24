import { MockGenerators } from 'test_data/mock_generators';
import { AuthService } from './auth.service';

describe('auth service', () => {
    describe('testAuthToken()', () => {
        it('does not set token() if the store service can find no existing token', async () => {
            const service = new AuthService(null, null, MockGenerators.storeService(null));
            await expectAsync(service.testAuthToken()).toBeRejected();

            expect(service.token()).toBeNull();
        });
        it('does not think there is a provisional token if the store service can find no existing token', async () => {
            const service = new AuthService(null, null, MockGenerators.storeService(null));
            await expectAsync(service.testAuthToken()).toBeRejected();

            expect(service.provisional()).toBeFalse();
        });
    });
});
