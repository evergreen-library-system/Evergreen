import { Injectable } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { Tree, TreeNode } from './tree';
import { PcrudService } from '@eg/core/pcrud.service';
import { firstValueFrom, lastValueFrom, toArray } from 'rxjs';
import { GlobalFlagService } from '@eg/core/global-flag.service';

const SHELVING_LOCATION_GROUPS_INCLUDED_BY_DEFAULT = true;

// This class is responsible for enhancing data
// it gets from the org service so that it is
// suitable for use in the Catalog Org Selector
@Injectable({
    providedIn: 'root'
})
export class EnhancedOrgTree {
    constructor(private org: OrgService, private pcrud: PcrudService, private globalFlag: GlobalFlagService) {
        this.org.absorbTree();
    }

    orgTreeObject = new Tree();
    locationGroups: IdlObject[];
    shouldAddLocationGroups = SHELVING_LOCATION_GROUPS_INCLUDED_BY_DEFAULT;

    async toTreeObject(labelGenerator?: (nodeToLabel: IdlObject) => string): Promise<Tree> {
        this.shouldAddLocationGroups = await firstValueFrom(
            this.globalFlag.enabled('staff.search.shelving_location_groups_with_orgs',
                SHELVING_LOCATION_GROUPS_INCLUDED_BY_DEFAULT)
        );

        // If we have already created a tree object, no need to recreate it
        if (this.orgTreeObject.nodeList(false, true).length === 0) {
            // If no labelGenerator arrow function provided, default
            // to using the shortname as the label
            labelGenerator ||= (node) => node.shortname();
            this.orgTreeObject = new Tree(new TreeNode({
                id: this.org.root().id(),
                label: labelGenerator(this.org.root()),
                callerData: this.org.root()
            }));
            const children = this.org.root().children();
            children.sort((a: IdlObject, b: IdlObject) => labelGenerator(a).localeCompare(labelGenerator(b)));
            children.forEach((child: IdlObject) => this.addTreeNodeToParent(child, labelGenerator));
            this.addShelvingLocationGroupsToTree();
        }
        return Promise.resolve(this.orgTreeObject);
    }

    private async addShelvingLocationGroupsToTree() {
        this.locationGroups = await lastValueFrom(this.pcrud.search('acplg', {opac_visible: 't'}).pipe(toArray()));
        this.addShelvingLocationGroupsToNode(this.orgTreeObject.rootNode);
    }

    private addShelvingLocationGroupsToNode(node: TreeNode) {
        if (!this.shouldAddLocationGroups) {
            return;
        }

        // A node could be an org unit or a shelving location group,
        // but only an org unit can have a child shelving location group
        if (node.callerData.classname !== 'aou') {
            return;
        }

        // Shelving locations can display either above the
        // child orgs, or below them
        const aboveGroups = this.locationGroups.filter((group) => {
            return (group.owner() === node.id && group.top() === 't');
        });
        aboveGroups.sort((a, b) => b.pos() - a.pos());
        aboveGroups.forEach(group => {
            node.children.unshift(new TreeNode({
                id: group.id(),
                label: group.name(),
                callerData: group,
                depth: node.depth + 1
            }));
        });

        const belowGroups = this.locationGroups.filter((group) => {
            return (group.owner() === node.id && group.top() === 'f');
        });
        belowGroups.sort((a, b) => a.pos() - b.pos());
        belowGroups.forEach(group => {
            node.addChild(new TreeNode({
                id: group.id(),
                label: group.name(),
                callerData: group
            }));
        });

        node.children.forEach(child => this.addShelvingLocationGroupsToNode(child));
    }

    private addTreeNodeToParent(node: IdlObject, labelGenerator: (nodeToLabel: IdlObject) => string) {
        if (this.nodeIsStaffCatVisible(node)) {
            this.orgTreeObject.findNode(this.closestStaffVisibleAncestorId(node)).addChild(
                new TreeNode({
                    id: node.id(),
                    label: labelGenerator(node),
                    callerData: node
                })
            );
        }
        const children = node.children();
        children.sort((a: IdlObject, b: IdlObject) => labelGenerator(a).localeCompare(labelGenerator(b)));
        children.forEach((child: IdlObject) => this.addTreeNodeToParent(child, labelGenerator));
    }

    private closestStaffVisibleAncestorId(org: IdlObject): number {
        const parentId = org.parent_ou();
        if(!parentId) {
            return this.org.root().id();
        }
        const parent = this.org.get(parentId);
        if(this.nodeIsStaffCatVisible(parent)) {
            return parent.id();
        }
        return this.closestStaffVisibleAncestorId(parent);
    }

    private nodeIsStaffCatVisible(node: IdlObject): boolean {
        // If the staff_catalog_visible method is not defined, there
        // is probably something wrong with the IDL, so assume visible
        // for minimal disruption
        if (!node.staff_catalog_visible ) {
            return true;
        }
        return node.staff_catalog_visible() !== 'f';
    }
}
