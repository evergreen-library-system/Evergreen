/* eslint-disable no-empty */
import { Component, Input, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import { TreeComponent } from '@eg/share/tree/tree.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-custom-org-unit-trees-dialog',
    templateUrl: './custom-org-unit-trees-dialog.component.html',
    imports: [
        TreeComponent
    ]
})

export class CustomOrgUnitTreesDialogComponent
    extends DialogComponent {
    private modal: NgbModal;


    @Input() customTree: Tree;
    @Input() nodeToMove: TreeNode;

    moveNodeHereDisabled = false;

    constructor() {
        const modal = inject(NgbModal);

        super(modal);
        this.modal = modal;

        if (this.modal) {} // de-lint
    }

    dialog_nodeClicked($event: any) {
        console.log('dialog: dialog_nodeClicked',typeof $event);
        this.moveNodeHereDisabled = !this.isMoveNodeHereAllowed();
    }

    isMoveNodeHereAllowed(): boolean {
        return !!this.customTree.selectedNode();
    }

    moveNodeHere() {
        const selectedNode = this.customTree.selectedNode();
        this.moveNodeHereDisabled = !this.isMoveNodeHereAllowed();
        if (this.moveNodeHereDisabled) {
            return;
        }
        this.close(selectedNode);
    }

}
