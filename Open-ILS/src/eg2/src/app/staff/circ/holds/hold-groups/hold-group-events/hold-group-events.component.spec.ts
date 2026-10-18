import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldGroupEventsComponent } from './hold-group-events.component';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { HoldGroupsService } from '../hold-groups.service';
import { MockGridComponent } from 'test_data/mock-components';
import { MockGenerators } from 'test_data/mock_generators';
import { FormsModule } from '@angular/forms';

describe('HoldGroupEventsComponent', () => {
    let component: HoldGroupEventsComponent;
    let fixture: ComponentFixture<HoldGroupEventsComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [HoldGroupEventsComponent],
            providers: MockGenerators.providers([
                {provide: HoldGroupsService, useValue: {userBucket: () => {}}},
            ])
        });
        TestBed.overrideComponent(HoldGroupEventsComponent, {set:{
            imports:[MockGridComponent, FormsModule],
            schemas:[CUSTOM_ELEMENTS_SCHEMA]
        }});

        fixture = TestBed.createComponent(HoldGroupEventsComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
