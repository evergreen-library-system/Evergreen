import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CircModifierComponent } from './circ-modifier.component';
import { AdminCommonModule } from '../common.module';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { PcrudService } from '@eg/core/pcrud.service';
import { MockGenerators } from 'test_data/mock_generators';
import { IdlService } from '@eg/core/idl.service';

describe('CircModifierComponent', () => {
    let component: CircModifierComponent;
    let fixture: ComponentFixture<CircModifierComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [CircModifierComponent],
            providers: [
                {provide: PcrudService, useValue: MockGenerators.pcrudService({})},
                {provide: IdlService, useValue: MockGenerators.idlService({ ccm: { pkey: 'code' } })}
            ]
        });

        TestBed.overrideComponent(CircModifierComponent, {
            remove: {imports: [AdminCommonModule]},
            add: {schemas: [CUSTOM_ELEMENTS_SCHEMA]}
        });

        fixture = TestBed.createComponent(CircModifierComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
