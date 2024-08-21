import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { SerialsReceiveComponent } from './serials-receive.component';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import { AuthService } from '@eg/core/auth.service';
import { PermService } from '@eg/core/perm.service';
import { of } from 'rxjs';
import { PrintService } from '@eg/share/print/print.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { MockGenerators } from 'test_data/mock_generators';
import { SerialsService } from './serials.service';

const template = MockGenerators.idlObject({
    circ_modifier: 'DEFAULT',
    location: 180
});
const routingList = [MockGenerators.idlObject({pos: null})];
const subscription = MockGenerators.idlObject({
    notes: [MockGenerators.idlObject({title: 'Don\'t barcode me', value: 'uncheck the barcode checkbox please', alert: 'f'})]
});
const distribution = MockGenerators.idlObject({
    receive_unit_template: template,
    holding_lib: MockGenerators.idlObject({shortname: 'MY_LIB'}),
    notes: [MockGenerators.idlObject({title: 'This is my favorite distribution', value: 'I hope you like it too', alert: 'f'})]
});
const stream = MockGenerators.idlObject({distribution: distribution, routing_list_users: routingList});

let sitem: IdlObject;

describe('SerialsReceiveComponent', () => {
    let component: SerialsReceiveComponent;
    let fixture: ComponentFixture<SerialsReceiveComponent>;

    beforeEach(() => {
        sitem = MockGenerators.idlObject({
            id: 1089,
            notes: [MockGenerators.idlObject({title: 'Watch out!', value: 'This issue includes a lot of glitter', alert: 't'})],
            issuance: MockGenerators.idlObject({label: 'Special issue', subscription: subscription}),
            stream: stream,
            unit: MockGenerators.idlObject({id: null})
        });

        TestBed.overrideComponent(SerialsReceiveComponent, {add: {
            providers: [{provide: PcrudService, useValue: MockGenerators.pcrudService({})},
                {provide: OrgService, useValue: jasmine.createSpyObj<OrgService>(['ancestors'])},
                {provide: AuthService, useValue: MockGenerators.authService()},
                {provide: PermService, useValue: null},
                {provide: PrintService, useValue: jasmine.createSpyObj<PrintService>(['print'])},
                {provide: ToastService, useValue: jasmine.createSpyObj<ToastService>(['success'])},
                {provide: SerialsService, useValue: MockGenerators.serialsService()},
                {provide: IdlService, useValue:
                jasmine.createSpyObj<IdlService>(['getClassSelector'], {classes: {
                    acnp: {pkey: 'id'},
                    acns: {pkey: 'id'},
                    acn: {pkey: 'id'},
                    ccm: {pkey: 'id'}
                }})}
            ]
        }});
        fixture = TestBed.createComponent(SerialsReceiveComponent);
        component = fixture.componentInstance;
        component.sitems = [sitem];
        component.bibRecordId = 224;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
    it('includes sitem notes', () => {
        expect(fixture.nativeElement.innerText).toContain('Watch out!');
        expect(fixture.nativeElement.innerText).toContain('This issue includes a lot of glitter');
    });
    it('includes sdist notes', () => {
        expect(fixture.nativeElement.innerText).toContain('This is my favorite distribution');
        expect(fixture.nativeElement.innerText).toContain('I hope you like it too');
    });
    it('includes ssub notes', () => {
        expect(fixture.nativeElement.innerText).toContain('Don\'t barcode me');
        expect(fixture.nativeElement.innerText).toContain('uncheck the barcode checkbox please');
    });
    it('includes issuance', () => {
        expect(fixture.nativeElement.innerText).toContain('Special issue');
    });
    describe('when no receive unit template is set', () => {
        beforeEach(() => {
            distribution.receive_unit_template.and.returnValue(null);
            fixture.detectChanges();
        });
        it('includes a notice', () => {
            expect(fixture.nativeElement.innerText)
                .toContain('This distribution does not have a receive template, so we cannot barcode the issue.');
        });
    });
    describe('when a receive unit template exists', () => {
        beforeEach(() => {
            distribution.receive_unit_template.and.returnValue(template);
            component.ngOnInit();
            fixture.detectChanges();
        });
        it('does not include a notice', () => {
            expect(fixture.nativeElement.innerText)
                .not.toContain('This distribution does not have a receive template, so we cannot barcode the issue.');
        });
        it('defaults the circ modifier to the template\'s circ modifier', () => {
            expect(component.itemsFormArray.at(0).get('modifier').value.id).toEqual('DEFAULT');
        });
        it('defaults the shelving location to the template\'s location', () => {
            expect(component.itemsFormArray.at(0).get('location').value).toEqual(180);
        });
        describe('when the Barcode items checkbox is unchecked', () => {
            beforeEach(() => {
                component.tableForm.get('barcodeOptions').get('barcodeItems').setValue(false);
                fixture.detectChanges();
            });
            it('considers the form to be valid', () => {
                expect(component.tableForm.valid).toBe(true);
                expect(fixture.nativeElement.querySelector('#receive-button').disabled).toBeFalse();
            });
            it('greys out the Automatically generate barcodes checkbox', () => {
                expect(fixture.nativeElement.querySelector('#autoGenerate').disabled).toBeTrue();
            });
            it('greys out the Show Call Number Prefixes/Suffixes checkbox', () => {
                expect(fixture.nativeElement.querySelector('#callNumberAffixes').disabled).toBeTrue();
            });
        });
        describe('when the Automatically generate barcodes checkbox is checked', () => {
            beforeEach(() => {
                component.tableForm.get('barcodeOptions').get('autoGenerate').setValue(true);
                fixture.detectChanges();
            });
            it('greys out the barcode field', () => {
                expect(fixture.nativeElement.querySelector('input[aria-labelledby="row-0 barcode"]').disabled).toBeTrue();
            });
        });
        describe('receiveItems$()', () => {
            beforeEach(() => {
                component.itemsFormArray.at(0).get('barcode').setValue('1234567890');
                component.itemsFormArray.at(0).get('callnumber').setValue({id: null, label: 'MAGAZINES', freetext: true});
                component.itemsFormArray.at(0).get('suffix').setValue({id: 30, label: 'NEW SHELF'});
                component.itemsFormArray.at(0).get('modifier').setValue({id: 'DEFAULT'});
                component.itemsFormArray.at(0).get('location').setValue(180);
                spyOn(component.net, 'request').and.returnValue(of({numItems: 1}));
                fixture.detectChanges();
            });
            it('sends the correct data to open-ils.serial.receive_items', fakeAsync(() => {
                component.receiveItems$().subscribe();
                tick();
                expect(component.net.request).toHaveBeenCalledWith(
                    'open-ils.serial',
                    'open-ils.serial.receive_items',
                    'MY_AUTH_TOKEN',
                    [sitem],
                    {1089: '1234567890'},
                    {1089: [null, 'MAGAZINES', 'NEW SHELF']},
                    {},
                    {circ_mods: {1089: 'DEFAULT'},
                        copy_locations: {1089: 180}});
            }));
            it('sets the issuance unit to -1', fakeAsync(() => {
                component.receiveItems$().subscribe();
                tick();
                expect(sitem.unit).toHaveBeenCalledWith(-1);
            }));
            describe('when barcode mode is off', () => {
                it('does not set the issuance unit to -1', fakeAsync(() => {
                    component.barcodeModeOn = false;
                    component.receiveItems$().subscribe();
                    tick();
                    expect(sitem.unit).not.toHaveBeenCalledWith(-1);
                }));
            });
        });
        describe('anyItemsSelectedForReceive', () => {
            it('returns true if any items are selected', () => {
                component.itemsFormArray.at(0).get('receive').setValue(true);
                expect(component.anyItemsSelectedForReceive).toBe(true);
            });
            it('returns false if no items are selected', () => {
                component.itemsFormArray.at(0).get('receive').setValue(false);
                expect(component.anyItemsSelectedForReceive).toBe(false);
            });
        });
        describe('batch actions', () => {
            it('applies a barcode to all rows', () => {
                component.tableForm.get('batch').get('barcode').setValue('ABC123');
                component.tableForm.get('batch').get('barcode').markAsTouched();
                fixture.nativeElement.querySelector('#apply-batch').click();
                fixture.detectChanges();

                expect(component.itemsFormArray.controls[0].get('barcode').value).toEqual('ABC123');
            });
            it('applies a shelving location to all rows', () => {
                component.tableForm.get('batch').get('location').setValue(4);
                component.tableForm.get('batch').get('location').markAsTouched();
                fixture.nativeElement.querySelector('#apply-batch').click();
                fixture.detectChanges();

                expect(component.itemsFormArray.controls[0].get('location').value).toEqual(4);
            });
            it('applies a prefix to all rows', () => {
                component.tableForm.get('batch').get('prefix').setValue({id: 17, label: 'NEW SHELF'});
                component.tableForm.get('batch').get('prefix').markAsTouched();
                fixture.nativeElement.querySelector('#apply-batch').click();
                fixture.detectChanges();

                expect(component.itemsFormArray.controls[0].get('prefix').value).toEqual({id: 17, label: 'NEW SHELF'});
            });
        });
    });
    describe('when a routing list exists', () => {
        beforeEach(() => {
            stream.routing_list_users.and.returnValue(routingList);
            component.ngOnInit();
            fixture.detectChanges();
        });
        it('includes a button to print the routing list', () => {
            expect(fixture.nativeElement.innerText).toContain('Receive and print routing list');
        });
    });
    describe('when no routing list exists', () => {
        beforeEach(() => {
            stream.routing_list_users.and.returnValue([]);
            component.ngOnInit();
            fixture.detectChanges();
        });
        it('includes a button to print the routing list', () => {
            expect(fixture.nativeElement.innerText).not.toContain('Receive and print routing list');
        });
    });
});
