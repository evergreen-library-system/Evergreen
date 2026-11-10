import { PcrudService } from '@eg/core/pcrud.service';
import { buildPcrudGridDataSource } from './build-grid-data-source';
import { from, toArray } from 'rxjs';
import { Pager } from '../util/pager';

describe('buildPcrudGridDataSource', () => {
    it('builds a data source that can retrieve things from PCRUD-compatible interfaces', () => {
        const fakeSearch = (_fmClass: string, _pcrud: PcrudService, search: any[], pcrudOps?: any) => {
            const data = [
                {name: 'Fido', animal: 'dog'},
                {name: 'Gertrude', animal: 'giraffe'},
                {name: 'Alberto', animal: 'dog'}
            ];
            const searchKeys = Object.keys(search[0]);
            const searchValues = Object.values(search[0]);
            return from(data
                .filter(entry => entry[searchKeys[0]] === searchValues[0])
                .sort((a, b) => a[pcrudOps.order_by].localeCompare(b[pcrudOps.order_by]))
            );
        };
        const source = buildPcrudGridDataSource(
            'zoo',
            {} as PcrudService,
            () => [{animal: 'dog'}],
            () => {return {order_by: 'name'};},
            fakeSearch
        );

        source.getRows(new Pager(), [])
            .pipe(toArray())
            .subscribe(results => {
                expect(results).toEqual([{name: 'Alberto', animal: 'dog'}, {name: 'Fido', animal: 'dog'}]);
            });
    });
});
