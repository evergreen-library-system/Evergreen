/* eslint-disable */
import {Component, Input, Output, ViewChild, QueryList, EventEmitter, TemplateRef, OnInit} from '@angular/core';
import {map} from 'rxjs/operators';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {Tree, TreeNode} from './tree';
import {TreeComponent} from './tree.component';

@Component({
    selector: 'eg-tree-multiselect',
    template: `
<div [id]="domId" class="eg-tree-multiselect">
<eg-tree #internalTree
  [disabled]="disabled"
  [showLabelFilter]="showLabelFilter"
  [showSelectAll]="showSelectAll"
  [showExpandAll]="showExpandAll"
  [disableRootSelector]="disableRootSelector"
  [disableStateFlag]="disableStateFlag"
  [disableStateFlagRangeSelect]="disableStateFlagRangeSelect"
  [rowTrailingTemplate]="rowTrailingTemplate"
  [stateFlagTemplate]="stateFlagTemplate"
  (nodeClicked)="handleInternalTreeNodeClicked($event)"
  (stateFlagClicked)="handleInternalTreeStateFlagClicked($event)"
/>
</div>
    `,
    styles: [`
.eg-tree-multiselect {
  max-height: 20rem;  /* About 10 items */
  overflow-y: auto;   /* Adds scrollbar only when needed. 'scroll' would show the scroll gutter at all times. */
  overflow-x: clip;   /* Avoid scrollbar */
}
    `]
})
export class TreeMultiselectComponent implements OnInit {

    @ViewChild('internalTree', { static: true }) private internalTree: TreeComponent;

    set tree(t: Tree) {
        if (t) {
            this.internalTree._tree = t;
            if (t.rootNode) {
                var nodes = t.descendants(t.rootNode); // reindex nodes
                if (this.defaultStateFlagLabel) { // set the default tooltip
                        nodes.forEach(n => n.stateFlagLabel = n.stateFlagLabel ? n.stateFlagLabel : this.defaultStateFlagLabel);
                }
            }
        }
    }

    get tree(): Tree {
        return this.internalTree._tree;
    }

    // input options for the new magic
    @Input() objectList: any[] = []; // [{id:'',label:''},...]
    @Input() selectorLabel: string;
    @Input() idlClass: string;
    @Input() idlBaseQuery: any = {};
    @Input() idlKey: string;
    @Input() idlLabel: string;
    @Input() linkedLibraryLabel: string;
    @Input() startValue: string;
    @Input() domId : string;

    // input options to allow overriding the tree
    @Input() defaultStateFlagLabel = $localize`Select`; // So that the state flag is on by default
    @Input() showLabelFilter = true; // Allow filtering by node label
    @Input() showSelectAll = false; // checkbox to toggle all state flags.
    @Input() showExpandAll = false; // show the expand/collapse all arrows?
    @Input() disableRootSelector = true; // checkbox at the top of the tree
    @Input() disableStateFlag = false; // Hide all checkboxes
    @Input() disableStateFlagRangeSelect = false; // Disable range selection 
    @Input() rowTrailingTemplate: TemplateRef<any>;
    @Input() stateFlagTemplate: TemplateRef<any>;
    @Input() disabled = false; // disables /changing/ state flag or emitting selection events

    @Output() onChange: EventEmitter<string>;
    @Output() nodeClicked: EventEmitter<TreeNode>;
    @Output() stateFlagClicked: EventEmitter<TreeNode>;

    constructor(
        private pcrud: PcrudService,
        private org: OrgService,
        private idl: IdlService
    ) {
        if (this.disabled) {
            this.showLabelFilter = false;
            this.showSelectAll = false;
        }

        this.onChange = new EventEmitter<string>();
        this.nodeClicked = new EventEmitter<TreeNode>();
        this.stateFlagClicked = new EventEmitter<TreeNode>();
    }

    compileCurrentValue(): string {
        const valstr = this.tree.findStateFlagNodes().map(n => n.id).join(',')
        return '{' + valstr + '}';
    }

    handleInternalTreeNodeClicked(node: TreeNode) {
        node.toggleStateFlag(); // toggle the state flag when the label is clicked, wiring them together
        //this.nodeClicked.emit(node);
        this.onChange.emit(this.compileCurrentValue());
    }

    handleInternalTreeStateFlagClicked(node: TreeNode) {
        //this.stateFlagClicked.emit(node);
        this.onChange.emit(this.compileCurrentValue());
    }

    ngOnInit() {

        if (!this.idlKey) {
            if (this.idlClass) {
                this.idlKey = this.idl.classes[this.idlClass].pkey || 'id';
            } else {
                this.idlKey = 'id';
            }
        }

        if (!this.idlLabel) {
            if (this.idlClass) {
                this.idlLabel = this.idl.getClassSelector(this.idlClass) || 'name';
            } else {
                this.idlLabel = 'name';
            }
        }

        if (this.idlClass && !this.selectorLabel) {
            this.selectorLabel = this.idl.classes[this.idlClass].label || this.idl.classes[this.idlClass].name;
        }

        if (!this.selectorLabel) {
            this.selectorLabel = $localize`Objects`;
        }

        if (this.objectList.length) {
            this.tree = new Tree(
                new TreeNode({
                    id: 'tree-root',
                    label: this.selectorLabel,
                    expanded: true,
                    children: this.objectList.map(o => new TreeNode(o))
                })
            );
        } else {

            const searchHash = {...this.idlBaseQuery};
            var ids = [];

            if (this.startValue && this.startValue !== '{}') {
                let valstr = this.startValue;
                valstr = valstr.replace(/^{/, '');
                valstr = valstr.replace(/}$/, '');
                ids = valstr.split(',');

                if (this.disabled) { // only show the selected ones in fully-disabled mode
                    searchHash[this.idlKey] = ids;
                }
            }
            
            if (!searchHash[this.idlKey]) {
                searchHash[this.idlKey] = { '!=': null };
            }

            var p = null;
            var kids = [];

            this.pcrud.search(this.idlClass, searchHash).pipe(map(data => {
                const tail = this.linkedLibraryLabel ? ' (' + this.getOrgShortname(data[this.linkedLibraryLabel]()) + ')' : '';
                kids.push(new TreeNode({
                    id: data[this.idlKey](),
                    label: data[this.idlLabel]() + tail,
                    stateFlag: ids.includes(''+data[this.idlKey]())
                }));
            })).toPromise().then(
                _ => this.tree = new Tree(
                    new TreeNode({
                        id: 'tree-root',
                        label: this.selectorLabel,
                        expanded: true,
                        children: kids.sort((a,b) => a.label.localeCompare(b.label))
                    })
                )
            );
        }
    }

    getOrgShortname(ou: any) {
        if (typeof ou === 'object') {
            return ou.shortname();
        } else {
            return this.org.get(ou).shortname();
        }
    }
}



