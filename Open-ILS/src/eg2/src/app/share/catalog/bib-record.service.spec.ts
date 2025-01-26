import { waitForAsync } from '@angular/core/testing';
import { NetService } from '@eg/core/net.service';
import { of } from 'rxjs';
import { BibRecordService } from './bib-record.service';
import { PermService } from '@eg/core/perm.service';

const mockNetService = jasmine.createSpyObj<NetService>(['request']);
const mockPermService = jasmine.createSpyObj<PermService>(['hasWorkPermHere']);
mockNetService.request.and.returnValue(of({
    'staff_view_metabib_records': [
        '245',
        '246',
        '247',
        '248'
    ],
    'staff_view_metabib_id': '241',
    'first_call_number': {
        'copy_status': 'Available',
        'call_number_prefix_label': '',
        'due_date': '',
        'call_number_label': 'MR 248',
        'copy_location': 'Stacks',
        'call_number_suffix_label': '',
        'circ_lib_sn': 'BR1'
    },
    'attributes': {
        'ills1': [
            ' '
        ]
    },
    'record': {
        id: () => 248,
        deleted: () => 'f'
    },
    'record_note_count': 0,
    'has_holdable_copy': '1',
    'copy_counts': [
        {
            'transcendant': null,
            'count': 18,
            'unshadow': 18,
            'available': 18,
            'depth': 0,
            'org_unit': 1
        }
    ],
    'urls': [],
    'display': {
        'publisher': 'New York : Crown Publishers, c2011.',
        'genre': [
            'Fantasy fiction.'
        ]
    },
    'staff_view_metabib_attributes': {
        'item_form': {
            'o': {
                'label': 'Online',
                'count': 1
            },
            'd': {
                'count': 1,
                'label': 'Large print'
            }
        },
    },
    'id': 248,
    'hold_count': '0'
}));
mockPermService.hasWorkPermHere.and.returnValue(Promise.resolve({PLACE_UNFILLABLE_HOLD: true}));
const service = new BibRecordService(mockNetService, null, mockPermService);

describe('BibRecordService', () => {
    describe('getBibSummary()', () => {
        it('gets the holdCount from the net service response', waitForAsync(() => {
            service.getBibSummary(248, 1, true)
                .subscribe((summary) => {
                    expect(summary.holdCount).toEqual(0);
                });
        }));
        it('gets the recordNoteCount from the net service response', waitForAsync(() => {
            service.getBibSummary(248, 1, true)
                .subscribe((summary) => {
                    expect(summary.recordNoteCount).toEqual(0);
                });
        }));
        it('can accept a library group id', waitForAsync(() => {
            service.getBibSummary(248, 1, true, 15)
                .subscribe(() => {
                    expect(mockNetService.request).toHaveBeenCalledWith(
                        'open-ils.search',
                        'open-ils.search.biblio.record.catalog_summary.staff',
                        1, // org id
                        [248], // bib record ids
                        {library_group: 15}
                    );
                });
        }));
    });
});
