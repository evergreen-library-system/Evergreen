import { Component, EventEmitter, Input, OnInit, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TreeComboboxComponent } from '@eg/share/tree-combobox/tree-combobox.component';
import { Tree, TreeNode } from '@eg/share/tree/tree';
import { EnhancedOrgTree } from '@eg/share/tree/enhanced-org-tree';
import { IdlObject } from '@eg/core/idl.service';
import { ServerStoreService } from '@eg/core/server-store.service';

@Component({
    selector: 'eg-catalog-org-select',
    standalone: true,
    imports: [CommonModule, TreeComboboxComponent],
    templateUrl: './catalog-org-select.component.html'
})
export class CatalogOrgSelectComponent implements OnInit {
    @Input() initialOrg: IdlObject;
    @Output() orgChanged$ = new EventEmitter<IdlObject>();
    tree = new Tree();

    constructor(private enhancedOrgTree: EnhancedOrgTree, private serverStore: ServerStoreService) {}

    ngOnInit() {
        this.initializeTree();
    }

    get initialOrgNode(): TreeNode {
        if (this.treeIsReady() && this.initialOrg?.id()) {
            return this.findOrgInTree(this.initialOrg.id());
        }
        return null;
    }

    emitOrgChanged(node: TreeNode) {
        this.orgChanged$.emit(node.callerData);
    }

    async initializeTree() {
        const shouldCombineNames = await this.serverStore.getItem('eg.orgselect.show_combined_names');
        if (shouldCombineNames) {
            this.tree = await this.enhancedOrgTree.toTreeObject((node) => `${node.name()} (${node.shortname()})`);
        } else {
            this.tree = await this.enhancedOrgTree.toTreeObject();
        }
    }

    private treeIsReady() {
        return (this.tree.nodeList(false, true).length > 0);
    }

    private findOrgInTree(id: number) {
        return this.tree.nodeList(false, true).find((node: TreeNode) => {
            return ((node.id === id) && node.callerData?.classname === 'aou');
        });
    }
}
