import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ItemLocationSelectComponent } from './item-location-select.component';
import { IdlService } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { AuthService } from '@eg/core/auth.service';
import { PermService } from '@eg/core/perm.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { ItemLocationService } from './item-location-select.service';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { CommonWidgetsModule } from '../common-widgets.module';
import { MockGenerators } from 'test_data/mock_generators';

describe('ItemLocationSelectComponent', () => {
    let component: ItemLocationSelectComponent;
    let fixture: ComponentFixture<ItemLocationSelectComponent>;
    const location = MockGenerators.idlObject({id: 1, name: 'My Location'});

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [CommonWidgetsModule],
            declarations: [ ItemLocationSelectComponent ],
            providers: [
                ItemLocationService,
                { provide: IdlService, useValue: {} },
                { provide: OrgService, useValue: {ancestors: () => []} },
                { provide: AuthService, useValue: {} },
                { provide: PermService, useValue: {} },
                { provide: PcrudService, useValue: MockGenerators.pcrudService({search: location}) },
            ],
            schemas: [CUSTOM_ELEMENTS_SCHEMA]
        })
            .compileComponents();
    });

    beforeEach(() => {
        fixture = TestBed.createComponent(ItemLocationSelectComponent);
        component = fixture.componentInstance;
        component.contextOrgId = 1;
        fixture.detectChanges();
    });

    it('does not include an aria-labelledby if it is not provided', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.hasAttribute('aria-labelledby')).toBeFalse();
    });

    it('should include an aria-labelledby if it is provided', () => {
        component.ariaLabelledby = 'someElementId';
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('input[aria-labelledby="someElementId"]')).toBeTruthy();
    });
});
