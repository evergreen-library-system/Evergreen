import { MockGenerators } from 'test_data/mock_generators';
import { AuthService } from '@eg/core/auth.service';
import { EventService } from '@eg/core/event.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { TestBed } from '@angular/core/testing';
import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { PatronService } from '@eg/staff/share/patron/patron.service';
import { of } from 'rxjs';
import { IdlObject } from '@eg/core/idl.service';

const MOCK_USER_SETTING_TYPES = [
    {
        datatype: 'string',
        label: 'Default Phone Number',
        name: 'opac.default_phone',
    },
    {
        datatype: 'integer',
        label: 'Default Hold Pickup Location',
        name: 'opac.default_pickup_location',
    },
    {
        datatype: 'bool',
        label: 'Hold is behind Circ Desk',
        name: 'circ.holds_behind_desk',
    },
    {
        datatype: 'bool',
        label: 'Collections: Exempt',
        name: 'circ.collections.exempt',
    },
    {
        datatype: 'string',
        label: 'Hold Notification Format',
        name: 'opac.hold_notify',
    },
    {
        datatype: 'string',
        label: 'Default SMS/Text Number',
        name: 'opac.default_sms_notify',
    },
    {
        datatype: 'link',
        label: 'Default SMS/Text Carrier',
        name: 'opac.default_sms_carrier',
    }
];

const MOCK_USER_SETTINGS = [
    { name: 'opac.default_phone', value: '"1234567890"' },
    { name: 'opac.default_pickup_location', value: '1' },
    { name: 'circ.holds_behind_desk', value: 'true' },
    { name: 'circ.collections.exempt', value: 'false' },
    { name: 'opac.hold_notify', value: '"phone:email:sms"' },
    { name: 'opac.default_sms_notify', value: '"1234567891"' },
    { name: 'opac.default_sms_carrier', value: '1' }
];

describe('PatronService', () => {
    let mockNet: jasmine.SpyObj<NetService>;
    let mockOrg: jasmine.SpyObj<OrgService>;
    let mockEvent: jasmine.SpyObj<EventService>;
    let mockPcrud: jasmine.SpyObj<PcrudService>;
    let mockAuth: jasmine.SpyObj<AuthService>;
    let mockServerStore: jasmine.SpyObj<ServerStoreService>;

    const config = () => {
        mockNet = MockGenerators.netService({});
        mockOrg = jasmine.createSpyObj<OrgService>(['ancestors', 'get']);
        mockOrg.ancestors.and.returnValue([]);
        mockEvent = jasmine.createSpyObj<EventService>(['parse']);
        mockPcrud = jasmine.createSpyObj<PcrudService>(['search']);
        mockAuth = MockGenerators.authService();
        mockServerStore = jasmine.createSpyObj<ServerStoreService>(['getItemBatch']);

        TestBed.configureTestingModule({ providers: [
            PatronService,
            { provide: NetService, useValue: mockNet },
            { provide: OrgService, useValue: mockOrg },
            { provide: EventService, useValue: mockEvent },
            { provide: PcrudService, useValue: mockPcrud },
            { provide: AuthService, useValue: mockAuth },
            { provide: ServerStoreService, useValue: mockServerStore }
        ] });
    };

    beforeEach(() => { config(); });

    describe('getUserSettingTypes()', async () => {
        it('returns cached user setting types if available', async () => {
            const name = 'setting.name';
            const cust = MockGenerators.idlObject({ name });
            const settingTypes = { [name]: cust };
            mockPcrud.search.and.returnValue(of('should not be called'));

            const service = TestBed.inject(PatronService);
            service.userSettingTypes = settingTypes;
            const result = await service.getUserSettingTypes();

            expect(mockPcrud.search).not.toHaveBeenCalled();
            expect(result).toEqual(settingTypes);
        });

        it('retrieves user setting types if not cached', async () => {
            const name = 'setting.name';
            const settingTypes = [MockGenerators.idlObject({ name })];
            mockPcrud.search.and.returnValue(of(settingTypes));

            const service = TestBed.inject(PatronService);
            const result = await service.getUserSettingTypes();

            expect(result).toEqual({ [name]: settingTypes[0] });
        });
    });

    describe('formatSupportedSettings()', () => {
        let settings: jasmine.SpyObj<IdlObject>[];
        const orgShortname = 'CONS';

        beforeEach(() => {
            config();

            mockOrg.get.and.callFake((orgId: number) => {
                const orgs = [MockGenerators.idlObject({
                    id: 1, shortname: orgShortname
                })];
                return orgs.find(o => o.id() === orgId) || null;
            });

            mockPcrud.search.and.callFake((fmclass: string) => {
                if (fmclass === 'cust') {
                    return of(MOCK_USER_SETTING_TYPES.map(
                        type => MockGenerators.idlObject({ ...type })
                    ));
                }
                if (fmclass === 'csc') {
                    return of(
                        MockGenerators.idlObject({id: 1, name: 'ExpectACarrier' })
                    );
                }
                return of([]);
            });

            settings = MOCK_USER_SETTINGS.map(
                setting => MockGenerators.idlObject({ ...setting })
            );
        });

        it('returns label and formatted value for supported settings', async () => {
            mockServerStore.getItemBatch.and.resolveTo({
                'circ.holds.behind_desk_pickup_supported': true,
                'sms.enable': true
            });

            const service = TestBed.inject(PatronService);
            const result = await service.formatSupportedSettings(settings);

            expect(result).toEqual([
                { label: 'Default Phone Number', value: '1234567890' },
                { label: 'Default Hold Pickup Location', value: orgShortname },
                { label: 'Hold is behind Circ Desk', value: 'Yes' },
                { label: 'Collections: Exempt', value: 'No' },
                { label: 'Hold Notification Format', value: 'Phone, Email, SMS' },
                { label: 'Default SMS/Text Number', value: '1234567891' },
                { label: 'Default SMS/Text Carrier', value: 'ExpectACarrier' }
            ]);
        });

        it('omits unsupported settings', async () => {
            mockServerStore.getItemBatch.and.resolveTo({
                'circ.holds.behind_desk_pickup_supported': false,
                'sms.enable': false
            });

            const service = TestBed.inject(PatronService);
            const result = await service.formatSupportedSettings(settings);

            expect(result).toEqual([
                { label: 'Default Phone Number', value: '1234567890' },
                { label: 'Default Hold Pickup Location', value: orgShortname },
                { label: 'Collections: Exempt', value: 'No' },
                { label: 'Hold Notification Format', value: 'Phone, Email, SMS' }
            ]);
        });
    });
});
