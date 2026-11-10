import { ComponentFixture, TestBed } from '@angular/core/testing';

import { HoldGroupEventMappingInfoDialogComponent } from './hold-group-event-mapping-info-dialog.component';

describe('HoldGroupEventMappingInfoDialogComponent', () => {
    let component: HoldGroupEventMappingInfoDialogComponent;
    let fixture: ComponentFixture<HoldGroupEventMappingInfoDialogComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [HoldGroupEventMappingInfoDialogComponent]
        })
            .compileComponents();

        fixture = TestBed.createComponent(HoldGroupEventMappingInfoDialogComponent);
        component = fixture.componentInstance;
        await fixture.whenStable();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
