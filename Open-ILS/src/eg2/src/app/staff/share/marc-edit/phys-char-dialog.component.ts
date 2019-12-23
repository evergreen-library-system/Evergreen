import {Component, ViewChild, Input, Output, OnInit, EventEmitter} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {MarcEditorDialogComponent} from './editor-dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';

/**
 * 007 Physical Characteristics Dialog
 *
 * Note the dialog does not many direct changes to the bib field.
 * It simply emits the new value on close, or null of the
 * dialog canceled.
 */

@Component({
  selector: 'eg-phys-char-dialog',
  templateUrl: './phys-char-dialog.component.html'
})

export class PhysCharDialogComponent
    extends DialogComponent implements OnInit {

    // The 007 data
    @Input() fieldData = '';

    initialValue: string;

    selectorLabel: string = null;
    selectorValue: string;
    selectorOptions: ComboboxEntry[] = [];

    typeMap: ComboboxEntry[] = [];

    sfMap: {[ptypeKey: string]: any[]} = {};
    valueMap: {[ptypeKey: string]: ComboboxEntry[]} = {};

    currentPtype: string;

    // step is the 1-based position in the list of data slots for the
    // currently selected type. step==0 means we are currently selecting
    // the type.
    step = 0;

    // size and offset of the slot we're currently editing; this is
    // maintained as a convenience for the highlighting of the currently
    // active position
    slotOffset = 0;
    slotSize = 1;

    constructor(
        private modal: NgbModal,
        private idl: IdlService,
        private pcrud: PcrudService) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.initialValue = this.fieldData;
            this.reset();
        });
    }

    // Chop the field data value into 3 parts, before, middle, and
    // after, where 'middle' is the part we're currently editing.
    splitFieldData(): string[] {
        const data = this.fieldData;
        return [
            data.substring(0, this.slotOffset),
            data.substring(this.slotOffset, this.slotOffset + this.slotSize),
            data.substring(this.slotOffset + this.slotSize)
        ];
    }

    setValuesForStep(): Promise<any> {
        let promise;

        if (this.step === 0) {
            promise = this.getPhysCharTypeMap();
        } else {
            promise = this.currentSubfield().then(
                subfield => this.getPhysCharValueMap(subfield.id()));
        }

        return promise.then(list => {
            this.selectorOptions = list;
            this.setSelectedOptionFromField();
            this.setLabelForStep();
        });
    }

    setLabelForStep() {
        if (this.step === 0) {
            this.selectorLabel = null;  // fall back to template value
        } else {
            this.currentSubfield().then(sf => this.selectorLabel = sf.label());
        }
    }

    getStepSlot(): Promise<any[]> {
        if (this.step === 0) { return Promise.resolve([0, 1]); }
        return this.currentSubfield()
            .then(sf => [sf.start_pos(), sf.length()]);
    }

    setSelectedOptionFromField() {
        this.getStepSlot().then(slot => {
            this.slotOffset = slot[0];
            this.slotSize = slot[1];
            this.selectorValue =
                String.prototype.substr.apply(this.fieldData, slot) || ' ';
        });
    }

    isLastStep(): boolean {
        // This one is called w/ every digest, so avoid async
        // calls.  Wait until we have loaded the current ptype
        // subfields to determine if this is the last step.
        return (
            this.currentPtype &&
            this.sfMap[this.currentPtype] &&
            this.sfMap[this.currentPtype].length === this.step
        );
    }

    selectorChanged() {

        if (this.step === 0) {
            this.currentPtype = this.selectorValue;
            this.fieldData = this.selectorValue; // total reset

        } else {
            this.getStepSlot().then(slot => {

                let value = this.fieldData;
                const offset = slot[0];
                const size = slot[1];
                while (value.length < (offset + size)) { value += ' '; }

                // Apply the value to the field in the required slot,
                // then delete all data after "here", since those values
                // no longer make sense.
                const before = value.substr(0, offset);
                this.fieldData = before + this.selectorValue.padEnd(size, ' ');
                this.slotOffset = offset;
                this.slotSize = size;
            });
        }
    }

    next() {
        this.step++;
        this.setValuesForStep();
    }

    prev() {
        this.step--;
        this.setValuesForStep();
    }

    currentSubfield(): Promise<any> {
        return this.getPhysCharSubfieldMap(this.currentPtype)
        .then(sfList => sfList[this.step - 1]);
    }

    reset(clear?: boolean) {
        this.step = 0;
        this.slotOffset = 0;
        this.slotSize = 1;
        this.fieldData = clear ? ' ' : this.initialValue;
        this.currentPtype = this.fieldData.substr(0, 1);
        this.setValuesForStep();
    }

    getPhysCharTypeMap(): Promise<ComboboxEntry[]> {
        if (this.typeMap.length) {
            return Promise.resolve(this.typeMap);
        }

        return this.pcrud.retrieveAll(
            'cmpctm', {order_by: {cmpctm: 'label'}}, {atomic: true})
        .toPromise().then(maps => {
            return this.typeMap = maps.map(
                map => ({id: map.ptype_key(), label: map.label()}));
        });
    }

    getPhysCharSubfieldMap(ptypeKey: string): Promise<IdlObject[]> {

        if (this.sfMap[ptypeKey]) {
            return Promise.resolve(this.sfMap[ptypeKey]);
        }

        return this.pcrud.search('cmpcsm',
            {ptype_key : ptypeKey},
            {order_by : {cmpcsm : ['start_pos']}},
            {atomic : true}
        ).toPromise().then(maps => this.sfMap[ptypeKey] = maps);
   }

    getPhysCharValueMap(ptypeSubfield: string): Promise<ComboboxEntry[]> {

        if (this.valueMap[ptypeSubfield]) {
            return Promise.resolve(this.valueMap[ptypeSubfield]);
        }

        return this.pcrud.search('cmpcvm',
            {ptype_subfield : ptypeSubfield},
            {order_by : {cmpcsm : ['value']}},
            {atomic : true}
        ).toPromise().then(maps =>
            this.valueMap[ptypeSubfield] = maps.map(
                map => ({id: map.value(), label: map.label()}))
        );
   }
}


