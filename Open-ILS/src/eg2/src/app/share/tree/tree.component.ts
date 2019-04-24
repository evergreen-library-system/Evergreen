import {Component, OnInit, Input, Output, EventEmitter} from '@angular/core';
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
export class TreeComponent implements OnInit {

    @Input() tree: Tree;
    @Output() nodeClicked: EventEmitter<TreeNode>;

    constructor() {
        this.nodeClicked = new EventEmitter<TreeNode>();
    }

    ngOnInit() {}

    displayNodes(): TreeNode[] {
        return this.tree.nodeList(true);
    }

    handleNodeClick(node: TreeNode) {
        this.tree.selectNode(node);
        this.nodeClicked.emit(node);
    }
}



