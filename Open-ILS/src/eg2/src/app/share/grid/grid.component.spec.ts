import { IdlService } from '@eg/core/idl.service';
import { GridComponent } from './grid.component';
import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { FormatService } from '@eg/core/format.service';
import { GridDataSource } from './grid';

const mockIdl = jasmine.createSpyObj<IdlService>([], {classes: {}});
const mockOrg = jasmine.createSpyObj<OrgService>(['root']);
const mockStore = jasmine.createSpyObj<ServerStoreService>(['getItem', 'setItem']);
const mockFormat = jasmine.createSpyObj<FormatService>(['transform']);
let component: GridComponent;

describe('GridComponent', () => {
    beforeEach(() => {
        component = new GridComponent(mockIdl, mockOrg, mockStore, mockFormat, null);
    });
    describe('ngOnInit', () => {
        it('adds initialFilterValues to the context', () => {
            component.initialFilterValues = {deleted: 'f'};
            component.dataSource = new GridDataSource();
            component.ngOnInit();
            expect(component.context.initialFilterValues).toEqual({deleted: 'f'});
        });
    });
});
