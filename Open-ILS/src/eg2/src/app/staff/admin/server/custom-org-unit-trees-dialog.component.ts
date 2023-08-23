/* eslint-disable no-empty */
import {Component, Input} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-custom-org-unit-trees-dialog',
    templateUrl: './custom-org-unit-trees-dialog.component.html'
})

export class CustomOrgUnitTreesDialogComponent
    extends DialogComponent {

    @Input() customTree: Tree;
    @Input() nodeToMove: TreeNode;

    moveNodeHereDisabled = false;

    constructor(
        private modal: NgbModal
    ) {
        super(modal);
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
