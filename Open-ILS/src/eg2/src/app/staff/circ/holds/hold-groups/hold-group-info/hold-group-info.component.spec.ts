import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldGroupInfoComponent } from './hold-group-info.component';
import { HoldGroupsService } from '../hold-groups.service';
import { MockGenerators } from 'test_data/mock_generators';

describe('HoldGroupInfoComponent', () => {
    let component: HoldGroupInfoComponent;
    let fixture: ComponentFixture<HoldGroupInfoComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [HoldGroupInfoComponent],
            providers: MockGenerators.providers([{provide: HoldGroupsService, useValue: MockGenerators.holdGroupsService()}])
        });

        fixture = TestBed.createComponent(HoldGroupInfoComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
