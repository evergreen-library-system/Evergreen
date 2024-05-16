import {Component, ViewChild, OnInit} from '@angular/core';
import {map} from 'rxjs/operators';
import {of, firstValueFrom} from 'rxjs';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {FmRecordEditorComponent, FmFieldOptions} from '@eg/share/fm-editor/fm-editor.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {PermGroupMapDialogComponent} from './perm-group-map-dialog.component';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';

/** Manage permission groups and group permissions */

@Component({
    templateUrl: './perm-group-tree.component.html'
})

export class PermGroupTreeComponent implements OnInit {

    tree: Tree;
    selected: TreeNode;
    allFactorMaps: IdlObject[];
    permissions: IdlObject[];
    permIdMap: {[id: number]: IdlObject};
    permEntries: ComboboxEntry[];
    permMaps: IdlObject[];
    orgDepths: number[];
    filterText: string;
    mfa_factors: string[];
    mfa_factor_details: any;
    mfa_enabled = false;

    // Have to fetch quite a bit of data for this UI.
    loading: boolean;
    permTab: string;

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
        private net: NetService,
        private toast: ToastService
    ) {
        this.allFactorMaps = [];
        this.mfa_factors = [];
        this.mfa_factor_details = { factors: {}, flags: {} };
        this.permissions = [];
        this.permEntries = [];
        this.permMaps = [];
        this.permIdMap = {};
    }

    async toggleFactorForSelected($event, factor) {
        if ($event) { // creating mapping
            try {
                const newmap = this.idl.create('pgmfm');
                newmap.isnew(true);
                newmap.factor(factor.name());
                newmap.grp(this.selected.callerData.id());
                const done = await firstValueFrom(this.pcrud.create(newmap));
                this.successString.current().then(str => this.toast.success(str));
            } catch (error) {
                console.error('Error creating factor mapping:', error);
                this.errorString.current().then(str => this.toast.danger(str));
            }
        } else { // removing a mapping
            try {
                const oldmap = this.allFactorMaps
                    .find(m => Number(m.grp()) === Number(this.selected.callerData.id()) && m.factor() === factor.name());
                oldmap.isdeleted(true);
                const done = await firstValueFrom(this.pcrud.remove(oldmap));
                this.successString.current().then(str => this.toast.success(str));
            } catch (error) {
                console.error('Error creating factor mapping:', error);
                this.errorString.current().then(str => this.toast.danger(str));
            }
        }
        await this.loadFactorMaps();
    }

    selectedAncestorIds() {
        const anc = [];
        let n = this.selected.callerData;
        do {
            anc.push(n.id());
            if (n.parent()) {
                n = this.tree.findNode(n.parent()).callerData;
            } else {
                n = null;
            }
        } while (n);
        return anc;
    }

    factorAssignedAt(factor): IdlObject {
        const closest = this.selectedAncestorIds()
            .find(grpid => this.allFactorMaps.find(m => Number(m.grp()) === Number(grpid) && m.factor() === factor.name()));
        if (!closest) { return null; }
        return this.tree.findNode(closest).callerData;
    }

    allAvailableFactors() {
        return Object.values(this.mfa_factor_details.factors)
            .sort((f1:IdlObject,f2:IdlObject) => f1.label() < f2.label() ? -1 : 1);
    }

    async ngOnInit() {
        this.loading = true;
        await this.checkMFA();
        this.loadProgress.increment();
        await this.loadFactorList();
        this.loadProgress.increment();
        await this.loadFactorObjects();
        this.loadProgress.increment();
        await this.loadFactorMaps();
        this.loadProgress.increment();
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

    onNavChange(evt: NgbNavChangeEvent) {
        this.permTab = evt.nextId;
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

    // Returns maps for this group and ancestors
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

    async checkMFA(): Promise<any> {
        return this.net.request(
            'open-ils.auth_mfa', 'open-ils.auth_mfa.enabled'
        ).toPromise().then(res => this.mfa_enabled = !!Number(res));
    }

    async loadFactorList(): Promise<any> {
        if (!this.mfa_enabled) { return of(true).toPromise(); }
        return this.net.request(
            'open-ils.auth_mfa', 'open-ils.auth_mfa.enabled_factors'
        ).toPromise().then(res => this.mfa_factors = res);
    }

    async loadFactorObjects(): Promise<any> {
        if (this.mfa_factors.length === 0) { return of(true).toPromise(); }

        return this.net.request(
            'open-ils.auth_mfa', 'open-ils.auth_mfa.factor_details', this.mfa_factors
        ).toPromise().then(res => this.mfa_factor_details = res);
    }

    async loadPgtTree(): Promise<any> {

        return this.pcrud.search('pgt', {parent: null},
            {flesh: -1, flesh_fields: {pgt: ['children']}}
        ).pipe(map(pgtTree => this.ingestPgtTree(pgtTree))).toPromise();
    }

    async loadFactorMaps(): Promise<any> {
        this.allFactorMaps = [];
        return this.pcrud.retrieveAll('pgmfm')
            .pipe(map(f => {
                this.loadProgress?.increment();
                this.allFactorMaps.push(f);
            })).toPromise();
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

    // True if the provided mapping applies to the selected group
    // and a mapping for the same permission exists for an ancestor.
    permOverrides(m: IdlObject): boolean {
        const grpId = this.selected.callerData.id();

        if (m.grp().id() === grpId) { // Selected group has the perm.

            // See if at least one of our ancestors also has the perm.
            return this.groupPermMaps().filter(mp => {
                return (
                    mp.perm().id() === m.perm().id() &&
                    mp.grp().id() !== grpId
                );
            }).length > 0;
        }

        return false;
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
            (failed: unknown) => {
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
                    // eslint-disable-next-line rxjs/no-nested-subscribe
                    .subscribe(
                        ok2 => {},
                        (err: unknown) => {
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
            (failed: unknown) => {
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
            (err: unknown) => {
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
        this.addMappingDialog.open({size: 'lg'}).subscribe(
            modified => {
                if (modified) {
                    this.createMapString.current().then(msg => this.toast.success(msg));
                    this.loadPermMaps();
                } else {
                    this.errorMapString.current().then(msg => this.toast.danger(msg));
                }
            }
        );
    }

    selectGroup(id: number) {
        const node: TreeNode = this.tree.findNode(id);
        this.tree.selectNode(node);
        this.nodeClicked(node);
    }
}

