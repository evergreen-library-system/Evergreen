import { TestBed, waitForAsync } from '@angular/core/testing';
import { EnhancedOrgTree } from './enhanced-org-tree';
import { OrgService } from '@eg/core/org.service';
import { IdlObject } from '@eg/core/idl.service';
import { Tree, TreeNode } from './tree';
import { PcrudService } from '@eg/core/pcrud.service';
import { GlobalFlagService } from '@eg/core/global-flag.service';
import { MockGenerators } from 'test_data/mock_generators';

const consortium = jasmine.createSpyObj<IdlObject>(
    ['children', 'id', 'parent_ou', 'shortname', 'staff_catalog_visible'],
    {classname: 'aou'}
);
consortium.id.and.returnValue(1);
consortium.shortname.and.returnValue('CONS');
consortium.staff_catalog_visible.and.returnValue('t');

const system = jasmine.createSpyObj<IdlObject>(['children', 'id', 'parent_ou', 'shortname', 'staff_catalog_visible'], {classname: 'aou'});
system.id.and.returnValue(2);
system.shortname.and.returnValue('SYS');
system.parent_ou.and.returnValue(1);
system.staff_catalog_visible.and.returnValue('f');

const branch = jasmine.createSpyObj<IdlObject>(['children', 'id', 'parent_ou', 'shortname', 'staff_catalog_visible'], {classname: 'aou'});
branch.id.and.returnValue(3);
branch.shortname.and.returnValue('BR');
branch.parent_ou.and.returnValue(2);
branch.staff_catalog_visible.and.returnValue('t');

branch.children.and.returnValue([]);
system.children.and.returnValue([branch]);
consortium.children.and.returnValue([system]);

const mockOrgService = jasmine.createSpyObj<OrgService>(['absorbTree', 'root', 'get']);
mockOrgService.root.and.returnValue(consortium);
mockOrgService.get.and.callFake((id) => {
    if (id === 1) {
        return consortium;
    } else if (id === 2) {
        return system;
    } else if (id === 3) {
        return branch;
    }
});

const adultGroup = MockGenerators.idlObject({
    id: 130,
    name: 'Adult\'s materials',
    owner: 1,
    pos: 2,
    top: 't'
}, 'acplg');
const teenGroup = MockGenerators.idlObject({
    id: 27,
    name: 'Teen\'s materials',
    owner: 3,
    pos: 1,
    top: 'f'
}, 'acplg');
const childrensGroup = MockGenerators.idlObject({
    id: 16,
    name: 'Children\'s materials',
    owner: 1,
    pos: 1,
    top: 't'
}, 'acplg');

const mockPcrudService = MockGenerators.pcrudService({
    search: [adultGroup, teenGroup, childrensGroup]
});

const mockGlobalFlagService = MockGenerators.globalFlagService([{
    enabled: true,
    name: 'staff.search.shelving_location_groups_with_orgs'
}]);

describe('EnhancedOrgTree', () => {
    let service: EnhancedOrgTree;

    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [
                {provide: OrgService, useValue: mockOrgService},
                {provide: PcrudService, useValue: mockPcrudService},
                {provide: GlobalFlagService, useValue: mockGlobalFlagService}
            ]
        });
        service = TestBed.inject(EnhancedOrgTree);
    });

    it('should be created', () => {
        expect(service).toBeTruthy();
    });
    describe('toTreeObject()', async () => {
        it('can accept an arrow function for node label', async () => {
            const received = await service.toTreeObject((node) => `My favorite library: ${node.shortname()}`);
            expect(received.rootNode.label).toEqual('My favorite library: CONS');
            expect(received.rootNode.children[2].label).toEqual('My favorite library: BR');
        });

        it('removes orgs that are not staff_cat_visible', waitForAsync(async () => {
            const receivedTree = await service.toTreeObject();

            expect(receivedTree.rootNode.label).toEqual('CONS');
            expect(receivedTree.rootNode.children.filter(node => node.callerData.classname === 'aou').length).toEqual(1);
            expect(receivedTree.rootNode.children.map(child => child.label)).not.toContain('SYS');
            expect(receivedTree.rootNode.children.map(child => child.label)).toContain('BR');
        }));

        it('adds shelving location groups', waitForAsync(async () => {
            const expectedTree = new Tree(
                new TreeNode({
                    id: 1,
                    label: 'CONS',
                    callerData: consortium,
                    depth: 0,
                    children: [
                        new TreeNode({
                            id: 16,
                            label: 'Children\'s materials',
                            callerData: childrensGroup,
                            depth: 1
                        }),
                        new TreeNode({
                            id: 130,
                            label: 'Adult\'s materials',
                            callerData: adultGroup,
                            depth: 1
                        }),
                        new TreeNode({
                            id: 3,
                            label: 'BR',
                            callerData: branch,
                            depth: 1,
                            children: [
                                new TreeNode({
                                    id: 27,
                                    label: 'Teen\'s materials',
                                    callerData: teenGroup,
                                    depth: 2
                                })
                            ]
                        })
                    ]
                })
            );

            const receivedTree = await service.toTreeObject();

            expect(receivedTree.rootNode.children.length).toEqual(3);
            expect(receivedTree.rootNode.children[0]).toEqual(expectedTree.rootNode.children[0]);
            expect(receivedTree.rootNode.children[1]).toEqual(expectedTree.rootNode.children[1]);
            expect(receivedTree.rootNode.children[2]).toEqual(expectedTree.rootNode.children[2]);
            expect(receivedTree.rootNode.children[2].children.length).toEqual(1);
            expect(receivedTree.rootNode.children[2].children[0]).toEqual(expectedTree.rootNode.children[2].children[0]);
        }));
    });
});
