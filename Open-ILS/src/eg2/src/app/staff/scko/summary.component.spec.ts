import { IdlObject } from '@eg/core/idl.service';
import { SckoService } from './scko.service';
import { SckoSummaryComponent } from './summary.component';


let patron: IdlObject;
let mockService: any;

describe('SummaryComponent', () => {
    describe('canEmail', () => {
        it('returns true if patron has a valid email address', () => {
            patron = {
                email: () => 'test@example.com',
                a: null, _isfieldmapper: null, classname: null
            };
            mockService = jasmine.createSpyObj<SckoService>([], {
                patronSummary: {
                    id: null,
                    stats: null,
                    alerts: null,
                    patron: patron
                }
            });
            const component = new SckoSummaryComponent(mockService);
            expect(component.canEmail()).toEqual(true);
        });
        it('returns false if patron has a null email address', () => {
            patron = {
                email: () => null,
                a: null, _isfieldmapper: null, classname: null
            };
            mockService = jasmine.createSpyObj<SckoService>([], {
                patronSummary: {
                    id: null,
                    stats: null,
                    alerts: null,
                    patron: patron
                }
            });
            const component = new SckoSummaryComponent(mockService);
            expect(component.canEmail()).toEqual(false);
        });
        it('returns false if patron has an empty string as an email address', () => {
            patron = {
                email: () => '',
                a: null, _isfieldmapper: null, classname: null
            };
            mockService = jasmine.createSpyObj<SckoService>([], {
                patronSummary: {
                    id: null,
                    stats: null,
                    alerts: null,
                    patron: patron
                }
            });
            const component = new SckoSummaryComponent(mockService);
            expect(component.canEmail()).toEqual(false);
        });
    });
});
