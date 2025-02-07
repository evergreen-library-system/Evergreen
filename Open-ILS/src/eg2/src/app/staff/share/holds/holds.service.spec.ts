import { HoldsService } from './holds.service';
import { MockGenerators } from 'test_data/mock_generators';
import { of } from 'rxjs';
import { BibRecordService } from '@eg/share/catalog/bib-record.service';

describe('HoldsService', () => {
    let service: HoldsService;
    let netService;
    let authService;
    let eventService;
    let bibRecordService;

    beforeEach(() => {
        netService = MockGenerators.netService({});
        authService = MockGenerators.authService();
        eventService = jasmine.createSpyObj('EventService', ['parse']);
        bibRecordService = jasmine.createSpyObj<BibRecordService>(['getBibSummary']);
        service = new HoldsService (eventService, netService, authService, bibRecordService);
    });

    it('can place a hold', (done) => {
        const holdRequest = {
            holdType: 'T',
            holdTarget: 123,
            recipient: 456,
            requestor: 789,
            pickupLib: 1,
            notifyEmail: true,
            notifyPhone: null
        };

        netService.request.and.returnValue(of({
            result: 999 // Success returns hold ID
        }));

        service.placeHold(holdRequest).subscribe(result => {
            expect(netService.request).toHaveBeenCalledWith(
                'open-ils.circ',
                'open-ils.circ.holds.test_and_create.batch',
                'MY_AUTH_TOKEN',
                {
                    patronid: 456,
                    pickup_lib: 1,
                    hold_type: 'T',
                    email_notify: true,
                    phone_notify: null,
                    thaw_date: undefined,
                    frozen: undefined,
                    sms_notify: undefined,
                    sms_carrier: undefined,
                    holdable_formats_map: undefined
                },
                [123]
            );
            expect(result.result.success).toBeTrue();
            expect(result.result.holdId).toBe(999);
            done();
        });
    });

    it('can place a hold for a hold group', (done) => {
        const holdRequest = {
            holdGroup: true,
            holdGroupId: 222,
            holdType: 'T',
            holdTarget: 123,
            recipient: 456,
            requestor: 789,
            pickupLib: 1,
            notifyEmail: true,
            notifyPhone: null
        };

        netService.request.and.returnValue(of({
            count: 0,
            total: 3
        }));

        service.placeHold(holdRequest).subscribe(result => {
            expect(netService.request).toHaveBeenCalledWith(
                'open-ils.circ',
                'open-ils.circ.holds.test_and_create.subscription_batch',
                'MY_AUTH_TOKEN',
                {
                    pickup_lib: 1,
                    hold_type: 'T',
                    email_notify: true,
                    phone_notify: null,
                    thaw_date: undefined,
                    frozen: undefined,
                    sms_notify: undefined,
                    sms_carrier: undefined,
                    holdable_formats_map: undefined
                },
                222, // hold group id
                123 // title record id
            );
            expect(result.result.success).toBeTrue();
            done();
        });
    });
});
