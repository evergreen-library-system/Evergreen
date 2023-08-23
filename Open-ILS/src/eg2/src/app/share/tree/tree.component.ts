import {Component, Input, Output, ViewChildren, QueryList, ElementRef, EventEmitter, TemplateRef} from '@angular/core';
import {Tree, TreeNode} from './tree';

/*
Tree Widget:

<eg-tree
    [tree]="myTree"
    (nodeClicked)="nodeClicked($event)"
    (stateFlagClicked)="stateFlagClicked($event)">
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

    _nodeList: any = [];
    _tree: Tree;
    @Input() disabled: boolean = false; // disables /changing/ state flag or emitting selection events
    @Input() set tree(t: Tree) {
        if (t) {
            this._tree = t;
            this._tree.nodeList(); // reindex nodes
        }
    }

    @ViewChildren('egTreeNode') visibleNodeList: QueryList<ElementRef>;

    get tree(): Tree {
        return this._tree;
    }

    @Input() showSelectAll = false; // checkbox to toggle all state flags.
    @Input() showExpandAll = true; // show the expand/collapse all arrows?
    @Input() disableRootSelector = false; // checkbox at the top of the tree
    @Input() rowTrailingTemplate: TemplateRef<any>;

    @Output() nodeClicked: EventEmitter<TreeNode>;
    @Output() stateFlagClicked: EventEmitter<TreeNode>;

    constructor() {
        this.nodeClicked = new EventEmitter<TreeNode>();
        this.stateFlagClicked = new EventEmitter<TreeNode>();
    }

    displayNodes(): TreeNode[] {
        if (!this.tree) { return []; }
        this._nodeList = this.tree.nodeList(true);
        return this._nodeList;
    }

    handleNodeClick(node: TreeNode) {
        if (this.disableRootSelector && node === this.tree.rootNode) {
            return;
        }
        if (!this.disabled) {
            this.tree.selectNode(node);
            this.nodeClicked.emit(node);
        }
    }

    handleStateFlagClick(node: TreeNode) {
        if (!this.disabled) {
            node.toggleStateFlag();
            this.stateFlagClicked.emit(node);
        }
    }

/*  // Maybe for later
    treeFocusEvent($event: any) {
        console.log("Tree Focus:", $event);
        //this.showFocusableElements($event.target);
    }

    treeBlurEvent($event: any) {
        console.log("Tree Blur:", $event);
        //this.hideFocusableElements($event.target);
    }
*/

    treeKeyEvent(node: TreeNode, $event: any) {
		const DOMind = this._nodeList.indexOf(node);
		const visibleNL = this.visibleNodeList.toArray();

        console.log("Node index: " + DOMind + "; Key pressed: ", $event.code);
        if (!$event.key || $event.repeat || $event.code == "Tab") return;

        // arrow keys are required to operate these form fields
        if ($event.target.tagName.toLowerCase() == 'select' || $event.target.tagName.toLowerCase() == 'textarea') return;

        switch ($event.key) {
            case 'Enter':
            case 'Space':
				this.handleNodeClick(node);
                $event.stopPropagation();
                $event.preventDefault();
                break;
            case 'ArrowRight':
	       		if (node.children.length)
					node.expanded = true;
                $event.stopPropagation();
                $event.preventDefault();
                break;
            case 'ArrowLeft':
	       		node.expanded = false;
                $event.stopPropagation();
                $event.preventDefault();
                break;
            case 'ArrowDown':
				if (visibleNL.length > DOMind + 1) {
					const nextTargetNode = this._nodeList[DOMind + 1];
					const target = visibleNL.filter(v => v.nativeElement.id == this._tree.treeId + '-' + nextTargetNode.id)[0];
	        		target.nativeElement.focus();
				}
                $event.stopPropagation();
                $event.preventDefault();
                break;
            case 'ArrowUp':
				if (DOMind > 0) {
					const prevTargetNode = this._nodeList[DOMind - 1];
					const target = visibleNL.filter(v => v.nativeElement.id == this._tree.treeId + '-' + prevTargetNode.id)[0];
	        		target.nativeElement.focus();
				}
                $event.stopPropagation();
                $event.preventDefault();
                break;
            default:
                return false;
        }
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

    toggleStateFlags(ev: any) {
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
                    node.stateFlag = true;
                }
            });
        }
    }

    deselectAll() {
        if (this.tree) {
            this.tree.nodeList().forEach(node => {
                if (!(this.disableRootSelector && (node === this.tree.rootNode))) {
                    node.stateFlag = false;
                }
            });
        }
    }

}



