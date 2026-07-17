import { IdlObject, IdlService } from '@eg/core/idl.service';
import { VolEditComponent } from './vol-edit.component';
import { VolCopyContext } from './volcopy';
import { TestBed } from '@angular/core/testing';
import { Renderer2 } from '@angular/core';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';
import { VolCopyService } from './volcopy.service';

describe('VolEditComponent', () => {
    let component: VolEditComponent;
    beforeEach(() => {
        TestBed.configureTestingModule({providers: [
            {provide: Renderer2, useValue: null},
            {provide: IdlService, useValue: null},
            {provide: OrgService, useValue: null},
            {provide: PcrudService, useValue: null},
            {provide: NetService, useValue: null},
            {provide: AuthService, useValue: null},
            {provide: VolCopyService, useValue: null}
        ]});
        component = TestBed.createComponent(VolEditComponent).componentInstance;
        const context = jasmine.createSpyObj<VolCopyContext>(['copyList', 'volNodes']);
        context.copyList.and.returnValue([]);
        context.volNodes.and.returnValue([]);
        component.context = context;
    });
    describe('applyVolValue', () => {
        let callNumber: IdlObject;
        let ischangedValue: string[];
        beforeEach(() => {
            ischangedValue = [];
            callNumber = jasmine.createSpyObj<IdlObject>(['prefix', 'suffix', 'classification', 'ischanged']);
            callNumber.prefix.and.returnValue(10);
            callNumber.suffix.and.returnValue(25);
            callNumber.classification.and.returnValue(1);
            callNumber.ischanged.and.callFake((newValue: string[]) => {
                if (newValue) {
                    ischangedValue = newValue;
                } else {
                    return ischangedValue;
                }
            });
        });
        it('indicates which call number fields were changed', () => {
            component.applyVolValue(callNumber, 'prefix', 100);
            expect(callNumber.ischanged).toHaveBeenCalledWith(['prefix']);
        });
        describe('when called multiple times', () => {
            it('records all the fields that have been changed', () => {
                component.applyVolValue(callNumber, 'prefix', 100);
                component.applyVolValue(callNumber, 'classification', 2);
                expect(callNumber.ischanged).toHaveBeenCalledWith(['prefix', 'classification']);
            });
        });
    });
});
