/* eslint-disable */

export class TreeNode {
    // Unique identifier
    id: any;

    // Display label
    label: string;

    // If set, the state flag is displayed and this is the tooltip
    stateFlagLabel: string;

    // True if child nodes should be visible
    expanded: boolean;

    // opaque "marked" flag for use by caller
    stateFlag: boolean;

    children: TreeNode[];

    // function! accepts this tree node as a param, so you can use callerData as extra info
    childrenCB: any;

    // Set by the tree.
    depth: number;

    // Set by the tree.
    selected: boolean;

    // Optional link to user-provided stuff.
    // This field is ignored by the tree.
    callerData: any;

    // Internal pointer to the owning tree

    constructor(values: {[key: string]: any}) {
        this.children = [];
        this.childrenCB = null;
        this.expanded = true;
        this.stateFlag = false;
        this.stateFlagLabel = null;
        this.depth = 0;
        this.selected = false;

        if (!values) { return; }

        if ('id' in values) { this.id = values.id; }
        if ('label' in values) { this.label = values.label; }
        if ('stateFlagLabel' in values) { this.stateFlagLabel = values.stateFlagLabel; }
        if ('children' in values) { this.children = values.children; }
        if ('childrenCB' in values) { this.childrenCB = values.childrenCB; }
        if ('expanded' in values) { this.expanded = values.expanded; }
        if ('stateFlag' in values) { this.stateFlag= values.stateFlag; }
        if ('callerData' in values) { this.callerData = values.callerData; }

        if (this.expanded && this.childrenCB) {
            this.children = this.childrenCB(this);
            this.childrenCB = null;
        }
    }

    toggleExpand() {
        this.expanded = !this.expanded;
    }

    toggleStateFlag() {
        this.stateFlag = !this.stateFlag;
    }

    clone(overlay?: any): TreeNode {
        overlay ||= {};

        const clonedNode = new TreeNode({
            id: 'id' in overlay ? overlay['id'] : this.id,
            label: 'label' in overlay ? overlay['label'] : this.label,
            expanded: 'expanded' in overlay ? overlay['expanded'] : this.expanded,
            stateFlag: 'stateFlag' in overlay ? overlay['stateFlag'] : this.stateFlag,
            stateFlagLabel: 'stateFlagLabel' in overlay ? overlay['stateFlagLabel'] : this.stateFlagLabel,
            childrenCB: 'childrenCB' in overlay ? overlay['childrenCB'] : this.childrenCB,
            callerData: 'callerData' in overlay ? overlay['callerData'] : this.callerData // NOTE: shallow copy
        });

        clonedNode.children = this.children.map(child => child.clone(overlay));
        return clonedNode;
    }
}

export class Tree {

    treeId: any;
    rootNode: TreeNode;
    idMap: {[id: string]: TreeNode};

    constructor(rootNode?: TreeNode) {
        this.treeId = parseInt((Math.random() * 1000) + '');
        this.rootNode = rootNode;
        this.idMap = {};
    }

    // Returns a depth-first list of tree nodes
    // Tweaks node attributes along the way to match the shape of the tree.
    nodeList(filterHidden?: boolean): TreeNode[] {

        const nodes = [];

        const recurseTree = (node: TreeNode, depth: number, hidden: boolean) => {
            if (!node) { return; }

            node.depth = depth++;
            this.idMap[node.id + ''] = node;

            if (hidden) {
            // it could be confusing for a hidden node to be selected.
                node.selected = false;
            }

            if (hidden && filterHidden) {
                // Avoid adding hidden child nodes to the list.
            } else {
                nodes.push(node);

                if (!hidden && node.childrenCB) {
                    node.children = node.childrenCB(node);
                    node.childrenCB = null;
                }

                node.children.forEach(n => recurseTree(n, depth, !node.expanded));
            }
        };

        recurseTree(this.rootNode, 0, false);
        return nodes;
    }

    findStateFlagNodes(): TreeNode[] {
        return this.nodeList().filter(n => n.stateFlag);
    }

    findNode(id: any): TreeNode {
        if (this.idMap[id + '']) {
            return this.idMap[id + ''];
        } else {
            // nodeList re-indexes all the nodes.
            this.nodeList();
            return this.idMap[id + ''];
        }
    }

    findNodesByFieldAndValue(field: string, value: any): TreeNode[] {
        const list = this.nodeList();
        const found = [];
        for (let idx = 0; idx < list.length; idx++) {
            if (list[idx][field] === value) {
                found.push( list[idx] );
            }
        }
        return found;
    }

    findParentNode(node: TreeNode, findHidden?: boolean) {
        const list = this.nodeList(findHidden ? false : true);
        for (let idx = 0; idx < list.length; idx++) {
            const pnode = list[idx];
            if (pnode.children.filter(c => c.id === node.id).length) {
                return pnode;
            }
        }
        return null;
    }

    expandPathTo(node: TreeNode) {
        let nextNode = this.findParentNode(node, true);
        while (nextNode) {
            nextNode.expanded = true;
            nextNode = this.findParentNode(nextNode, true);
        }
    }

    findNodePath(node: TreeNode) {
        const path = [];
        do {
            const pnode = {...node};
            delete pnode['children'];
            delete pnode['childrenCB'];
            path.push({...pnode});
        } while (node = this.findParentNode(node));
        return path.reverse();
    }

    // only work on non-dynamic trees, that is, those with no childrenCB callback function
    removeNode(node: TreeNode) {
        if (!node) { return; }
        const pnode = this.findParentNode(node);
        if (pnode) {
            pnode.children = pnode.children.filter(n => n.id !== node.id);
        } else {
            this.rootNode = null;
        }
    }

    expandAll() {
        if (this.rootNode) {
            this.nodeList().forEach(node => node.expanded = true);
        }
    }

    collapseAll() {
        if (this.rootNode) {
            this.nodeList().forEach(node => node.expanded = false);
        }
    }

    selectedNode(): TreeNode {
        return this.nodeList().find(node => node.selected);
    }

    selectNode(node: TreeNode) {
        this.nodeList().forEach(n => n.selected = false);
        node.selected = true;
    }

    unSelectNode(node: TreeNode) {
        node.selected = false;
    }

    toggleNodeSelection(node: TreeNode) {
        node.selected = !node.selected;
    }

    selectNodes(nodes: TreeNode[]) {
        this.nodeList().forEach(n => n.selected = false);
        nodes.forEach(node => {
            const foundNode = this.findNode(node.id);
            if (foundNode) {
                foundNode.selected = true;
            }
        });
    }

    clone(overlay?: any): Tree {
        const clonedTree = new Tree(this.rootNode.clone(overlay));
        return clonedTree;
    }
}

