import {Component, ViewChild, OnInit} from '@angular/core';
import {map} from 'rxjs/operators';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {FmRecordEditorComponent, FmFieldOptions} from '@eg/share/fm-editor/fm-editor.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {PermGroupMapDialogComponent} from './perm-group-map-dialog.component';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';

/** Manage permission groups and group permissions */

@Component({
    templateUrl: './perm-group-tree.component.html'
})

export class PermGroupTreeComponent implements OnInit {

    tree: Tree;
    selected: TreeNode;
    permissions: IdlObject[];
    permIdMap: {[id: number]: IdlObject};
    permEntries: ComboboxEntry[];
    permMaps: IdlObject[];
    orgDepths: number[];
    filterText: string;

    // Have to fetch quite a bit of data for this UI.
    loading: boolean;

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('delConfirm', { static: true }) delConfirm: ConfirmDialogComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: true }) createString: StringComponent;
    @ViewChild('errorString', { static: true }) errorString: StringComponent;
    @ViewChild('successMapString', { static: true }) successMapString: StringComponent;
    @ViewChild('createMapString', { static: true }) createMapString: StringComponent;
    @ViewChild('errorMapString', { static: true }) errorMapString: StringComponent;
    @ViewChild('addMappingDialog', { static: true }) addMappingDialog: PermGroupMapDialogComponent;
    @ViewChild('loadProgress', { static: false }) loadProgress: ProgressInlineComponent;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private toast: ToastService
    ) {
        this.permissions = [];
        this.permEntries = [];
        this.permMaps = [];
        this.permIdMap = {};
    }


    async ngOnInit() {
        this.loading = true;
        await this.loadPgtTree();
        this.loadProgress.increment();
        await this.loadPermissions();
        this.loadProgress.increment();
        await this.loadPermMaps();
        this.loadProgress.increment();
        this.setOrgDepths();
        this.loadProgress.increment();
        this.loading = false;
        return Promise.resolve();
    }

    setOrgDepths() {
        const depths = this.org.typeList().map(t => Number(t.depth()));
        const depths2 = [];
        depths.forEach(d => {
            if (!depths2.includes(d)) {
                depths2.push(d);
            }
        });
        this.orgDepths = depths2.sort();
    }

    groupPermMaps(): IdlObject[] {
        if (!this.selected) { return []; }

        let maps = this.inheritedPermissions();
        maps = maps.concat(
            this.permMaps.filter(m => +m.grp().id() === +this.selected.id));

        maps = this.applyFilter(maps);

        return maps.sort((m1, m2) =>
            m1.perm().code() < m2.perm().code() ? -1 : 1);
    }

    // Chop the filter text into separate words and return true if all
    // of the words appear somewhere in the combined permission code
    // plus description text.
    applyFilter(maps: IdlObject[]) {
        if (!this.filterText) { return maps; }
        const parts = this.filterText.toLowerCase().split(' ');

        maps = maps.filter(m => {
            const desc = m.perm().description() || ''; // null-able

            const target =
                m.perm().code().toLowerCase() + ' ' + desc.toLowerCase();

            for (let i = 0; i < parts.length; i++) {
                const part = parts[i];
                if (part && target.indexOf(part) === -1) {
                    return false;
                }
            }

            return true;
        });

        return maps;
    }

    async loadPgtTree(): Promise<any> {

        return this.pcrud.search('pgt', {parent: null},
            {flesh: -1, flesh_fields: {pgt: ['children']}}
        ).pipe(map(pgtTree => this.ingestPgtTree(pgtTree))).toPromise();
    }

    async loadPermissions(): Promise<any> {
        // ComboboxEntry's for perms uses code() for id instead of
        // the database ID, because the application_perm field on
        // "pgt" is text instead of a link.  So the value it expects
        // is the code, not the ID.
        return this.pcrud.retrieveAll('ppl', {order_by: {ppl: 'code'}})
        .pipe(map(perm => {
            this.loadProgress.increment();
            this.permissions.push(perm);
            this.permEntries.push({id: perm.code(), label: perm.code()});
            this.permissions.forEach(p => this.permIdMap[+p.id()] = p);
        })).toPromise();
    }

    async loadPermMaps(): Promise<any> {
        this.permMaps = [];
        return this.pcrud.retrieveAll('pgpm', {},
            {fleshSelectors: true, authoritative: true})
        .pipe(map(m => {
            if (this.loadProgress) {
                this.loadProgress.increment();
            }
            this.permMaps.push(m);
        })).toPromise();
    }

    fmEditorOptions(): {[fieldName: string]: FmFieldOptions} {
        return {
            application_perm: {
                customValues: this.permEntries
            }
        };
    }

    // Translate the org unt type tree into a structure EgTree can use.
    ingestPgtTree(pgtTree: IdlObject) {

        const handleNode = (pgtNode: IdlObject): TreeNode => {
            if (!pgtNode) { return; }

            const treeNode = new TreeNode({
                id: pgtNode.id(),
                label: pgtNode.name(),
                callerData: pgtNode
            });

            pgtNode.children()
                .sort((c1, c2) => c1.name() < c2.name() ? -1 : 1)
                .forEach(childNode =>
                treeNode.children.push(handleNode(childNode))
            );

            return treeNode;
        };

        const rootNode = handleNode(pgtTree);
        this.tree = new Tree(rootNode);
    }

    groupById(id: number): IdlObject {
        return this.tree.findNode(id).callerData;
    }

    permById(id: number): IdlObject {
        return this.permIdMap[id];
    }

    // Returns true if the perm map belongs to an ancestore of the
    // currently selected group.
    permIsInherited(m: IdlObject): boolean {
        // We know the provided map came from this.groupPermMaps() which
        // only returns maps for the selected group plus parent groups.
        return m.grp().id() !== this.selected.callerData.id();
    }

    // List of perm maps that owned by perm groups which are ancestors
    // of the selected group
    inheritedPermissions(): IdlObject[] {
        let maps: IdlObject[] = [];

        let treeNode = this.tree.findNode(this.selected.callerData.parent());
        while (treeNode) {
            maps = maps.concat(
                this.permMaps.filter(m => +m.grp().id() === +treeNode.id));
            treeNode = this.tree.findNode(treeNode.callerData.parent());
        }

        return maps;
    }


    nodeClicked($event: any) {
        this.selected = $event;

        // When the user selects a different perm tree node,
        // reset the edit state for our perm maps.

        this.permMaps.forEach(m => {
            m.isnew(false);
            m.ischanged(false);
            m.isdeleted(false);
        });
    }

    edit() {
        this.editDialog.mode = 'update';
        this.editDialog.setRecord(this.selected.callerData);

        this.editDialog.open({size: 'lg'}).subscribe(
            success => {
                this.successString.current().then(str => this.toast.success(str));
            },
            failed => {
                this.errorString.current()
                    .then(str => this.toast.danger(str));
            }
        );
    }

    remove() {
        this.delConfirm.open().subscribe(
            confirmed => {
                if (!confirmed) { return; }

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
                        this.successString.current().then(str => this.toast.success(str));
                    }
                );
            }
        );
    }

    addChild() {
        const parentTreeNode = this.selected;
        const parentType = parentTreeNode.callerData;

        const newType = this.idl.create('pgt');
        newType.parent(parentType.id());

        this.editDialog.setRecord(newType);
        this.editDialog.mode = 'create';

        this.editDialog.open({size: 'lg'}).subscribe(
            result => { // pgt object

                // Add our new node to the tree
                const newNode = new TreeNode({
                    id: result.id(),
                    label: result.name(),
                    callerData: result
                });
                parentTreeNode.children.push(newNode);
                this.createString.current().then(str => this.toast.success(str));
            },
            failed => {
                this.errorString.current()
                    .then(str => this.toast.danger(str));
            }
        );
    }

    changesPending(): boolean {
        return this.modifiedMaps().length > 0;
    }

    modifiedMaps(): IdlObject[] {
        return this.permMaps.filter(
            m => m.isnew() || m.ischanged() || m.isdeleted()
        );
    }

    applyChanges() {

        const maps: IdlObject[] = this.modifiedMaps()
            .map(m => this.idl.clone(m)); // Clone for de-fleshing

        maps.forEach(m => {
            m.grp(m.grp().id());
            m.perm(m.perm().id());
        });

        this.pcrud.autoApply(maps).subscribe(
            one => console.debug('Modified one mapping: ', one),
            err => {
                console.error(err);
                this.errorMapString.current().then(msg => this.toast.danger(msg));
            },
            ()  => {
                this.successMapString.current().then(msg => this.toast.success(msg));
                this.loadPermMaps();
            }
        );
    }

    openAddDialog() {
        this.addMappingDialog.open().subscribe(
            modified => {
                this.createMapString.current().then(msg => this.toast.success(msg));
                this.loadPermMaps();
            }
        );
    }

    selectGroup(id: number) {
        const node: TreeNode = this.tree.findNode(id);
        this.tree.selectNode(node);
        this.nodeClicked(node);
    }
}

