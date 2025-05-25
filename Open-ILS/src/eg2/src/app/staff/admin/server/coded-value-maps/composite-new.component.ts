import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';

export class CompositeNewPointValues {
    pointType: string;
    boolOp: string;
    typeLabel: string;
    typeId: string;
    valueLabel: string;
    valueId: string;
}

@Component({
    selector: 'eg-composite-new-point',
    templateUrl: 'composite-new.component.html'
})
export class CompositeNewPointComponent implements OnInit {

    public values: CompositeNewPointValues;

    attrTypeDefs: IdlObject[];
    attrValDefs: IdlObject[];
    attrTypes: ComboboxEntry[];
    attrVals: ComboboxEntry[];

    @Input() set pointType(type_: string) {
        this.values.pointType = type_;
        this.values.boolOp = '';
        this.values.valueLabel = '';
        this.values.valueId = '';
        this.values.typeId = '';
        this.values.typeLabel = '';
    }

    @ViewChild('valComboBox', {static: false}) valComboBox: ComboboxComponent;

    constructor(
        private pcrud: PcrudService
    ) {
        this.values = new CompositeNewPointValues();
        this.attrTypeDefs = [];
        this.attrTypes = [];
    }

    ngOnInit() {
        this.pcrud.retrieveAll('crad', {order_by: {crad: 'label'}})
            .subscribe(attr => {
                this.attrTypeDefs.push(attr);
                this.attrTypes.push({id: attr.name(), label: attr.label()});
            });
    }

    typeChange(evt) {
        this.values.typeId = evt.id;
        this.values.typeLabel = evt.label;
        this.valComboBox.selected = null;  // reset other combobox
        this.values.valueId = ''; // don't allow save with old valueId or valueLabel
        this.values.valueLabel = '';
        this.attrVals = [];
        this.attrValDefs = [];
        this.pcrud.search('ccvm', {'ctype': evt.id},
            {flesh: 1, flesh_fields: {ccvm: ['composite_def', 'ctype']} }).subscribe(
            { next: data => {
                this.attrValDefs.push(data);
                this.attrVals.push({id: data.code(), label: data.value()});
            }, error: (err: unknown) => {
                console.debug(err);
                this.attrVals = [];
                this.attrValDefs = [];
            } }
        );
    }

    valueChange(evt) {
        if (evt) {
            this.values.valueId = evt.id;
            this.values.valueLabel = evt.label;
        }
    }
}

