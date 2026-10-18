import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldGroupsComponent } from './hold-groups.component';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { HoldGroupsService } from './hold-groups.service';
import { MockGenerators } from 'test_data/mock_generators';
import { NgbNavModule } from '@ng-bootstrap/ng-bootstrap';

describe('HoldGroupsComponent', () => {
    let component: HoldGroupsComponent;
    let fixture: ComponentFixture<HoldGroupsComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [HoldGroupsComponent],
            providers: MockGenerators.providers([
                {provide: HoldGroupsService, useValue: {userBucket: () => {}}},
            ])
        });
        TestBed.overrideComponent(HoldGroupsComponent, {set:{imports:[NgbNavModule],schemas:[CUSTOM_ELEMENTS_SCHEMA]}});

        fixture = TestBed.createComponent(HoldGroupsComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
