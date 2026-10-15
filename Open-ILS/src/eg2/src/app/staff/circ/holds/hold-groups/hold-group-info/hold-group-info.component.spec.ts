import { ComponentFixture, TestBed } from '@angular/core/testing';

import { HoldGroupInfoComponent } from './hold-group-info.component';

describe('HoldGroupInfoComponent', () => {
    let component: HoldGroupInfoComponent;
    let fixture: ComponentFixture<HoldGroupInfoComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [HoldGroupInfoComponent]
        })
            .compileComponents();

        fixture = TestBed.createComponent(HoldGroupInfoComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
