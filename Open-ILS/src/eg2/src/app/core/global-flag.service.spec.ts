import { MockGenerators } from 'test_data/mock_generators';
import { GlobalFlagService } from './global-flag.service';
import { PcrudService } from './pcrud.service';
import { IdlObject } from './idl.service';

let mockFlag: jasmine.SpyObj<IdlObject>;
let mockPcrud: jasmine.SpyObj<PcrudService>;

describe('GlobalFlagService', () => {
    beforeEach(() => {
        mockFlag = MockGenerators.idlObject({
            label: 'Staff Catalog Search: Display shelving location groups with library groups'
        });
        mockPcrud = MockGenerators.pcrudService({
            search: [mockFlag]
        });
    });
    describe('retrieve()', () => {
        it('retrieves global flag values', () => {
            const service = new GlobalFlagService(mockPcrud);

            service.retrieve('staff.search.shelving_location_groups_with_lassos').subscribe((flag) => {
                expect(flag.label()).toEqual(
                    'Staff Catalog Search: Display shelving location groups with library groups'
                );
            });
        });
        it('does not re-request the global flag data after an initial request', async () => {
            const service = new GlobalFlagService(mockPcrud);

            service.retrieve('staff.search.shelving_location_groups_with_lassos').subscribe((flag) => {
                expect(flag.label()).toEqual(
                    'Staff Catalog Search: Display shelving location groups with library groups'
                );
            });
            expect(mockPcrud.search.calls.count()).toEqual(1);

            service.retrieve('staff.search.shelving_location_groups_with_lassos').subscribe((flag) => {
                expect(flag.label()).toEqual(
                    'Staff Catalog Search: Display shelving location groups with library groups'
                );
            });
            expect(mockPcrud.search.calls.count()).toEqual(1); // still just 1 call to Pcrud
        });
    });
    describe('enabled()', () => {
        describe('when the flag is enabled', () => {
            beforeEach(() => {
                mockFlag = MockGenerators.idlObject({
                    enabled: 't'
                });
                mockPcrud = MockGenerators.pcrudService({
                    search: [mockFlag]
                });
            });
            it('returns true', () => {
                const service = new GlobalFlagService(mockPcrud);
                service.enabled('staff.search.shelving_location_groups_with_lassos').subscribe((enabled) => {
                    expect(enabled).toEqual(true);
                });
            });

        });
        describe('when the flag is not enabled', () => {
            beforeEach(() => {
                mockFlag = MockGenerators.idlObject({
                    enabled: 'f'
                });
                mockPcrud = MockGenerators.pcrudService({
                    search: [mockFlag]
                });
            });
            it('returns false', () => {
                const service = new GlobalFlagService(mockPcrud);
                service.enabled('staff.search.shelving_location_groups_with_lassos').subscribe((enabled) => {
                    expect(enabled).toEqual(false);
                });
            });

        });
        describe('when there is no such global flag', () => {
            beforeEach(() => {
                mockPcrud = MockGenerators.pcrudService({
                    search: [] // no values emitted
                });
            });
            it('returns false', () => {
                const service = new GlobalFlagService(mockPcrud);
                service.enabled('does.not.exist').subscribe((enabled) => {
                    expect(enabled).toEqual(false);
                });
            });
            it('returns the default value if specified', () => {
                const service = new GlobalFlagService(mockPcrud);
                service.enabled('does.not.exist', true).subscribe((enabled) => {
                    expect(enabled).toEqual(true);
                });
            });

        });
    });
});
