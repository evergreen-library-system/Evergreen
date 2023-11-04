import { IdlObject } from '@eg/core/idl.service';
import { VolEditComponent } from './vol-edit.component';
import { VolCopyContext } from './volcopy';

describe('VolEditComponent', () => {
    let component: VolEditComponent;
    beforeEach(() => {
        component = new VolEditComponent(null, null, null, null, null, null, null);
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
