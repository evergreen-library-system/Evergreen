import { ComponentFixture, TestBed } from '@angular/core/testing';

import { SortOrderSelectComponent } from './sort-order-select.component';
import { FormsModule } from '@angular/forms';

describe('SortOrderSelectComponent', () => {
    let component: SortOrderSelectComponent;
    let fixture: ComponentFixture<SortOrderSelectComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            declarations: [ SortOrderSelectComponent ],
            imports: [FormsModule]
        })
            .compileComponents();

        fixture = TestBed.createComponent(SortOrderSelectComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
        expect(component.sortOrder).toBeTruthy();
    });
});
