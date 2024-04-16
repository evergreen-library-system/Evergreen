import { ComponentFixture, TestBed, fakeAsync, flush, tick, waitForAsync } from '@angular/core/testing';
import { CatalogOrgSelectComponent } from './catalog-org-select.component';
import { Tree, TreeNode } from '@eg/share/tree/tree';
import { IdlObject } from '@eg/core/idl.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { EnhancedOrgTree } from '@eg/share/tree/enhanced-org-tree';

const mockRootIdlObject = jasmine.createSpyObj<IdlObject>(['id', 'shortname'], {classname: 'aou'});
mockRootIdlObject.id.and.returnValue(1);
mockRootIdlObject.shortname.and.returnValue('LINN');

const enhancedOrgTree = jasmine.createSpyObj<EnhancedOrgTree>(['toTreeObject']);
enhancedOrgTree.toTreeObject.and.resolveTo(new Tree(
    new TreeNode({
        label: 'LINN',
        id: 1,
        callerData: mockRootIdlObject,
        children: [
            new TreeNode({
                label: 'APL',
                id: 2,
                children: [
                    new TreeNode({label: 'APL-CARNEGIE', id: 4}),
                    new TreeNode({label: 'APL-MAIN', id: 3}),
                ]
            }),
            new TreeNode({
                label: 'HPL',
                id: 5,
                children: [
                    new TreeNode({label: 'HPLLIB', id: 6})
                ]
            })
        ]
    })
));

const mockServerStoreService = jasmine.createSpyObj<ServerStoreService>(['getItem']);

describe('CatalogOrgSelectComponent', () => {
    let component: CatalogOrgSelectComponent;
    let fixture: ComponentFixture<CatalogOrgSelectComponent>;

    mockServerStoreService.getItem.and.resolveTo(null);

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ CatalogOrgSelectComponent ],
            providers: [
                {provide: EnhancedOrgTree, useValue: enhancedOrgTree},
                {provide: ServerStoreService, useValue: mockServerStoreService}
            ]
        })
            .compileComponents();

        fixture = TestBed.createComponent(CatalogOrgSelectComponent);
        component = fixture.componentInstance;

        // The tests don't wait for component.initializeTree() to resolve
        // before running assertions, so let's explicitly wait for it here.
        await component.initializeTree();
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('displays an org tree', fakeAsync(() => {
        // non-collapsing space
        const PAD_SPACE = ' '; // U+2007
        fixture.nativeElement.querySelector('input').focus();

        flush();
        const entries = fixture.nativeElement.querySelectorAll('button.dropdown-item');
        expect(entries[0].textContent).toEqual('LINN');
        expect(entries[1].textContent).toEqual(PAD_SPACE + 'APL');
        expect(entries[2].textContent).toEqual(PAD_SPACE + PAD_SPACE + 'APL-CARNEGIE');
        expect(entries[3].textContent).toEqual(PAD_SPACE + PAD_SPACE + 'APL-MAIN');
        expect(entries[4].textContent).toEqual(PAD_SPACE + 'HPL');
        expect(entries[5].textContent).toEqual(PAD_SPACE + PAD_SPACE + 'HPLLIB');
    }));

    it('emits a orgChanged event with the IDL object', () => {
        let emitted: IdlObject;
        component.orgChanged$.subscribe((event: IdlObject) => {
            emitted = event;
        });

        fixture.nativeElement.querySelector('input').focus();
        fixture.debugElement.query(
            debugEl => debugEl.nativeElement.textContent === 'LINN'
        ).nativeElement.click();

        expect(emitted.id()).toEqual(1);
    });

    it('has a placeholder', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.getAttribute('placeholder')).toEqual('Library');
    });

    it('has an aria label', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.getAttribute('aria-label')).toEqual('Library');
    });

    it('has an id', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.getAttribute('id')).toEqual('search-org-selector');
    });

    it('can accept initialOrg', fakeAsync(() => {
        component.initialOrg = mockRootIdlObject;
        fixture.detectChanges();
        tick(200);

        expect(fixture.nativeElement.querySelector('input').value).toEqual('LINN');
    }));

    describe('when server store tells us the user wants combined org unit labels', () => {
        beforeEach(async () => {
            mockServerStoreService.getItem.and.resolveTo(true);
            await component.initializeTree();
        });
        it('sends the appropriate labelGenerator arrow function to the org service', () => {
            const labelGenerator = enhancedOrgTree.toTreeObject.calls.mostRecent().args[0];
            const node = jasmine.createSpyObj<IdlObject>(['name', 'shortname']);
            node.name.and.returnValue('Fantastic Consortium');
            node.shortname.and.returnValue('FanCons');

            expect(labelGenerator(node)).toEqual('Fantastic Consortium (FanCons)');
        });
    });
});
