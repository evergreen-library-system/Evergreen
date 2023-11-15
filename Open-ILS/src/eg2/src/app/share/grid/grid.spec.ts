import { FormatService } from '@eg/core/format.service';
import { IdlService } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { GridContext } from './grid';

const mockIdl = jasmine.createSpyObj<IdlService>([], {classes: {acpl: {fields: [{name: 'id'}]}}});
const mockOrg = jasmine.createSpyObj<OrgService>(['root']);
const mockStore = jasmine.createSpyObj<ServerStoreService>(['getItem', 'setItem']);
const mockFormat = jasmine.createSpyObj<FormatService>(['transform']);


describe('GridContext', () => {
    describe('init()', () => {
        it('can use the initialFilterValues when generating columns', () => {
            const context = new GridContext(mockIdl, mockOrg, mockStore, mockFormat);
            context.initialFilterValues = {id: '3'};
            context.idlClass = 'acpl';
            context.ignoredFields = ['bad', 'fields'];
            context.init();
            expect(context.columnSet.columns[0].filterValue).toEqual('3');
        });
    });
});
