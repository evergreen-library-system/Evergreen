/* eslint-disable no-await-in-loop, no-shadow */
import {Component, ViewChild, OnInit} from '@angular/core';
import {catchError, firstValueFrom, lastValueFrom, of, take, defaultIfEmpty} from 'rxjs';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {CustomOrgUnitTreesDialogComponent} from './custom-org-unit-trees-dialog.component';

@Component({
    templateUrl: './custom-org-unit-trees.component.html',
    styleUrls: [ './custom-org-unit-trees.component.css' ],
})

export class CustomOrgUnitTreesComponent implements OnInit {

    tree: Tree;
    custom_tree: Tree;
    aouctn_root: IdlObject;
    tree_type: IdlObject;
    active = false;
    selected: TreeNode;
    custom_selected: TreeNode;
    orgUnitTab: string;
    singleNodeSelected = false;
    multipleNodesSelected = false;
    noNodesSelected = false;

    @ViewChild('editString', { static: true }) editString: StringComponent;
    @ViewChild('errorString', { static: true }) errorString: StringComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: true }) updateFailedString: StringComponent;
    @ViewChild('delConfirm', { static: true }) delConfirm: ConfirmDialogComponent;
    @ViewChild('moveNodeElsewhereDialog', { static: true })
        moveNodeElsewhereDialog: CustomOrgUnitTreesDialogComponent;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        // private strings: StringService,
        private toast: ToastService
    ) {}


    async ngOnInit() {
        try {
            await this.loadAouTree(this.org.root().id());
            await this.loadCustomTree('opac');
            // console.warn('CustomOrgUnitTreesComponent, this', this);
        } catch(E) {
            console.error('caught during ngOnInit',E);
        }
    }

    async loadAouTree(selectNodeId?: number): Promise<any> {
        const flesh = ['children', 'ou_type', 'hours_of_operation'];

        try {
            const tree = await firstValueFrom(this.pcrud.search('aou', {parent_ou : null},
                {flesh : -1, flesh_fields : {aou : flesh}}, {authoritative: true}
            ));

            this.ingestAouTree(tree); // sets this.tree as a side-effect
            if (!selectNodeId) { selectNodeId = this.org.root().id(); }

            /* const node = this.tree.findNode(selectNodeId);
            this.selected = node;
            this.tree.selectNode(node);*/

            return this.tree;
        } catch (E) {
            console.warn('caught from pcrud (aou)', E);
        }
    }

    async loadCustomTree(purpose: string): Promise<any> {
        const flesh = ['children', 'org_unit'];

        this.tree_type = await firstValueFrom(
            this.pcrud.search('aouct', { purpose: purpose })
                .pipe(
                    take(1),
                    defaultIfEmpty(undefined),
                    catchError((err: unknown) => {
                        console.warn('caught from pcrud (aouct): 1', err);
                        return of(undefined);
                    })
                )
        );

        let tree_id: number;
        if (this.tree_type) {
            tree_id = this.tree_type.id();
            this.active = this.tree_type.active() === 't';
        } else {
            tree_id = null;
        }

        this.aouctn_root = undefined;
        if (tree_id) {
            this.aouctn_root = await firstValueFrom(
                this.pcrud.search('aouctn', {tree: tree_id, parent_node: null},
                    {flesh: -1, flesh_fields: {aouctn: flesh}}, {authoritative: true})
                    .pipe(
                        take(1),
                        defaultIfEmpty(undefined),
                        catchError((err: unknown) => {
                            console.warn('phasefx: caught from pcrud (aouctn): 2', err);
                            return of(undefined);
                        })
                    )
            );
        } else {
            this.tree_type = this.idl.create('aouct');
            this.tree_type.isnew('t');
            this.tree_type.purpose('opac');
            this.tree_type.active(this.active ? 't' : 'f');
        }
        if (this.aouctn_root) {
            this.ingestCustomTree(this.aouctn_root); // sets this.custom_tree as a side-effect
        } else {
            this.custom_tree = this.tree.clone({stateFlagLabel:$localize`Select for adjustment`});
        }
        return this.custom_tree;
    }

    // Translate the org unt type tree into a structure EgTree can use.
    ingestAouTree(aouTree: IdlObject) {

        const handleNode = (orgNode: IdlObject, expand?: boolean): TreeNode => {
            if (!orgNode) { return; }

            const treeNode = new TreeNode({
                id: orgNode.id(),
                label: orgNode.name() + '--' + orgNode.shortname(),
                callerData: {orgId: orgNode.id()},
                expanded: expand,
                stateFlagLabel: $localize`Select for custom tree`
            });

            // Tree node labels are "name -- shortname".  Sorting
            // by name suffices and bypasses the need the wait
            // for all of the labels to interpolate.
            orgNode.children()
                .sort((a: IdlObject, b: IdlObject) => a.name() < b.name() ? -1 : 1)
                .forEach((childNode: IdlObject) =>
                    treeNode.children.push(handleNode(childNode))
                );

            return treeNode;
        };

        const rootNode = handleNode(aouTree, true);
        this.tree = new Tree(rootNode);
    }

    ingestCustomTree(aouctnTree: IdlObject) {

        const handleNode = (orgNode: IdlObject, expand?: boolean): TreeNode => {
            if (!orgNode) { return; }

            const treeNode = new TreeNode({
                id: orgNode.id(),
                label: orgNode.org_unit().name() + '--' + orgNode.org_unit().shortname(),
                callerData: {orgId: orgNode.org_unit().id()},
                expanded: expand,
                stateFlagLabel: $localize`Select for adjustment`
            });

            orgNode.children()
                .sort((a: IdlObject, b: IdlObject) => a.sibling_order() < b.sibling_order() ? -1 : 1)
                .forEach((childNode: IdlObject) =>
                    treeNode.children.push(handleNode(childNode))
                );

            return treeNode;
        };

        const rootNode = handleNode(aouctnTree, true);
        this.custom_tree = new Tree(rootNode);
    }

    nodeClicked($event: any) {
        // this.selected = $event;
        // console.log('custom: nodeClicked',typeof $event);
    }

    custom_nodeClicked($event: any) {
        // this.custom_selected = $event;
        // console.log('custom: custom_nodeClicked',typeof $event);
    }

    nodeChecked($event: any) {
        // this.selected = $event;
        // console.log('custom: nodeChecked',typeof $event);
    }

    custom_nodeChecked($event: any) {
        // this.custom_selected = $event;
        this.custom_tree.selectNode($event);
        // console.debug('custom: custom_nodeChecked',typeof $event);
        //console.debug('custom: selected node: ', $event);
    }

    isCopyNodesAllowed(): boolean {
        try {
            if (!this.tree) {
                // console.log('isCopyNodesAllowed: tree not ready', false);
                return false;
            }
            const sourceNodes = this.tree.findStateFlagNodes();
            if (sourceNodes.length === 0) {
                // console.log('isCopyNodesAllowed: no sourceNodes selected', false);
                return false;
            }
            const destinationNode = this.custom_tree.selectedNode();
            if (!destinationNode) {
                // console.log('isCopyNodesAllowed: no destinationNode selected', false);
                return false;
            }
            for (const sourceNode of sourceNodes) {
                if (this.custom_tree.findNodesByFieldAndValue('label', sourceNode.label).length > 0) {
                    // console.log('isCopyNodesAllowed: selected SourceNode already in custom_tree', false);
                    return false;
                }
                if (sourceNode === this.tree.rootNode) {
                    // console.log('isCopyNodesAllowed: rootNode is sacrosanct', false);
                    return false;
                }
            }
            // console.log('isCopyNodesAllowed', true);
            return true;
        } catch(E) {
            console.log('isCopyNodesAllowed, error', E);
            return false;
        }
    }

    copyNodes() {
        // console.log('copyNodes');
        const sourceNodes = this.tree.findStateFlagNodes();
        const targetNode = this.custom_tree.selectedNode();
        if (!this.isCopyNodesAllowed()) {
            return;
        }
        this._copyNodes(sourceNodes, targetNode, false);
    }

    _copyNodes(sourceNodes: TreeNode[], targetNode: TreeNode, cloneChildren = true) {
        // console.log('_copyNodes', { sourceNodes: sourceNodes, targetNode: targetNode });
        const traverseTreeAndCopySourceNodes = (currentNode: TreeNode, targetNode: TreeNode) => {
            // console.log('traverseTreeAndCopySourceNodes', currentNode.label);
            if (sourceNodes.map(n => n.label).includes(currentNode.label)) {
                // console.log('found a source node, copying',currentNode.label);
                const newNode = currentNode.clone();
                if (!cloneChildren) {
                    newNode.children = [];
                }
                targetNode.children.push(newNode);
                targetNode = newNode;
            }

            for (const childNode of currentNode.children) {
                traverseTreeAndCopySourceNodes(childNode, targetNode);
            }
        };

        traverseTreeAndCopySourceNodes(this.tree.rootNode, targetNode);
        this.custom_tree.nodeList(); // re-index
    }

    isDeleteNodesAllowed(): boolean {
        try {
            if (!this.custom_tree) {
                console.debug('isDeleteNodesAllowed: custom_tree not ready');
                return false;
            }
            const targetNodes = this.custom_tree.findStateFlagNodes();
            if (targetNodes.length === 0) {
                console.debug('isDeleteNodesAllowed: no targetNodes selected');
                return false;
            }
            for (const targetNode of targetNodes) {
                if (targetNode === this.custom_tree.rootNode) {
                    console.debug('isDeleteNodesAllowed: rootNode is sacrosanct');
                    return false;
                }
            }
            // console.log('isDeleteNodesAllowed', true);
            return true;
        } catch(E) {
            console.log('isDeleteNodesAllowed, error', E);
            return false;
        }
    }

    isDeleteSelectedNodeAllowed(): boolean {
        if (this.custom_tree.selectedNode()) {
            if (this.custom_tree.selectedNode() === this.custom_tree.rootNode) {
                return false;
            }
            return true;
        }
        return false;
    }

    deleteNodes(targetNodes: TreeNode[], justOne?: boolean) {
        if (justOne) {
            if (! this.isDeleteSelectedNodeAllowed()) {
                return;
            }
        } else if (! this.isDeleteNodesAllowed()) {
            return;
        }
        if (! window.confirm($localize`Are you sure?`)) {
            return;
        }

        // Sort nodes by depth in descending order
        targetNodes.sort((a, b) => b.depth - a.depth);

        for (const targetNode of targetNodes) {
            if (targetNode !== this.custom_tree.rootNode) {
                // console.log('removing node',targetNode);
                this.custom_tree.removeNode(targetNode);
            }
        }
        this.custom_tree.nodeList(); // re-index
    }

    deleteNode(node: TreeNode) {
        this.deleteNodes([node], true);
    }

    deleteSelectedNodes() {
        this.deleteNodes(this.custom_tree.findStateFlagNodes());
    }

    isMoveNodeUpAllowed(node: TreeNode): boolean {
        const parentNode = this.custom_tree.findParentNode(node);
        if (parentNode) {
            const index = parentNode.children.indexOf(node);
            if (index === 0) {
                return false;
            }
        }
        return true;
    }

    moveNodeUp(node: TreeNode) {
        const selectedNode = node || this.custom_tree.selectedNode();
        if (!this.isMoveNodeUpAllowed(node)) {
            return;
        }
        const parentNode = this.custom_tree.findParentNode(selectedNode);
        if (parentNode) {
            const index = parentNode.children.indexOf(selectedNode);
            if (index > 0) {
                // Swap the selected node with its previous sibling.
                const temp = parentNode.children[index - 1];
                parentNode.children[index - 1] = selectedNode;
                parentNode.children[index] = temp;
                this.custom_tree.nodeList(); // re-index
            }
        }
    }

    isMoveNodeDownAllowed(node: TreeNode): boolean {
        const parentNode = this.custom_tree.findParentNode(node);
        if (parentNode) {
            const index = parentNode.children.indexOf(node);
            if (index < parentNode.children.length - 1) {
                // great
            } else {
                return false;
            }
        }
        return true;
    }

    moveNodeDown(node: TreeNode) {
        if (!this.isMoveNodeDownAllowed(node)) {
            return;
        }
        const parentNode = this.custom_tree.findParentNode(node);
        if (parentNode) {
            const index = parentNode.children.indexOf(node);
            if (index < parentNode.children.length - 1) {
                // Swap the selected node with its next sibling.
                const temp = parentNode.children[index + 1];
                parentNode.children[index + 1] = node;
                parentNode.children[index] = temp;
                this.custom_tree.nodeList(); // re-index
            }
        }
    }

    isMoveNodeElsewhereAllowed(node: TreeNode): boolean {
        return node !== this.custom_tree.rootNode;
    }

    moveNodeElsewhere() {
        const nodeToMove = this.custom_tree.selectedNode();
        const selectionTree = this.custom_tree.clone({
            stateFlag: false,
            stateFlagLabel: null,
            selected:false
        });

        // prune nodeToMove and descendants from destination selection tree
        const equivalentNode = selectionTree.findNodesByFieldAndValue(
            'label',nodeToMove.label)[0];
        selectionTree.removeNode(equivalentNode);

        this.moveNodeElsewhereDialog.customTree = selectionTree;
        this.moveNodeElsewhereDialog.nodeToMove = nodeToMove;


        this.moveNodeElsewhereDialog.open({size: 'lg'}).subscribe(
            result => {
                // console.log('modal result',result);
                if (result) {
                    try {
                        // Find the equivalent node in custom_tree
                        const targetNodeInCustomTree = this.custom_tree.findNodesByFieldAndValue(
                            'label',result.label)[0];

                        // Prevent a node from becoming its own parent.
                        if (nodeToMove === targetNodeInCustomTree
                            || this.custom_tree.findParentNode(targetNodeInCustomTree) === nodeToMove) {
                            return;
                        }

                        // Remove the selected node from its current parent's children.
                        // this.custom_tree.removeNode(nodeToMove);

                        // Add the selected node as the last child of the target node in custom_tree.
                        if (targetNodeInCustomTree) {
                            this.custom_tree.removeNode(nodeToMove);
                            // this._copyNodes([nodeToMove], targetNodeInCustomTree);
                            targetNodeInCustomTree.children.push( nodeToMove );
                        }

                        // re-index
                        this.custom_tree.nodeList();

                    } catch(E) {
                        console.error('moveNodeHere',E);
                    }
                }
            }
        );
    }

    async applyChanges() {
        // console.log('applyChanges');
        if (this.active !== (this.tree_type.active() === 't')) {
            this.tree_type.active(this.active ? 't' : 'f');
            this.tree_type.ischanged('t');
        }
        try {
            if (this.tree_type.isnew()) {
                this.tree_type = await firstValueFrom(this.pcrud.create(this.tree_type));
            } else if (this.tree_type.ischanged()) {
                await firstValueFrom(this.pcrud.update(this.tree_type));
            }
            await this.createNewAouctns(this.custom_tree.rootNode);
            this.successString.current().then(str => this.toast.success(str));

        } catch (error) {
            console.error('Error applying changes:', error);
            this.updateFailedString.current().then(str => this.toast.danger(str));
        }
    }

    async createNewAouctns(node: TreeNode, parent_id: number = null, order = 0) {
        // console.log('createNewAouctns for ' + node.label + ' with parent_id = ' + parent_id + ' and order = ' + order, node);
        // delete the existing custom nodes for the custom tree
        // TODO: this is what the dojo interface did, but do we really need so much churn?
        // TODO: we may want to move this to an OpenSRF method so we can wrap the entire
        //       delete and create into a single transaction
        if (this.aouctn_root) {
            if (this.org.get(this.aouctn_root.org_unit()).id() === node.callerData.orgId) {
                // console.warn('removing aouctn for org ' + this.org.get(node.callerData.orgId).shortname(), this.aouctn_root);
                const result = await lastValueFrom(this.pcrud.remove(this.aouctn_root));
                // console.log('remove returned', result);
                // console.log('this should have cascaded and deleted all descendants');
                // console.log('setting aouctn_root to null');
                this.aouctn_root = null;
            }
        }
        let newNode = this.idl.create('aouctn');
        newNode.isnew('t');
        newNode.parent_node(parent_id);
        newNode.sibling_order(order);
        newNode.org_unit(node.callerData.orgId);
        newNode.tree(this.tree_type.id());
        // console.warn('creating aouctn for org ' + this.org.get(node.callerData.orgId).shortname(), newNode);

        // Send the new node to the server and get back the updated node
        newNode = await firstValueFrom(this.pcrud.create(newNode));
        // console.log('pcrud.create returned', newNode);
        if (!this.aouctn_root) {
            // console.log('setting it to aouctn_root; parent_node =', newNode.parent_node())
            this.aouctn_root = newNode;
        }

        // If the original TreeNode has children, create new aouctn's for each child
        if (node.children && node.children.length > 0) {
            // console.log('looping through children for ' + this.org.get(newNode.org_unit()).shortname());
            for (let i = 0; i < node.children.length; i++) {
                await this.createNewAouctns(node.children[i], newNode.id(), i);
            }
            // console.log('finished with children for ' + this.org.get(newNode.org_unit()).shortname());
        }

        // console.warn('final version of node', newNode);
        return newNode;
    }

}

