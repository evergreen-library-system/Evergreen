import { TestBed } from '@angular/core/testing';

import { HoldGroupsService } from './hold-groups.service';

describe('HoldGroupsServiceService', () => {
    let service: HoldGroupsService;

    beforeEach(() => {
        TestBed.configureTestingModule({});
        service = TestBed.inject(HoldGroupsService);
    });

    it('should be created', () => {
        expect(service).toBeTruthy();
    });
});
