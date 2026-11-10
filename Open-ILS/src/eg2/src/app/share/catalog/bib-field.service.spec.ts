import { TestBed } from '@angular/core/testing';
import { BibFieldService } from './bib-field.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { MockGenerators } from 'test_data/mock_generators';

let mockPcrud;

describe('BibFieldService', () => {
    let service: BibFieldService;

    beforeEach(() => {
        mockPcrud = MockGenerators.pcrudService({});
        TestBed.configureTestingModule({
            providers: [{provide: PcrudService, useValue: mockPcrud}]
        });
        service = TestBed.inject(BibFieldService);
    });

    it('should be created', () => {
        expect(service).toBeTruthy();
    });
});
