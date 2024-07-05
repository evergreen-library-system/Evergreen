/* eslint-disable */
import {Component, Input, Output, EventEmitter, OnInit, ViewEncapsulation} from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ReporterService} from '../share/reporter.service';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {Md5} from 'ts-md5';

@Component({
    selector: 'eg-reporter-field',
    templateUrl: './reporter-field.component.html',
    styleUrls: ['./reporter-field.component.css'],
    encapsulation: ViewEncapsulation.None
})
export class ReporterFieldComponent implements OnInit {

    operators = [];
    transforms = [];
    wsContextOrgs = [];
    linkedIdlBaseQuery = {};
    pathLabel = '';
    pathId = '';
    origDatatype = '';
    orgTree: Tree = null;
    advancedMode = false;
    supplyHint = false;
    relativeTransform = false;

    @Input() editorMode = 'template';
    @Input() field: IdlObject = null;
    @Output() fieldChange = new EventEmitter<IdlObject>();
    @Input() withHint = true;
    @Input() editHint = true;
    @Input() withAlias = false;
    @Input() editAlias = true;
    @Input() withTransforms = false;
    @Input() withOperators = false;
    @Input() withValueInput = false;
    @Input() withSelect = false;
    @Input() withDeselect = false;
    @Input() withSortDirection = false;
    @Output() selectEvent = new EventEmitter();
    @Output() deselectEvent = new EventEmitter();
    @Input() selected = false;
    @Input() withUpDown = false;
    @Output() upEvent = new EventEmitter();
    @Output() downEvent = new EventEmitter();
    @Input() disableUp = false;
    @Input() disableDown = false;
    @Input() disabled = false;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private RSvc: ReporterService
    ) {
    }

    visibleTransforms() { return this.transforms.filter(t => !t.hidden); }

    ngOnInit() {

        if ( this.withTransforms ) {
            if (this.field.transform?.name === 'date') {
                this.field.transform.name = 'date_trunc'; // cleanup old templates
            }

            if (this.field.transform?.name === 'count') {
                this.field.transform.name = 'count_distinct'; // cleanup old templates
            }

            this.transforms = this.RSvc.getTransformsForDatatype(this.field.datatype);
        }

        if ( this.withOperators ) {
            this.operators = this.RSvc.getOperatorsForDatatype(this.field.datatype);
        }

        this.wsContextOrgs = this.org.fullPath(this.auth.user().ws_ou(), true);
        if (this.field.org_filter_field) {
            this.linkedIdlBaseQuery[this.field.org_filter_field] = this.wsContextOrgs;
        }

        if (this.editorMode === 'template' && this.field.with_value_input) {
            this.withValueInput = this.field.with_value_input;
        }

        if (this.field.path) {
            this.makePathLabel();

            const fmField = this.getFMFieldFromPathEnd();

            if (this.field.datatype === 'id') { // pkey somewhere, do we treat it like a link?
                if (fmField && this.field.path.length > 1
                    && ['has_a','might_have'].includes(fmField.reltype)
                    && this.idl.getClassSelector(fmField.class, true)
                ) { // we're the right side of a has_a link field. steal the left side's info for rendering
                    this.origDatatype = 'id';
                    this.field.datatype = 'link';
                    this.field.class = fmField.class;
                    this.field.key = fmField.key;
                }
            }
        }

        if (this.field.datatype === 'org_unit'
            || this.field.transform.final_datatype === 'org_unit') {

            this.org.sortTree('name');

            const preselected = this.field.filter_value || [];
            const node = new TreeNode({
                id       : this.org.root().id(),
                label    : this.org.root().name(),
                expanded : false,
                stateFlag: preselected.includes(this.org.root().id()),
                stateFlagLabel: $localize`Selected`,
                children : []
            });

            this.treeifyOrg(node, preselected);

            this.orgTree = new Tree(node);
            preselected.forEach( i => this.orgTree.expandPathTo(this.orgTree.findNode(i)) );
            this.orgTree.expandPathTo(this.orgTree.findNode(this.org.get(this.auth.user().ws_ou()).id()));

        }

        let already_collected_rel_time_input = this.field.transform.relativeTransform;
        if (this.field.transform.relative_time_input_transform) {
            if (Array.isArray(this.field.filter_value)) {
                if (typeof this.field.filter_value[0] === 'object') {
                    already_collected_rel_time_input =
                        this.field.transform.relativeTransform =
                        !!(this.field.filter_value[0]?.transform?.match(/^relative_/).length > 0);
                }
            } else if (typeof this.field.filter_value === 'object') {
                already_collected_rel_time_input =
                    this.field.transform.relativeTransform =
                    !!(this.field.filter_value?.transform?.match(/^relative_/).length > 0);
            }
        }

        // we need to set up the default filter
        // because, otherwise, you can save a broken
        // template.
        if (this.field.transform.relativeTransform && !already_collected_rel_time_input) {
            this.clearFilterValue();
        }

        if (this.field.field_doc_supplied) {
            this.supplyHint = true;
        }
    }

    getFMFieldFromPathEnd() {
        if (!this.field.path) {return null;}
        return this.field.path[this.field.path.length - 1].callerData?.fmField;
    }

    toggleSupplyHint() {
        if (!this.supplyHint) { // reversed... ugh
            this.field.field_doc ??= '';
            this.field.field_doc_supplied = true;
            if (!this.field.field_doc && this.field.path?.length ) {
                this.getFieldDoc().then(d => this.field.field_doc = d?.string());
            }
        } else {
            this.field.field_doc_supplied = false;
            this.field.field_doc = '';
        }
    }

    treeifyOrg(node, preselected) {
        this.org.get(node.id).children().forEach(x => {
            const new_node = new TreeNode({
                id      : x.id(),
                label   : x.name(),
                expanded: false,
                stateFlag: preselected.includes(x.id()),
                stateFlagLabel: $localize`Selected`,
                children: []
            });
            this.treeifyOrg(new_node, preselected);
            node.children.push(new_node);
        });
    }

    getFieldDoc(): Promise<any> {
        return this.pcrud.search(
            'fdoc',
            { owner   : this.wsContextOrgs,
			  fm_class: this.field.path[this.field.path.length - 1].id,
			  field   : this.field.name
            }
        ).toPromise();
    }

    combineLabelAndStateClick (node: TreeNode) {
        node.toggleStateFlag();
        this.saveFlaggedOrgs();
    }

    saveFlaggedOrgs() {
        this.field.filter_value = this.orgTree.findStateFlagNodes().map(x => x.id);
    }

    makePathLabel() {
        this.pathLabel = '';
        this.field.path.forEach((n,i) => {
            if (i) {
                this.pathLabel += ' -> ';
            }
            this.pathLabel += n.label;
            if (n.stateFlag) {this.pathLabel += ' (Required)';}
        });
        this.pathLabel += ' -> ' + (this.field.label || this.field.name);
        this.field.path_label = this.pathLabel;
        this.pathId = Md5.hashStr(this.pathLabel);
    }

    toggleFilterValueSupplied() {
        this.field.with_value_input = !this.withValueInput; // why does this need to be inverted????
        this.clearFilterValue();
    }

    setRelativeTransformDefault(newTransform) {
        if (this.field.operator.arity > 1) {
            [0,0].forEach( x => this.field.filter_value.push({
                transform: newTransform,
                params: [x]
            }));
        } else {
            this.field.filter_value = {
                transform: newTransform,
                params: [0]
            };
        }
    }

    clearFilterValue() {
        this.field.filter_value = this.field.operator.arity > 1 ? [] : null;

        if (this.field.transform.relativeTransform) {
            this.setRelativeTransformDefault(this.field.transform.relative_time_input_transform);
        }

        delete this.field._org_family_includeAncestors;
        delete this.field._org_family_includeDescendants;
        delete this.field._org_family_primaryOrgId;

        if (this.orgTree) {
            this.orgTree.findStateFlagNodes().map(x => x.stateFlag = false);
        }
    }

    operatorChange($event) {
        const new_op = this.RSvc.getOperatorByName($event.target.value);
        if (new_op.arity !== this.field.operator.arity) { // param count of the old and new ops are different
            this.field.operator = new_op;
            this.clearFilterValue(); // clear the filter value
        } else {
            this.field.operator = new_op;
        }
        this.fieldChange.emit(this.field);
    }

    replaceRelativeTransform(newTransform) {
        if (this.field.operator.arity > 1) {
            this.field.filter_value.forEach(v => v.transform = newTransform);
        } else {
            this.field.filter_value.transform = newTransform;
        }
    }

    transformChange($event) {
        const new_transform = this.RSvc.getTransformByName($event.target.value);

        if (this.field.transform.relativeTransform) {
            if (this.field.transform.relative_time_input_transform && new_transform.relative_time_input_transform) {
                this.replaceRelativeTransform(new_transform.relative_time_input_transform);
            } else if (new_transform.relative_time_input_transform) {
                this.setRelativeTransformDefault(new_transform.relative_time_input_transform);
            } else if (this.field.transform.relative_time_input_transform) {
                this.field.transform.relativeTransform = false;
                this.clearFilterValue();
            }
        } else if (new_transform.final_datatype) { // new has a final_datatype
            if (this.field.transform.final_datatype) { // and so does old
                if (new_transform.final_datatype !== this.field.transform.final_datatype) { // and they're different
                    this.clearFilterValue(); // clear
                }
            } else if (new_transform.final_datatype !== this.field.datatype) { // old does not, and base is different from new
                this.clearFilterValue(); // clear
            }
        } else if (this.field.transform.final_datatype) {// old has a final_datatype, new doesn't
            if (this.field.transform.final_datatype !== this.field.datatype) { // and it's different from the base type
                this.clearFilterValue(); // clear
            }
        }

        this.field.transform = new_transform;
        if (new_transform.final_datatype) {
            this.operators = this.RSvc.getOperatorsForDatatype(new_transform.final_datatype);
        } else {
            this.operators = this.RSvc.getOperatorsForDatatype(this.field.datatype);
        }

        this.selectEvent.emit();
        this.fieldChange.emit(this.field);
    }

    firstBetweenValue($event) {
        if (!Array.isArray(this.field.filter_value)) {
            this.field.filter_value = [];
        }
        this.field.filter_value[0] = $event;
        this.fieldChange.emit(this.field);
    }

    secondBetweenValue($event) {
        if (!Array.isArray(this.field.filter_value)) {
            this.field.filter_value = [];
        }
        this.field.filter_value[1] = $event;
        this.fieldChange.emit(this.field);
    }

    setSingleValue($event) {
        if (Array.isArray(this.field.filter_value)) {
            this.field.filter_value = null;
        }
        this.field.filter_value = $event;
        this.fieldChange.emit(this.field);
    }

    getBracketListValue(list_value) {
        let output = '{';
        if (Array.isArray(list_value)) {
            list_value.forEach((v, i) => {
                if (i > 0) {
                    output += ',';
                }
                output += v;
            });
        }
        output += '}';
        return output;
    }

    setOrgFamilyValue($event) {
        this.field.filter_value = this.getBracketListValue($event.orgIds);
        this.field._org_family_includeAncestors = $event.includeAncestors;
        this.field._org_family_includeDescendants = $event.includeDescendants;
        this.field._org_family_primaryOrgId = $event.primaryOrgId;
        this.fieldChange.emit(this.field);
    }

    setBracketListValue($event) {
        if (Array.isArray(this.field.filter_value)) {
            this.field.filter_value = null;
        }
        let valstr = $event;
        valstr = valstr.replace(/^{/, '');
        valstr = valstr.replace(/}$/, '');
        const ids = valstr.split(',');
        this.field.filter_value = [...ids];
        this.fieldChange.emit(this.field);
    }

    directionChange($event) {
        this.field['direction'] = $event.target.value;
        this.fieldChange.emit(this.field);
    }

    selectAction() {
        this.selectEvent.emit();
    }

    deselectAction() {
        this.deselectEvent.emit();
    }

    upAction() {
        this.upEvent.emit();
    }

    downAction() {
        this.downEvent.emit();
    }

}

