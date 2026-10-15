import { ComponentFixture, TestBed } from '@angular/core/testing';

import { HoldGroupsComponent } from './hold-groups.component';

describe('HoldGroupsComponent', () => {
    let component: HoldGroupsComponent;
    let fixture: ComponentFixture<HoldGroupsComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [HoldGroupsComponent]
        })
            .compileComponents();

        fixture = TestBed.createComponent(HoldGroupsComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
