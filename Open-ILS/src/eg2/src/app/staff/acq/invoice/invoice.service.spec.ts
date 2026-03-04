import { TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { EventService } from '@eg/core/event.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { MockGenerators } from 'test_data/mock_generators';
import { PoService } from '../po/po.service';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { LineitemService } from '../lineitem/lineitem.service';
import { InvoiceService } from './invoice.service';

function mockInvoice(): IdlObject {
    // Use a Proxy to allow the code under test to get and set arbitrary fields, without us
    // having to specifically mock each field
    return new Proxy({
        a: [],
        classname: 'acqinv',
        _isfieldmapper: true,
        saved_data: {}
    }, {
        get(data, property: string) {
            if (['a', 'classname', '_isfieldmapper'].includes(property as string)) {
                return data[property];
            } else {
                return (newValue: any) => {
                    if(newValue === undefined) {
                        return data.saved_data[property] ?? null;
                    } else {
                        data.saved_data[property] = newValue;
                    }
                };
            }
        }
    });
}

describe('InvoiceService', () => {
    beforeEach(() => {
        const mockIdl = jasmine.createSpyObj<IdlService>(['create']);
        mockIdl.create.and.returnValue(mockInvoice());
        TestBed.configureTestingModule({providers: [
            {provide: AuthService, useValue: null},
            {provide: EventService, useValue: null},
            {provide: IdlService, useValue: mockIdl},
            InvoiceService,
            {provide: LineitemService, useValue: MockGenerators.lineItemService()},
            {provide: NetService, useValue: null},
            {provide: PcrudService, useValue: MockGenerators.pcrudService({})},
            {provide: PoService, useValue: null},
        ]});
    });
    describe('createNewInvoice()', () => {
        it('sets the currentInvoice to a new one', async () => {
            const service = TestBed.inject(InvoiceService);
            await service.createNewInvoice(null, []);
            expect(service.currentInvoice.recv_method()).toEqual('PPR');
            expect(service.currentInvoice.receiver()).toBeNull();
        });
    });
});
