/* eslint-disable eqeqeq, max-len, no-magic-numbers */
import {Component, ViewChild, OnInit} from '@angular/core';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {PermService} from '@eg/core/perm.service';

@Component({
    templateUrl: './org-unit.component.html',
    styleUrls: [ './org-unit.component.css' ],
})
export class OrgUnitComponent implements OnInit {

    tree: Tree;
    selected: TreeNode;
    orgUnitTab: string;

    hasClosedDatePerms: boolean;

    @ViewChild('editString', { static: true }) editString: StringComponent;
    @ViewChild('errorString', { static: true }) errorString: StringComponent;
    @ViewChild('delConfirm', { static: true }) delConfirm: ConfirmDialogComponent;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private strings: StringService,
        private toast: ToastService,
        private perm: PermService,
    ) {}


    ngOnInit() {
        this.loadAouTree(this.org.root().id());

        // Check once on init if user could be linked to closed date editor (don't want them to land on a page that does nothing and think it's broken)
        const neededClosedDatesPerms = ['actor.org_unit.closed_date.create',
            'actor.org_unit.closed_date.update',
            'actor.org_unit.closed_date.delete'];

        this.perm.hasWorkPermAt(neededClosedDatesPerms, true).then((perm) => {
            // Set true once if they have every permission they need to change closed dates
            this.hasClosedDatePerms = neededClosedDatesPerms.every(element => {
                return perm[element].length > 0;
            });
        });

    }

    navChanged(evt: NgbNavChangeEvent) {
        const tab = evt.nextId;
        // stubbing out in case we need it.
    }

    orgSaved(orgId: number | IdlObject) {
        let id;

        if (orgId) { // new org created, focus it.
            id = typeof orgId === 'object' ? orgId.id() : orgId;
        } else if (this.currentOrg()) {
            id = this.currentOrg().id();
        }

        this.loadAouTree(id).then(_ => this.postUpdate(this.editString));
    }

    orgDeleted() {
        this.loadAouTree();
    }

    loadAouTree(selectNodeId?: number): Promise<any> {

        const flesh = ['children', 'ou_type', 'hours_of_operation'];

        return this.pcrud.search('aou', {parent_ou : null},
            {flesh : -1, flesh_fields : {aou : flesh}}, {authoritative: true}

        ).toPromise().then(tree => {
            this.ingestAouTree(tree);
            if (!selectNodeId) { selectNodeId = this.org.root().id(); }

            const node = this.tree.findNode(selectNodeId);
            this.selected = node;
            this.tree.selectNode(node);
        });
    }

    // Translate the org unt type tree into a structure EgTree can use.
    ingestAouTree(aouTree) {

        const handleNode = (orgNode: IdlObject, expand?: boolean): TreeNode => {
            if (!orgNode) { return; }

            if (!orgNode.hours_of_operation()) {
                this.generateHours(orgNode);
            }

            const treeNode = new TreeNode({
                id: orgNode.id(),
                label: orgNode.name(),
                callerData: {orgUnit: orgNode},
                expanded: expand
            });

            // Apply the compiled label asynchronously
            this.strings.interpolate(
                'admin.server.org_unit.treenode', {org: orgNode}
            ).then(label => treeNode.label = label);

            // Tree node labels are "name -- shortname".  Sorting
            // by name suffices and bypasses the need the wait
            // for all of the labels to interpolate.
            orgNode.children()
                .sort((a, b) => a.name() < b.name() ? -1 : 1)
                .forEach(childNode =>
                    treeNode.children.push(handleNode(childNode))
                );

            return treeNode;
        };

        const rootNode = handleNode(aouTree, true);
        this.tree = new Tree(rootNode);
    }

    nodeClicked($event: any) {
        this.selected = $event;
    }

    generateHours(org: IdlObject) {
        const hours = this.idl.create('aouhoo');
        hours.id(org.id());
        hours.isnew(true);

        [0, 1, 2, 3, 4, 5, 6].forEach(dow => {
            this.hours(dow, 'open', '09:00:00', hours);
            this.hours(dow, 'close', '17:00:00', hours);
        });

        org.hours_of_operation(hours);
    }

    // if a 'value' is passed, it will be applied to the optional
    // hours-of-operation object, otherwise the hours on the currently
    // selected org unit.
    hours(dow: number, which: 'open' | 'close' | 'note', value?: string, hoo?: IdlObject): string {
        if (!hoo && !this.selected) { return null; }

        const hours = hoo || this.selected.callerData.orgUnit.hours_of_operation();

        if (value) {
            hours[`dow_${dow}_${which}`](value);
            hours.ischanged(true);
        }

        return hours[`dow_${dow}_${which}`]();
    }

    isClosed(dow: number): boolean {
        return (
            this.hours(dow, 'open') === '00:00:00' &&
            this.hours(dow, 'close') === '00:00:00'
        );
    }

    // Is the org closed every day of the week?
    allClosed(): boolean{
        return [0, 1, 2, 3, 4, 5, 6].every(dow => this.isClosed(dow));
    }

    getNote(dow: number, hoo?: IdlObject) {
        if (!hoo && !this.selected) { return null; }

        const hours = hoo || this.selected.callerData.orgUnit.hours_of_operation();

        return hours['dow_' + dow + '_note']();
    }

    setNote(dow: number, value?: string, hoo?: IdlObject) {
        console.log(value);
        if (!hoo && !this.selected) { return null; }

        const hours = hoo || this.selected.callerData.orgUnit.hours_of_operation();

        hours['dow_' + dow + '_note'](value);
        hours.ischanged(true);

        return hours['dow_' + dow + '_note']();
    }

    note(dow: number, which: 'note', value?: string, hoo?: IdlObject) {
        if (!hoo && !this.selected) { return null; }

        const hours = hoo || this.selected.callerData.orgUnit.hours_of_operation();
        if (!value) {
            hours[`dow_${dow}_${which}`]('');
            hours.ischanged(true);
        } else if (value != hours[`dow_${dow}_${which}`]()) {
            hours[`dow_${dow}_${which}`](value);
            hours.ischanged(true);
        }
        return hours[`dow_${dow}_${which}`]();
    }

    closedOn(dow: number) {
        this.hours(dow, 'open', '00:00:00');
        this.hours(dow, 'close', '00:00:00');
    }

    saveHours() {
        const org = this.currentOrg();
        const hours = org.hours_of_operation();
        this.pcrud.autoApply(hours).subscribe(
            { next: result => {
                console.debug('Hours saved ', result);
                this.editString.current()
                    .then(msg => this.toast.success(msg));
            }, error: (error: unknown) => {
                this.errorString.current()
                    .then(msg => this.toast.danger(msg));
            }, complete: () => this.loadAouTree(this.selected.id) }
        );
    }

    deleteHours() {
        const hours = this.currentOrg().hours_of_operation();
        const promise = hours.isnew() ? Promise.resolve() :
            this.pcrud.remove(hours).toPromise();

        promise.then(_ => this.generateHours(this.currentOrg()));
    }

    currentOrg(): IdlObject {
        return this.selected ? this.selected.callerData.orgUnit : null;
    }

    orgHasChildren(): boolean {
        const org = this.currentOrg();
        return (org && org.children().length > 0);
    }

    postUpdate(message: StringComponent) {
        // Modifying org unit types means refetching the org unit
        // data normally fetched on page load, since it includes
        // org unit type data.
        this.org.fetchOrgs().then(() =>
            message.current().then(str => this.toast.success(str)));
    }

    remove() {
        this.delConfirm.open().subscribe(confirmed => {
            if (!confirmed) { return; }

            const org = this.selected.callerData.orgUnit;

            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            this.pcrud.remove(org).subscribe(
                { next: ok2 => {}, error: (err: unknown) => {
                    this.errorString.current()
                        .then(str => this.toast.danger(str));
                }, complete: ()  => {
                    // Avoid updating until we know the entire
                    // pcrud action/transaction completed.
                    // After removal, select the parent org if available
                    // otherwise the root org.
                    const orgId = org.parent_ou() ?
                        org.parent_ou() : this.org.root().id();
                    this.loadAouTree(orgId).then(_ =>
                        this.postUpdate(this.editString));
                } }
            );
        });
    }

    orgTypeOptions(): ComboboxEntry[] {
        let ouType = this.currentOrg().ou_type();

        if (typeof ouType === 'number') {
            // May not be fleshed for new org units
            ouType = this.org.typeMap()[ouType];
        }
        const curDepth = ouType.depth();

        return this.org.typeList()
            .filter(type_ => type_.depth() === curDepth)
            .map(type_ => ({id: type_.id(), label: type_.name()}));
    }

    orgChildTypes(): IdlObject[] {
        let ouType = this.currentOrg().ou_type();

        if (typeof ouType === 'number') {
            // May not be fleshed for new org units
            ouType = this.org.typeMap()[ouType];
        }

        const depth = ouType.depth();
        return this.org.typeList()
            .filter(type_ => type_.depth() === depth + 1);
    }

    addChild() {
        const parentTreeNode = this.selected;
        const parentOrg = this.currentOrg();
        const newType = this.orgChildTypes()[0];

        const org = this.idl.create('aou');
        org.isnew(true);
        org.parent_ou(parentOrg.id());
        org.ou_type(newType.id());
        org.children([]);

        // Create a dummy, detached org node to keep the UI happy.
        this.selected = new TreeNode({
            id: org.id(),
            label: org.name(),
            callerData: {orgUnit: org}
        });
    }

    addressChanged(thing: any) {
        // Reload to pick up org unit address changes.
        this.orgSaved(this.currentOrg().id());
    }
}

