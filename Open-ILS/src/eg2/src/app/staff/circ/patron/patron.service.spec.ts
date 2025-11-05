import { MockGenerators } from 'test_data/mock_generators';
import { TestBed } from '@angular/core/testing';
import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { StoreService } from '@eg/core/store.service';
import { CircService } from '@eg/staff/share/circ/circ.service';
import { PatronService, PatronSummary} from '@eg/staff/share/patron/patron.service';
import { PatronContextService } from './patron.service';

describe('PatronContextService', () => {
    const mockStore = MockGenerators.storeService(null);
    const mockServerStore = MockGenerators.serverStoreService(null);
    const mockOrg = MockGenerators.orgService();
    const mockCirc = {};
    const mockPatron = jasmine.createSpyObj<PatronService>('Patron',
        ['formatSupportedSettings']
    );

    beforeEach(() => {
        TestBed.configureTestingModule({ providers: [
            PatronContextService,
            { provide: StoreService, useValue: mockStore },
            { provide: ServerStoreService, useValue: mockServerStore },
            { provide: OrgService, useValue: mockOrg },
            { provide: CircService, useValue: mockCirc },
            { provide: PatronService, useValue: mockPatron }
        ] });
    });

    describe('formatPatronSettings()', () => {
        it('loads patron summary settings', async () => {
            const label = 'Setting Label';
            const name = 'setting.name';
            const value = 'setting.value';

            mockPatron.formatSupportedSettings.and.resolveTo([{
                label, value
            }]);

            const service = TestBed.inject(PatronContextService);

            const settings = [MockGenerators.idlObject({ name, value })];
            const user = MockGenerators.idlObject({ id: 42, settings });
            service.summary = new PatronSummary(user);

            await service.formatSummaryUserSettings();

            expect(
                mockPatron.formatSupportedSettings
            ).toHaveBeenCalledWith(
                service.summary.patron.settings()
            );

            expect(service.summary.settings).toEqual([{
                label, value
            }]);
        });
    });
});
