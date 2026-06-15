import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ManageHoldNotesComponent } from './manage-hold-notes.component';
import { HoldNotesService } from './hold-notes.service';
import { ToastService } from '@eg/share/toast/toast.service';

describe('ManageHoldNotesComponent', () => {
    let component: ManageHoldNotesComponent;
    let fixture: ComponentFixture<ManageHoldNotesComponent>;

    beforeEach(async () => {
        TestBed.configureTestingModule({
            imports: [ManageHoldNotesComponent],
            providers: [
                {provide: HoldNotesService, useValue: {}},
                {provide: ToastService, useValue: {}}
            ]
        });

        fixture = TestBed.createComponent(ManageHoldNotesComponent);
        component = fixture.componentInstance;
        await fixture.whenStable();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
