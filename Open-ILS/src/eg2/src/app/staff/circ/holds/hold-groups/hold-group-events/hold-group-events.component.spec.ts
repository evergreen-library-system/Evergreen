import { ComponentFixture, TestBed } from '@angular/core/testing';

import { HoldGroupEventsComponent } from './hold-group-events.component';

describe('HoldGroupEventsComponent', () => {
    let component: HoldGroupEventsComponent;
    let fixture: ComponentFixture<HoldGroupEventsComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [HoldGroupEventsComponent]
        })
            .compileComponents();

        fixture = TestBed.createComponent(HoldGroupEventsComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
