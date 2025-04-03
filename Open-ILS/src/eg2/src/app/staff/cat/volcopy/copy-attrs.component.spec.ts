import { IdlService, IdlObject } from './../../../core/idl.service';
import { QueryList } from '@angular/core';
import { waitForAsync } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { FormatService } from '@eg/core/format.service';
import { OrgService } from '@eg/core/org.service';
import { StoreService } from '@eg/core/store.service';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';
import { ToastService } from '@eg/share/toast/toast.service';
import { CopyAttrsComponent } from './copy-attrs.component';
import { VolCopyContext, HoldingsTreeNode } from './volcopy';
import { VolCopyService } from './volcopy.service';
import { StringComponent } from '@eg/share/string/string.component';

describe('CopyAttrsComponent', () => {
    let component: CopyAttrsComponent;
    const idlMock = jasmine.createSpyObj<IdlService>(['clone']);
    const orgMock = jasmine.createSpyObj<OrgService>(['get']);
    const authServiceMock = jasmine.createSpyObj<AuthService>(['user']);
    const formatServiceMock = jasmine.createSpyObj<FormatService>(['transform']);
    const storeServiceMock = jasmine.createSpyObj<StoreService>(['setLocalItem', 'getLocalItem']);
    const toastServiceMock = jasmine.createSpyObj<ToastService>(['success']);
    const volCopyServiceMock = jasmine.createSpyObj<VolCopyService>(['copyStatIsMagic', 'saveTemplates']);

    beforeEach(() => {
        component = new CopyAttrsComponent(idlMock, orgMock, authServiceMock,
            null, formatServiceMock, storeServiceMock,
            toastServiceMock, volCopyServiceMock);
        component.copyTemplateCbox = jasmine.createSpyObj<ComboboxComponent>(['entries']);
        component.copyTemplateCbox.selected = {id: 0};
    });
    describe('#applyTemplate', () => {
        describe('status field', () => {
            it('does not apply a magic status to an item', waitForAsync(() => {
                const template = { 'status': 1 };
                volCopyServiceMock.templates = [template];
                volCopyServiceMock.copyStatIsMagic.and.returnValue(true);
                component.batchAttrs = new QueryList();

                spyOn(component, 'applyTemplate').and.callThrough();
                spyOn(component, 'applyCopyValue').and.callThrough();

                component.applyTemplate();
                expect(component.applyCopyValue).not.toHaveBeenCalled();
            }));
        });
        describe('call number fields', () => {
            it('marks the fields as ischanged', () => {
                const template = { 'callnumber': {'prefix': 10, 'suffix': 20, 'classification': 3} };
                volCopyServiceMock.templates = {0: template};
                volCopyServiceMock.copyStatIsMagic.and.returnValue(true);
                component.batchAttrs = new QueryList();

                spyOn(component, 'applyTemplate').and.callThrough();
                spyOn(component, 'applyCopyValue').and.callThrough();
                let ischangedValue = [];
                const callNumber = jasmine.createSpyObj<IdlObject>(['ischanged', 'label_class', 'prefix', 'suffix']);
                callNumber.ischanged.and.callFake((newValue: string[]) => {
                    if (newValue) {
                        ischangedValue = newValue;
                    } else {
                        return ischangedValue;
                    }
                });

                // Assume that the existing call number only has default values
                callNumber.label_class.and.returnValue(1);
                callNumber.prefix.and.returnValue(-1);
                callNumber.suffix.and.returnValue(-1);

                const node = new HoldingsTreeNode();
                node.target = callNumber;
                const contextMock = jasmine.createSpyObj<VolCopyContext>(['copyList', 'volNodes']);
                contextMock.volNodes.and.returnValue([node]);
                contextMock.copyList.and.returnValue([]);
                component.context = contextMock;

                component.applyTemplate();
                expect(callNumber.ischanged).toHaveBeenCalledWith(['prefix', 'suffix', 'label_class']);
                expect(callNumber.prefix).toHaveBeenCalledWith(10);
                expect(callNumber.suffix).toHaveBeenCalledWith(20);
                expect(callNumber.label_class).toHaveBeenCalledWith(3);
            });
        });
    });
    describe('#applyCopyValue', () => {
        it('does not override a magic status', () => {
            volCopyServiceMock.copyStatIsMagic.and.returnValue(true);
            // eslint-disable-next-line no-unused-expressions
            const item = jasmine.createSpyObj<IdlObject>(['ischanged'], {'status': () => {1;}});
            const contextMock = jasmine.createSpyObj<VolCopyContext>(['copyList']);
            contextMock.copyList.and.returnValue([item]);
            component.context = contextMock;
            spyOn(component, 'emitSaveChange');

            component.applyCopyValue('status', 0);
            expect(item.ischanged).not.toHaveBeenCalled();
        });
    });
    describe('saveTemplate()', () => {
        describe('when call number prefix has changed', () => {
            it('includes call number prefix, but not other fields, in the template', () => {
                volCopyServiceMock.saveTemplates.and.returnValue(Promise.resolve());
                const savedString = jasmine.createSpyObj<StringComponent>(['current']);
                savedString.current.and.returnValue(Promise.resolve('saved'));
                component.savedHoldingsTemplates = savedString;

                // Assume that there already is a template by this name
                component.volcopy.templates = {0: {}};

                // Assume that we've selected a new prefix in the editor
                const callNumber = jasmine.createSpyObj<IdlObject>(['ischanged', 'label_class', 'prefix', 'suffix']);
                callNumber.ischanged.and.returnValue(['prefix']);
                callNumber.label_class.and.returnValue(1);
                callNumber.prefix.and.returnValue(10);
                callNumber.suffix.and.returnValue(25);
                const node = new HoldingsTreeNode();
                node.target = callNumber;
                const contextMock = jasmine.createSpyObj<VolCopyContext>(['volNodes']);
                contextMock.volNodes.and.returnValue([node]);
                component.context = contextMock;

                // Also assume that we have no item fields
                component.batchAttrs = new QueryList();

                component.saveTemplate(false);

                expect(component.volcopy.templates[0]).toEqual({callnumber: {prefix: 10}});
            });
        });
        describe('when multiple fields have changed', () => {
            it('includes all changed fields in the template', () => {
                volCopyServiceMock.saveTemplates.and.returnValue(Promise.resolve());
                const savedString = jasmine.createSpyObj<StringComponent>(['current']);
                savedString.current.and.returnValue(Promise.resolve('saved'));
                component.savedHoldingsTemplates = savedString;

                // Assume that there already is a template by this name
                component.volcopy.templates = {0: {}};

                // Assume that we've selected a new prefix in the editor
                const callNumber = jasmine.createSpyObj<IdlObject>(['ischanged', 'label_class', 'prefix', 'suffix']);
                callNumber.ischanged.and.returnValue(['prefix', 'label_class']);
                callNumber.label_class.and.returnValue(1);
                callNumber.prefix.and.returnValue(10);
                callNumber.suffix.and.returnValue(25);
                const node = new HoldingsTreeNode();
                node.target = callNumber;
                const contextMock = jasmine.createSpyObj<VolCopyContext>(['volNodes']);
                contextMock.volNodes.and.returnValue([node]);
                component.context = contextMock;

                // Also assume that we have no item fields
                component.batchAttrs = new QueryList();

                component.saveTemplate(false);

                expect(component.volcopy.templates[0]).toEqual({callnumber: {prefix: 10, classification: 1}});
            });
        });
    });
});
