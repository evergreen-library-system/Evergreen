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

    parent: TreeNode;
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

        if (this.expanded) {
            this.applyChildrenCB()
        }
    }

    toggleExpand() {
        this.expanded = !this.expanded;
    }

    toggleStateFlag() {
        this.stateFlag = !this.stateFlag;
    }

    applyChildrenCB() {
        if (this.childrenCB) {
            this.children = this.childrenCB(this);
            this.children.forEach(child => child.parent = this);
            this.childrenCB = null;
        }
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
        clonedNode.children.forEach(child => child.parent = clonedNode);
        return clonedNode;
    }
}

export class Tree {

    treeId: any;
    rootNode: TreeNode;
    idMap: {[id: string]: TreeNode};
    restrictedNodes: TreeNode[];

    constructor(rootNode?: TreeNode) {
        this.treeId = parseInt((Math.random() * 1000) + '');
        this.rootNode = rootNode;
        this.idMap = {};
        this.restrictedNodes = [];
    }

    visibleChildren(node: TreeNode, shallow?: boolean): TreeNode[] {
        this.maybeMaintainState(node);
        if (!shallow) {
            node.applyChildrenCB();
        }

        if (!this.restrictedNodes.length) { // no restriction, return the whole list
            return node.children;
        }

        const restricted_with_ancestors = [];
        this.restrictedNodes.forEach(n => restricted_with_ancestors.push(... this.pathTo(n).filter(x => !!x)));

        return node.children.filter(n => restricted_with_ancestors.indexOf(n) > -1);
    }

    visibleDescendants(node: TreeNode): TreeNode[] {
        this.maybeMaintainState(node);
        const nodes = [];
        const recurseTree = (node: TreeNode) => {
            if (node) {
                nodes.push(node);
                this.visibleChildren(node, true).forEach(n => recurseTree(n));
            }
        };

        recurseTree(node);
        return nodes;
    }

    // Returns a list of tree nodes
    nodeList(filterHidden?: boolean): TreeNode[] {
        if (!filterHidden) {
            if (!Object.values(this.idMap).length) {
                return this.descendants(this.rootNode);
            }
            return Object.values(this.idMap);
        }
        return this.descendants(this.rootNode, filterHidden);
    }

    // Returns a depth-first list of tree nodes
    // Tweaks node attributes along the way to match the shape of the tree.
    descendants(node: TreeNode, filterHidden?: boolean): TreeNode[] {
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

                if (!hidden) {
                    node.applyChildrenCB();
                }

                node.children.forEach(n => n.parent = node);
                if (filterHidden) {
                    this.visibleChildren(node).forEach(n => recurseTree(n, depth, !node.expanded));
                } else {
                    node.children.forEach(n => recurseTree(n, depth, !node.expanded));
                }
            }
        };

        recurseTree(node, node.depth, false);
        return nodes;
    }

    private maybeMaintainState(node: TreeNode) {
        if (!node.parent && node !== this.rootNode) {
            this.descendants(this.rootNode);
        }
    }

    findStateFlagNodes(): TreeNode[] {
        return this.nodeList().filter(n => n.stateFlag);
    }

    findNode(id: any): TreeNode {
        if (this.idMap[id + '']) {
            return this.idMap[id + ''];
        } else {
            // descendants() re-indexes all the nodes.
            this.descendants(this.rootNode)
            return this.idMap[id + ''];
        }
    }

    findNodesByFieldAndValue(field: string, value: any): TreeNode[] {
        return this.nodeList().filter(n => n[field]?.toString() == value.toString());
    }

    findNodesByFieldAndValueSearch(field: string, value: string): TreeNode[] { // find nodes where $field.toLocaleLowerCase() contains $value.toLocaleLowerCase()
        return this.nodeList().filter(n => n[field]?.toString().toLocaleLowerCase().search(value.toLocaleLowerCase()) > -1);
    }

    findParentNode(node: TreeNode, findHidden?: boolean) {
        this.maybeMaintainState(node);
        return node.parent;
    }

    pathTo(node: TreeNode): TreeNode[] {
        this.maybeMaintainState(node);
        let pathNodes = [node];
        let nextNode = node.parent;
        while (nextNode) {
            pathNodes.push(nextNode);
            nextNode = nextNode.parent;
        }
        return pathNodes;
    }

    expandPathTo(node: TreeNode) {
        this.maybeMaintainState(node);
        this.pathTo(node).forEach(n => n.expanded = true);
    }

    findNodePath(node: TreeNode) {
        this.maybeMaintainState(node);
        const path = [];
        do {
            const pnode = {...node};
            delete pnode['parent'];
            delete pnode['children'];
            delete pnode['childrenCB'];
            path.push({...pnode});
        } while (node = node.parent);
        return path.reverse();
    }

    // only work on non-dynamic trees, that is, those with no childrenCB callback function
    removeNode(node: TreeNode) {
        if (!node) { return; }
        this.maybeMaintainState(node);
        const pnode = node.parent;
        if (pnode) {
            node.parent = null; // to help the GC find blind ref
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
        this.maybeMaintainState(node);
        this.nodeList().forEach(n => n.selected = false);
        node.selected = true;
    }

    unSelectNode(node: TreeNode) {
        this.maybeMaintainState(node);
        node.selected = false;
    }

    toggleNodeSelection(node: TreeNode) {
        this.maybeMaintainState(node);
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

