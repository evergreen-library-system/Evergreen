import { TestBed } from '@angular/core/testing';
import { ItemLocationService } from './item-location.service';
import { MockGenerators } from 'test_data/mock_generators';
import { OrgService } from '@eg/core/org.service';
import { BasicItemLocationDisplayComponent } from './basic-item-location-display-component';

describe('BasicItemLocationDisplayComponent', () => {
    it('displays the name and org unit of a shelving location', () => {
        TestBed.configureTestingModule({providers: [
            {provide: ItemLocationService, useValue: MockGenerators.itemLocationService()},
            {provide: OrgService, useValue: MockGenerators.orgService()}
        ]});
        const fixture = TestBed.createComponent(BasicItemLocationDisplayComponent);
        fixture.detectChanges();
        expect(fixture.nativeElement.textContent).toEqual('Romance fiction (MYLIB)');
    });
});
