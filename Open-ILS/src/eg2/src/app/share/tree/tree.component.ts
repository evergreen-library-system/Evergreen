/* eslint-disable */
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

    static lastClickedTree: TreeComponent;

    _nodeList: any = [];
    _tree: Tree;
    _prev_stateFlagClick: TreeNode;
    _labelFilter = '';
    _labelFilterDebounceTimeout: any = null;

    @Input() showLabelFilter = false; // Allow filtering by node label
    @Input() disabled = false; // disables /changing/ state flag or emitting selection events
    @Input() set tree(t: Tree) {
        if (t) {
            this._tree = t;
            this._tree.nodeList(); // reindex nodes
        }
    }

    @ViewChildren('egTreeNode') visibleNodeList: QueryList<ElementRef>;
    @ViewChildren('stateFlagContainer') stateFlagContainerList: QueryList<ElementRef>;

    get tree(): Tree {
        return this._tree;
    }

    @Input() showSelectAll = false; // checkbox to toggle all state flags.
    @Input() showExpandAll = true; // show the expand/collapse all arrows?
    @Input() disableRootSelector = false; // checkbox at the top of the tree
    @Input() disableStateFlag = false; // Hide all checkboxes
    @Input() disableStateFlagRangeSelect = false; // Disable range selection
    @Input() rowTrailingTemplate: TemplateRef<any>;
    @Input() stateFlagTemplate: TemplateRef<any>;

    @Output() nodeClicked: EventEmitter<TreeNode>;
    @Output() stateFlagClicked: EventEmitter<TreeNode>;

    constructor() {
        this.nodeClicked = new EventEmitter<TreeNode>();
        this.stateFlagClicked = new EventEmitter<TreeNode>();
    }

    rootNode(): TreeNode {
        return this.tree?.rootNode;
    }

    displayNodes(): TreeNode[] {
        if (!this.tree) { return []; }
        this._nodeList = this.tree.nodeList(true);
        return this._nodeList;
    }

    updateLabelFilter() {
        clearTimeout(this._labelFilterDebounceTimeout);
        if (!this._labelFilter) {
            this.tree.restrictedNodes = [];
        } else {
            this._labelFilterDebounceTimeout = setTimeout( () => {
                this.tree.restrictedNodes = this.tree.findNodesByFieldAndValueSearch('label',this._labelFilter);
                this.tree.restrictedNodes.forEach(n => this.tree.expandPathTo(n));
            }, 250);
        }
    }

    handleNodeClick(node: TreeNode, $event) {
        if (this.disableRootSelector && node === this.rootNode()) {
            return;
        }
        if (!this.disabled) {
            if (!this.disableStateFlagRangeSelect     // If shift-click range selection is allowed ...
                && $event?.shiftKey                   // ... and shift is currently pressed ...
                && this._prev_stateFlagClick          // ... and range selection has been started ...
                && this._prev_stateFlagClick !== node // ... and this isn't the same node as the selection start ...
            ) { // ... then we treat this as a checkbox range selection shift-click.
                this.handleStateFlagClick(node, $event);
            } else {
                this._prev_stateFlagClick = null; // forget last state flag click
                this.nodeClicked.emit(node);
            }
            this.tree.selectNode(node);
            TreeComponent.lastClickedTree = this;
        }
    }

    handleStateFlagClick(node: TreeNode, $event) {
        if (!this.disabled) {
            node.toggleStateFlag();
            if (!this.disableStateFlagRangeSelect) { // shift-click child selection is allowed
                if ($event?.shiftKey) { // shift-click child selection happened
                    this.tree.visibleDescendants(node).forEach(n => n.stateFlag = node.stateFlag); // make descendants match clicked state flag
                    if (this._prev_stateFlagClick && this._prev_stateFlagClick !== node) { // shift-click range selection, different previous node
                        const new_state = this._prev_stateFlagClick.stateFlag;
                        node.stateFlag = new_state;

                        const NL = this.tree.visibleDescendants(this.rootNode());
                        let range_start = NL.indexOf(this._prev_stateFlagClick);
                        let range_end = NL.indexOf(node);

                        if (range_start > -1 && range_end > -1) { // valid range
                            if (range_start > range_end) { // clicked above! swap them, and shift
                                range_end++;
                                [range_start, range_end] = [range_end, range_start];
                                range_end++;
                            }
                            NL.slice(range_start,range_end).forEach(n => n.stateFlag = new_state);
                        }
                    }
                }
                this._prev_stateFlagClick = node; // remember last state flag click
            }
            this.stateFlagClicked.emit(node);
            TreeComponent.lastClickedTree = this;
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
        const DOMind = this.displayNodes().indexOf(node);
        const visibleNL = this.visibleNodeList.toArray();

        // Allow the state flag template to control all it's key events
        if (this.stateFlagContainerList.toArray().find(sfc => sfc.nativeElement === $event.target || sfc.nativeElement.contains($event.target))) {return;}

        console.log('Node index: ' + DOMind + '; Key pressed: ', $event.code);
        if (!$event.key || $event.repeat || $event.code == 'Tab') {return;}

        // arrow keys are required to operate these form fields
        if ($event.target.tagName.toLowerCase() == 'select' || $event.target.tagName.toLowerCase() == 'textarea') {return;}

        switch ($event.key) {
            case 'Enter':
            case ' ':
                this.handleNodeClick(node, $event);
                $event.stopPropagation();
                $event.preventDefault();
                break;
            case 'ArrowRight':
	       		if (node.children.length) {node.expanded = true;}
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
                    const nextTargetNode = this.displayNodes()[DOMind + 1];
                    const target = visibleNL.filter(v => v.nativeElement.id == this.tree.treeId + '-' + nextTargetNode.id)[0];
	        		target.nativeElement.focus();
                }
                $event.stopPropagation();
                $event.preventDefault();
                break;
            case 'ArrowUp':
                if (DOMind > 0) {
                    const prevTargetNode = this.displayNodes()[DOMind - 1];
                    const target = visibleNL.filter(v => v.nativeElement.id == this.tree.treeId + '-' + prevTargetNode.id)[0];
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
                if (!(this.disableRootSelector && (node === this.rootNode()))) {
                    node.stateFlag = true;
                    this.stateFlagClicked.emit(node);
                }
            });
        }
    }

    deselectAll() {
        if (this.tree) {
            this.tree.nodeList().forEach(node => {
                if (!(this.disableRootSelector && (node === this.rootNode()))) {
                    node.stateFlag = false;
                    this.stateFlagClicked.emit(node);
                }
            });
        }
    }

    wasLastClicked(): boolean {
        return TreeComponent.lastClickedTree === this;
    }

}



