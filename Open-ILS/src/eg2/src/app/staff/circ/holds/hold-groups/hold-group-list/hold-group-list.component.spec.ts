import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldGroupListComponent } from './hold-group-list.component';
import { MockGenerators } from 'test_data/mock_generators';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { MockGridComponent } from 'test_data/mock-components';

describe('HoldGroupListComponent', () => {
    let component: HoldGroupListComponent;
    let fixture: ComponentFixture<HoldGroupListComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [HoldGroupListComponent]
        });

        TestBed.configureTestingModule({providers: MockGenerators.providers()});
        TestBed.overrideComponent(HoldGroupListComponent, {set:{imports: [MockGridComponent], schemas:[CUSTOM_ELEMENTS_SCHEMA]}});

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
