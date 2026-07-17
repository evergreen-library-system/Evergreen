import { TagTable } from './tagtable.service';

const TAG_300_DATA = {
    'subfields': [
        {
            'mandatory': 'f',
            'description': 'Materials specified',
            'code': '3',
            'repeatable': 'f'
        },
        {
            'code': '6',
            'repeatable': 'f',
            'mandatory': 'f',
            'description': 'Linkage'
        },
        {
            'repeatable': 't',
            'code': '8',
            'description': 'Field link and sequence number',
            'mandatory': 'f'
        },
        {
            'mandatory': 'f',
            'description': 'Extent',
            'code': 'a',
            'repeatable': 't'
        },
        {
            'repeatable': 'f',
            'code': 'b',
            'description': 'Other physical details',
            'mandatory': 'f'
        },
        {
            'code': 'c',
            'repeatable': 't',
            'description': 'Dimensions',
            'mandatory': 'f'
        },
        {
            'code': 'e',
            'repeatable': 'f',
            'description': 'Accompanying material',
            'mandatory': 'f'
        },
        {
            'code': 'f',
            'repeatable': 't',
            'description': 'Type of unit',
            'mandatory': 'f'
        },
        {
            'repeatable': 't',
            'code': 'g',
            'mandatory': 'f',
            'description': 'Size of unit'
        }
    ],
    'id': 78,
    'owner': null,
    'name': 'Physical Description',
    'description': 'Physical description of the described item, including its extent, dimensions, and such other physical details ' +
        'as a description of any accompanying materials and unit type and size.',
    'ind2': [
        {
            'code': '#',
            'description': 'Undefined'
        }
    ],
    'marc_record_type': 'biblio',
    'repeatable': 't',
    'ind1': [
        {
            'code': '#',
            'description': 'Undefined'
        }
    ],
    'marc_format': 1,
    'mandatory': 'f',
    'hidden': 'f',
    'tag': '300',
    'fixed_field': 'f'
};

describe('TagTable', () => {
    describe('getSubfieldCodes()', () => {
        it('returns the sorted subfields as comboboxes', () => {
            const table = new TagTable(null, null, null, null, null);
            table['tagMap'] = {'300': TAG_300_DATA};
            expect(table.getSubfieldCodes('300')).toEqual([
                { id: 'a', label: 'Extent' },
                { id: 'b', label: 'Other physical details' },
                { id: 'c', label: 'Dimensions' },
                { id: 'e', label: 'Accompanying material' },
                { id: 'f', label: 'Type of unit' },
                { id: 'g', label: 'Size of unit' },
                { id: '3', label: 'Materials specified' },
                { id: '6', label: 'Linkage' },
                { id: '8', label: 'Field link and sequence number' },
            ]);
        });
    });
});
