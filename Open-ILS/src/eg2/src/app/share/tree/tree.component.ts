import {Component, Input, Output, EventEmitter, TemplateRef} from '@angular/core';
import {Tree, TreeNode} from './tree';

/*
Tree Widget:

<eg-tree
    [tree]="myTree"
    (nodeClicked)="nodeClicked($event)">
</eg-tree>

----

constructor() {

    const rootNode = new TreeNode({
        id: 1,
        label: 'Root',
        children: [
            new TreeNode({id: 2, label: 'Child'}),
            new TreeNode({id: 3, label: 'Child2'})
        ]
    ]});

    this.myTree = new Tree(rootNode);
}

nodeClicked(node: TreeNode) {
    console.log('someone clicked on ' + node.label);
}
*/

@Component({
    selector: 'eg-tree',
    templateUrl: 'tree.component.html',
    styleUrls: ['tree.component.css']
})
export class TreeComponent {

    _tree: Tree;
    @Input() set tree(t: Tree) {
        if (t) {
            this._tree = t;
            this._tree.nodeList(); // reindex nodes
        }
    }

    get tree(): Tree {
        return this._tree;
    }

    @Input() showSelectors = false; // the checkboxes, etc.
    @Input() disableRootSelector = false; // checkbox at the top of the tree
    @Input() toggleOnClick = false; // selectNode vs toggleNodeSelection
    @Input() rowTrailingTemplate: TemplateRef<any>;

    @Output() nodeClicked: EventEmitter<TreeNode>;
    @Output() nodeChecked: EventEmitter<TreeNode>;

    constructor() {
        this.nodeClicked = new EventEmitter<TreeNode>();
        this.nodeChecked = new EventEmitter<TreeNode>();
    }

    displayNodes(): TreeNode[] {
        if (!this.tree) { return []; }
        return this.tree.nodeList(true);
    }

    handleNodeClick(node: TreeNode) {
        if (this.disableRootSelector && node === this.tree.rootNode) {
            return;
        }
        if (this.toggleOnClick) {
            this.tree.toggleNodeSelection(node);
        } else {
            this.tree.selectNode(node);
        }
        this.nodeClicked.emit(node);
    }

    handleNodeCheck(node: TreeNode) {
        // If needed, add logic here to handle the case where
        // a node's checkbox was clicked.
        // since ngModel is node.selected, we don't need to set it ourselves
        // this.handleNodeClick(node);
        this.nodeClicked.emit(node);
    }

    expandAll() {
        if (this.tree) {
            this.tree.expandAll();
        }
    }

    collapseAll() {
        if (this.tree) {
            this.tree.collapseAll();
        }
    }

    toggleSelections(ev: any) {
        if (ev.target.checked) {
            this.selectAll();
        } else {
            this.deselectAll();
        }
    }

    selectAll() {
        if (this.tree) {
            this.tree.nodeList().forEach(node => {
                if (!(this.disableRootSelector && (node === this.tree.rootNode))) {
                    node.selected = true;
                }
            });
        }
    }

    deselectAll() {
        if (this.tree) {
            this.tree.nodeList().forEach(node => {
                if (!(this.disableRootSelector && (node === this.tree.rootNode))) {
                    node.selected = false;
                }
            });
        }
    }

}



