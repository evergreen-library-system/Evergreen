import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CopyAlertTypesComponent } from './copy-alert-types.component';
import { AuthService } from '@eg/core/auth.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { MockGenerators } from 'test_data/mock_generators';
import { IdlService } from '@eg/core/idl.service';

describe('CopyAlertTypesComponent', () => {
    let component: CopyAlertTypesComponent;
    let fixture: ComponentFixture<CopyAlertTypesComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            declarations: [ CopyAlertTypesComponent ],
            providers: [
                {provide: AuthService, useValue: MockGenerators.authService()},
                {provide: IdlService, useValue: MockGenerators.idlService({ccat: {pkey: 'id'}})},
                {provide: OrgService, useValue: MockGenerators.orgService()},
                {provide: PcrudService, useValue: MockGenerators.pcrudService({})},
            ],
            schemas: [CUSTOM_ELEMENTS_SCHEMA]
        })
            .compileComponents();

        fixture = TestBed.createComponent(CopyAlertTypesComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});
