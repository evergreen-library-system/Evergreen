import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';

@Component({
    templateUrl: './org-unit-type.component.html'
})

export class OrgUnitTypeComponent implements OnInit {

    tree: Tree;
    selected: TreeNode;
    @ViewChild('editDialog') editDialog: FmRecordEditorComponent;
    @ViewChild('editString') editString: StringComponent;
    @ViewChild('createString') createString: StringComponent;
    @ViewChild('errorString') errorString: StringComponent;
    @ViewChild('delConfirm') delConfirm: ConfirmDialogComponent;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private toast: ToastService
    ) {}


    ngOnInit() {
        this.loadAoutTree();
    }

    loadAoutTree() {
        this.pcrud.search('aout', {depth: 0},
            {flesh: -1, flesh_fields: {aout: ['children']}},
            {anonymous: true}
        ).subscribe(aoutTree => this.ingestAoutTree(aoutTree));
    }

    // Translate the org unt type tree into a structure EgTree can use.
    ingestAoutTree(aoutTree) {

        const handleNode = (aoutNode: IdlObject): TreeNode => {
            if (!aoutNode) { return; }

            const treeNode = new TreeNode({
                id: aoutNode.id(),
                label: aoutNode.name(),
                callerData: aoutNode
            });

            aoutNode.children().forEach(childNode =>
                treeNode.children.push(handleNode(childNode))
            );

            return treeNode;
        };

        const rootNode = handleNode(aoutTree);
        this.tree = new Tree(rootNode);
    }

    nodeClicked($event: any) {
        this.selected = $event;
    }

    postUpdate(message: StringComponent) {
        // Modifying org unit types means refetching the org unit
        // data normally fetched on page load, since it includes
        // org unit type data.
        this.org.fetchOrgs().then(
            ok => {
                message.current().then(str => this.toast.success(str));
            }
        );
    }

    edit() {
        this.editDialog.mode = 'update';
        this.editDialog.setRecord(this.selected.callerData);

        this.editDialog.open().then(
            success => {
                this.postUpdate(this.editString);
            },
            rejected => {
                if (rejected && rejected.dismissed) {
                    return;
                }
                this.errorString.current()
                    .then(str => this.toast.danger(str));
            }
        );
    }

    remove() {
        this.delConfirm.open().then(
            ok => {
                this.pcrud.remove(this.selected.callerData)
                .subscribe(
                    ok2 => {},
                    err => {
                        this.errorString.current()
                          .then(str => this.toast.danger(str));
                    },
                    ()  => {
                        // Avoid updating until we know the entire
                        // pcrud action/transaction completed.
                        this.tree.removeNode(this.selected);
                        this.selected = null;
                        this.postUpdate(this.editString);
                    }
                );
            },
            notConfirmed => {}
        );
    }

    addChild() {
        const parentTreeNode = this.selected;
        const parentType = parentTreeNode.callerData;

        const newType = this.idl.create('aout');
        newType.parent(parentType.id());
        newType.depth(Number(parentType.depth()) + 1);

        this.editDialog.setRecord(newType);
        this.editDialog.mode = 'create';

        this.editDialog.open().then(
            result => { // aout object

                // Add our new node to the tree
                const newNode = new TreeNode({
                    id: result.id(),
                    label: result.name(),
                    callerData: result
                });
                parentTreeNode.children.push(newNode);
                this.postUpdate(this.createString);
            },

            rejected => {
                if (rejected && rejected.dismissed) {
                    return;
                }
                this.errorString.current()
                    .then(str => this.toast.danger(str));
            }
        );
    }
}

