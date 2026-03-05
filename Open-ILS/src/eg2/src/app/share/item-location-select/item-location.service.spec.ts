import { TestBed } from '@angular/core/testing';
import { PcrudService } from '@eg/core/pcrud.service';
import { MockGenerators } from 'test_data/mock_generators';
import { ItemLocationService } from './item-location.service';

describe('ItemLocationService', () => {
    beforeEach(() => {
        const locations = [
            MockGenerators.idlObject({id: 2, name: 'Romance'}),
        ];
        const mockPcrud = MockGenerators.pcrudService({retrieve: locations});
        TestBed.configureTestingModule({providers: [
            ItemLocationService,
            {provide: PcrudService, useValue: mockPcrud}
        ]});
    });
    describe('getById()', () => {
        it('returns the requested id', () => {
            const service = TestBed.inject(ItemLocationService);
            service.getById(2).subscribe((location) => {
                expect(location.id()).toEqual(2);
                expect(location.name()).toEqual('Romance');
            });
        });
    });
});
