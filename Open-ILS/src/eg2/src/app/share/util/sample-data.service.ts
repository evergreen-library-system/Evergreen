/* eslint-disable no-magic-numbers */
import {Injectable} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';

/** Service for generating sample data for testing, demo, etc. */

// TODO: I could also imagine this coming from a web service or
// even a flat file of web-served JSON.

const NOW_DATE = new Date().toISOString();

// Copied from sample of Concerto data set
const DATA = {
    au: [
        {first_given_name: 'Vincent',  second_given_name: 'Kenneth',   family_name: 'Moran'},
        {first_given_name: 'Gregory',  second_given_name: 'Adam',      family_name: 'Jones'},
        {first_given_name: 'Brittany', second_given_name: 'Geraldine', family_name: 'Walker'},
        {first_given_name: 'Ernesto',  second_given_name: 'Robert',    family_name: 'Miller'},
        {first_given_name: 'Robert',   second_given_name: 'Louis',     family_name: 'Hill'},
        {first_given_name: 'Edward',   second_given_name: 'Robert',    family_name: 'Lopez'},
        {first_given_name: 'Andrew',   second_given_name: 'Alberto',   family_name: 'Bell'},
        {first_given_name: 'Jennifer', second_given_name: 'Dorothy',   family_name: 'Mitchell'},
        {first_given_name: 'Jo',       second_given_name: 'Mai',       family_name: 'Madden'},
        {first_given_name: 'Maomi',    second_given_name: 'Julie',     family_name: 'Harding'}
    ],
    ac: [
        {barcode: '908897239000'},
        {barcode: '908897239001'},
        {barcode: '908897239002'},
        {barcode: '908897239003'},
        {barcode: '908897239004'},
        {barcode: '908897239005'},
        {barcode: '908897239006'},
        {barcode: '908897239007'},
        {barcode: '908897239008'},
        {barcode: '908897239009'}
    ],
    aua: [
        {street1: '1809 Target Way', city: 'Vero beach', state: 'FL', post_code: 32961},
        {street1: '3481 Facility Island', city: 'Campton', state: 'KY', post_code: 41301},
        {street1: '5150 Dinner Expressway', city: 'Dodge center', state: 'MN', post_code: 55927},
        {street1: '8496 Random Trust Points', city: 'Berryville', state: 'VA', post_code: 22611},
        {street1: '7626 Secret Institute Courts', city: 'Anchorage', state: 'AK', post_code: 99502},
        {street1: '7044 Regular Index Path', city: 'Livingston', state: 'KY', post_code: 40445},
        {street1: '3403 Thundering Heat Meadows', city: 'Miami', state: 'FL', post_code: 33157},
        {street1: '759 Doubtful Government Extension', city: 'Sellersville', state: 'PA', post_code: 18960},
        {street1: '5431 Japanese Work Rapid', city: 'Society hill', state: 'SC', post_code: 29593},
        {street1: '5253 Agricultural Exhibition Stravenue', city: 'La place', state: 'IL', post_code: 61936}
    ],
    ahr: [
        {request_time: NOW_DATE, hold_type: 'T', capture_time: null,     fulfillment_time: null},
        {request_time: NOW_DATE, hold_type: 'T', capture_time: null,     fulfillment_time: null},
        {request_time: NOW_DATE, hold_type: 'V', capture_time: null,     fulfillment_time: null},
        {request_time: NOW_DATE, hold_type: 'C', capture_time: null,     fulfillment_time: null},
        {request_time: NOW_DATE, hold_type: 'T', capture_time: null,     fulfillment_time: null, frozen: true},
        {request_time: NOW_DATE, hold_type: 'T', capture_time: NOW_DATE, fulfillment_time: null},
        {request_time: NOW_DATE, hold_type: 'T', capture_time: NOW_DATE, fulfillment_time: null},
        {request_time: NOW_DATE, hold_type: 'T', capture_time: NOW_DATE, fulfillment_time: NOW_DATE},
        {request_time: NOW_DATE, hold_type: 'T', capture_time: NOW_DATE, fulfillment_time: NOW_DATE},
        {request_time: NOW_DATE, hold_type: 'T', capture_time: NOW_DATE, fulfillment_time: NOW_DATE}
    ],
    acp: [
        {barcode: '208897239000'},
        {barcode: '208897239001'},
        {barcode: '208897239002'},
        {barcode: '208897239003'},
        {barcode: '208897239004'},
        {barcode: '208897239005'},
        {barcode: '208897239006'},
        {barcode: '208897239007'},
        {barcode: '208897239008'},
        {barcode: '208897239009'}
    ],
    mwde: [
        {title: 'Sinidos sinfónicos : an orchestral sampler'},
        {title: 'Piano concerto, op. 38'},
        {title: 'Critical entertainments : music old and new'},
        {title: 'Piano concerto in C major, op. 39'},
        {title: 'Double concerto in A minor, op. 102 ; Variations on a theme by Haydn, op. 56a ; Tragic overture, op. 81'},
        {title: 'Trombone concerto (1991) subject: american'},
        {title: 'Violin concerto no. 2 ; Six duos (from 44 Duos)'},
        {title: 'Piano concerto no. 1 (1926) ; Rhapsody, op. 1 (1904)'},
        {title: 'Piano concertos 2 & 3 & the devil makes me?'},
        {title: 'Composition student recital, April 6, 2000, Huntington University / composition students of Daniel Bédard'},
    ],
    mbt: [
        {id: 1, xact_start: new Date().toISOString()},
        {id: 2, xact_start: new Date().toISOString()},
        {id: 3, xact_start: new Date().toISOString()}
    ],
    mbts: [
        {   balance_owed: 1,
            last_billing_note: 'a note',
            last_billing_ts: new Date().toISOString(),
            last_billing_type: 'Overdue Materials',
            last_payment_note: '',
            last_payment_ts: new Date().toISOString(),
            last_payment_type: 'cash_payment',
            total_owed: 5,
            total_paid: 3,
            xact_start: new Date().toISOString(),
            xact_type: 'circulation'
        }
    ],
    sstr: [
        {id: 1},
        {id: 2, routing_label: 'Send to interested parties'}
    ],
    sdist: [
        {label: 'Our library\'s copy'}
    ],
    siss: [
        {label: 'volume 1, issue 1'},
        {label: 'Special issue'}
    ],
    srlu: [
        {department: 'Circulation'},
        {department: 'Reference', note: 'Please recycle when done'}
    ]
};


@Injectable()
export class SampleDataService {

    constructor(private idl: IdlService) {}

    randomValue(list: any[], field: string): string {
        return list[Math.floor(Math.random() * list.length)][field];
    }

    listOfThings(idlClass: string, count = 1): IdlObject[] {
        if (!(idlClass in DATA)) {
            throw new Error(`No sample data for class ${idlClass}'`);
        }

        const things: IdlObject[] = [];
        for (let i = 0; i < count; i++) {
            const thing = this.idl.create(idlClass);
            Object.keys(DATA[idlClass][0]).forEach(field =>
                thing[field](this.randomValue(DATA[idlClass], field))
            );
            things.push(thing);
        }

        return things;
    }

    // Returns a random-ish date in the past or the future.
    randomDate(future = false): Date {
        const rando = Math.random() * 10000000000;
        const time = new Date().getTime();
        return new Date(future ? time + rando : time - rando);
    }

    randomDateIso(future = false): string {
        return this.randomDate(future).toISOString();
    }
}


