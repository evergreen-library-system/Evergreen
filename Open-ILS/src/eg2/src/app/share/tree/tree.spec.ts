import { TreeNode, Tree } from './tree';

const rootNode = new TreeNode({id: 1, label: 'Root 1'});
const child1 = new TreeNode({id: 3, label: 'Child 1'});
const child2 = new TreeNode({
    id: 4,
    label: 'Another Child with number 2',
    children: [
        new TreeNode({id: 5, label: 'Grandchild 1'})
    ]
});
rootNode.addChild(child1);
rootNode.addChild(child2);
const tree = new Tree(rootNode);

describe('Tree', () => {
    describe('nodeList()', () => {
        it('includes the org depth', () => {
            const nodeList = tree.nodeList();
            expect(nodeList.length).toEqual(4);
            expect(nodeList[0].label).toEqual('Root 1');
            expect(nodeList[0].depth).toEqual(0);
            expect(nodeList[1].label).toEqual('Child 1');
            expect(nodeList[1].depth).toEqual(1);
            expect(nodeList[2].label).toEqual('Another Child with number 2');
            expect(nodeList[2].depth).toEqual(1);
            expect(nodeList[3].label).toEqual('Grandchild 1');
            expect(nodeList[3].depth).toEqual(2);
        });
    });
});
