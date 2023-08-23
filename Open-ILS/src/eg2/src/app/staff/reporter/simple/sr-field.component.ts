import {Component, Input, Output, EventEmitter, OnInit} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {ReporterService} from '../share/reporter.service';

@Component({
    selector: 'eg-sr-field',
    templateUrl: './sr-field.component.html',
    styleUrls: ['./sr-field.component.css'],
})
export class SRFieldComponent implements OnInit {

    operators = [];
    transforms = [];
    wsContextOrgs = [];
    linkedIdlBaseQuery = {};

    @Input() field: IdlObject = null;
    @Output() fieldChange = new EventEmitter<IdlObject>();
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

    constructor(
        private org: OrgService,
        private auth: AuthService,
        private srSvc: ReporterService
    ) {
    }

    ngOnInit() {

        if ( this.withTransforms ) {
            this.transforms = this.srSvc.getTransformsForDatatype(this.field.datatype, true);
        }

        if ( this.withOperators ) {
            this.operators = this.srSvc.getOperatorsForDatatype(this.field.datatype);
        }

        this.wsContextOrgs = this.org.fullPath(this.auth.user().ws_ou(), true);
        if (this.field.org_filter_field) {
            this.linkedIdlBaseQuery[this.field.org_filter_field] = this.wsContextOrgs;
        }
    }

    clearFilterValue() {
        this.field.filter_value = this.field.operator.arity > 1 ? [] : null;
        delete this.field._org_family_includeAncestors;
        delete this.field._org_family_includeDescendants;
        delete this.field._org_family_primaryOrgId;
    }

    operatorChange($event) {
        const new_op = this.srSvc.getOperatorByName($event.target.value);
        if (new_op.arity !== this.field.operator.arity) { // param count of the old and new ops are different
            this.field.operator = new_op;
            this.clearFilterValue(); // clear the filter value
        } else {
            this.field.operator = new_op;
        }
        this.fieldChange.emit(this.field);
    }

    transformChange($event) {
        const new_transform = this.srSvc.getTransformByName($event.target.value);

        if (new_transform.final_datatype) { // new has a final_datatype
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
            this.operators = this.srSvc.getOperatorsForDatatype(new_transform.final_datatype);
        } else {
            this.operators = this.srSvc.getOperatorsForDatatype(this.field.datatype);
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

