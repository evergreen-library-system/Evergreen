import { IdlObject } from '@eg/core/idl.service';
import { SckoService } from './scko.service';
import { SckoSummaryComponent } from './summary.component';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute } from '@angular/router';
import { MockGenerators } from 'test_data/mock_generators';

function mockPatron(email: string | null, settings: IdlObject[] = []): IdlObject {
    return MockGenerators.idlObject({ email, settings });
}

function mockService(patron: IdlObject): SckoService {
    return jasmine.createSpyObj<SckoService>([], {
        patronSummary: {
            id: null,
            stats: null,
            alerts: null,
            patron
        }
    });
}

function mockSetting(name: string, value: string): IdlObject {
    return MockGenerators.idlObject({ name, value });
}

function createSummaryComponent(service: SckoService): SckoSummaryComponent {
    return TestBed
        .configureTestingModule({providers: [{provide: SckoService, useValue: service}, {provide:ActivatedRoute, useValue: null}]})
        .createComponent(SckoSummaryComponent)
        .componentInstance;
}

describe('SummaryComponent', () => {
    describe('canEmail', () => {
        it('returns true if patron has a valid email address', () => {
            const patron = mockPatron('test@example.com');
            const service = mockService(patron);
            const component = createSummaryComponent(service);
            expect(component.canEmail()).toEqual(true);
        });
        it('returns false if patron has a null email address', () => {
            const patron = mockPatron(null);
            const service = mockService(patron);
            const component = createSummaryComponent(service);
            expect(component.canEmail()).toEqual(false);
        });
        it('returns false if patron has an empty string as an email address', () => {
            const patron = mockPatron('');
            const service = mockService(patron);
            const component = createSummaryComponent(service);
            expect(component.canEmail()).toEqual(false);
        });
    });

    describe('prefersEmail', () => {
        it('returns true if default email receipt setting is true', () => {
            const patron = mockPatron(null, [
                mockSetting('circ.send_email_checkout_receipts', 'true')
            ]);
            const service = mockService(patron);
            const component = createSummaryComponent(service);
            expect(component.prefersEmail()).toEqual(true);
        });
        it('returns false if default email receipt setting is not true', () => {
            const patron = mockPatron(null, [
                mockSetting('circ.send_email_checkout_receipts', 'false')
            ]);
            const service = mockService(patron);
            const component = createSummaryComponent(service);
            expect(component.prefersEmail()).toEqual(false);
        });
        it('returns false if no default email receipt setting value', () => {
            const patron = mockPatron(null, []);
            const service = mockService(patron);
            const component = createSummaryComponent(service);
            expect(component.prefersEmail()).toEqual(false);
        });
    });
});
