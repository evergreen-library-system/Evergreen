
export class TreeNode {
    // Unique identifier
    id: any;

    // Display label
    label: string;

    // True if child nodes should be visible
    expanded: boolean;

    children: TreeNode[];

    // Set by the tree.
    depth: number;

    // Set by the tree.
    selected: boolean;

    // Optional link to user-provided stuff.
    // This field is ignored by the tree.
    callerData: any;

    constructor(values: {[key: string]: any}) {
        this.children = [];
        this.expanded = true;
        this.depth = 0;
        this.selected = false;

        if (!values) { return; }

        if ('id' in values) { this.id = values.id; }
        if ('label' in values) { this.label = values.label; }
        if ('children' in values) { this.children = values.children; }
        if ('expanded' in values) { this.expanded = values.expanded; }
        if ('callerData' in values) { this.callerData = values.callerData; }
    }

    toggleExpand() {
        this.expanded = !this.expanded;
    }
}

export class Tree {

    rootNode: TreeNode;
    idMap: {[id: string]: TreeNode};

    constructor(rootNode?: TreeNode) {
        this.rootNode = rootNode;
        this.idMap = {};
    }

    // Returns a depth-first list of tree nodes
    // Tweaks node attributes along the way to match the shape of the tree.
    nodeList(filterHidden?: boolean): TreeNode[] {

        const nodes = [];

        const recurseTree =
            (node: TreeNode, depth: number, hidden: boolean) => {
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
                node.children.forEach(n => recurseTree(n, depth, !node.expanded));
            }
        };

        recurseTree(this.rootNode, 0, false);
        return nodes;
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

    findParentNode(node: TreeNode) {
        const list = this.nodeList();
        for (let idx = 0; idx < list.length; idx++) {
            const pnode = list[idx];
            if (pnode.children.filter(c => c.id === node.id).length) {
                return pnode;
            }
        }
        return null;
    }

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
        this.nodeList().forEach(node => node.expanded = true);
    }

    collapseAll() {
        this.nodeList().forEach(node => node.expanded = false);
    }

    selectedNode(): TreeNode {
        return this.nodeList().filter(node => node.selected)[0];
    }

    selectNode(node: TreeNode) {
        this.nodeList().forEach(n => n.selected = false);
        node.selected = true;
    }
}

