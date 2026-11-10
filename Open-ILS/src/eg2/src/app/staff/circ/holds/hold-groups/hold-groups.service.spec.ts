import { TestBed } from '@angular/core/testing';
import { HoldGroupsService } from './hold-groups.service';
import { PcrudService } from '@eg/core/pcrud.service';

describe('HoldGroupsService', () => {
    let service: HoldGroupsService;

    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [
                {provide: PcrudService, useValue: {}}
            ]
        });
        service = TestBed.inject(HoldGroupsService);
    });

    it('should be created', () => {
        expect(service).toBeTruthy();
    });
});
