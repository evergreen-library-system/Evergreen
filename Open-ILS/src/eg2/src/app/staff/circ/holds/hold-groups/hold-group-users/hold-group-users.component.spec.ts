import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldGroupUsersComponent } from './hold-group-users.component';
import { HoldGroupsService } from '../hold-groups.service';
import { MockGenerators } from 'test_data/mock_generators';
import { NO_ERRORS_SCHEMA } from '@angular/core';
import { MockComboboxComponent, MockGridComponent } from 'test_data/mock-components';
import { FormsModule } from '@angular/forms';

describe('HoldGroupUsersComponent', () => {
    let component: HoldGroupUsersComponent;
    let fixture: ComponentFixture<HoldGroupUsersComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [HoldGroupUsersComponent],
            providers: MockGenerators.providers([
                {provide: HoldGroupsService, useValue: MockGenerators.holdGroupsService()}
            ])
        });

        TestBed.overrideComponent(HoldGroupUsersComponent, {set: {
            imports: [MockGridComponent, FormsModule, MockComboboxComponent],
            schemas: [NO_ERRORS_SCHEMA]
        }});

        fixture = TestBed.createComponent(HoldGroupUsersComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('should disable the actions if no rows are selected', () => {
        expect(component.hasNoSelectedUsers()).toBeTrue();
    });
});
