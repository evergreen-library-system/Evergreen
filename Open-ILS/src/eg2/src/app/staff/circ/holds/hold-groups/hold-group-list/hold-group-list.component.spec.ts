import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldGroupListComponent } from './hold-group-list.component';

describe('HoldGroupListComponent', () => {
    let component: HoldGroupListComponent;
    let fixture: ComponentFixture<HoldGroupListComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [HoldGroupListComponent]
        })
            .compileComponents();

        fixture = TestBed.createComponent(HoldGroupListComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('should disable buttons without any rows selected', () => {
        spyOn(component.grid.context, 'getSelectedRows').and.returnValue([]);
        expect(component.has_none_selected()).toBeTrue();
    });
});
