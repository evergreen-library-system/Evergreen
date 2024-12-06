import { MockGenerators } from 'test_data/mock_generators';
import { VolEditPartDedupePipe } from './vol-edit-part-dedupe.pipe';
import { IdlObject } from '@eg/core/idl.service';

describe('VolEditPartDedupePupe', () => {
    it('returns an array of IdlObjects with unique labels', () => {
        const pipe = new VolEditPartDedupePipe();
        const items = {
            12: [
                MockGenerators.idlObject({ label: 'Orange' }),
                MockGenerators.idlObject({ label: 'Pomelo' }),
            ],
            7001: [
                MockGenerators.idlObject({ label: 'Pomelo' }),
            ],
            1: [
                MockGenerators.idlObject({ label: 'Orange' }),
            ],
            743_133: [
                MockGenerators.idlObject({ label: 'Grapefruit' }),
                MockGenerators.idlObject({ label: 'Makrut Lime' }),
            ]
        };
        expect(pipe.transform(items).map((item: IdlObject) => item.label())).toEqual([
            'Orange', 'Pomelo', 'Grapefruit', 'Makrut Lime'
        ]);
    });
});
