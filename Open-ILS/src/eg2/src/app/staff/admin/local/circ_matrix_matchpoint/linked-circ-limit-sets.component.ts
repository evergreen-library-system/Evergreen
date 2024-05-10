/* eslint-disable */

import {Component, OnInit, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import { IdlService} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';

class LinkedLimitSetObjects {
    linkedLimitSet: any;
    created: boolean;
    isDeleted: boolean;
    isNew: boolean;
}

@Component({
    selector: 'eg-linked-circ-limit-sets',
    templateUrl: './linked-circ-limit-sets.component.html'
})

export class LinkedCircLimitSetsComponent implements OnInit {

    @Input() usedSetLimitList = {};
    @Input() limitSetNames = {};
    @Output() outputLinkedLimitSet: EventEmitter<any>;
    linkedSetList = {};
    linkedSet: any;
    showLinkLimitSets: boolean;

    @ViewChild('combobox') combobox: ComboboxComponent;

    constructor(
        private idl: IdlService,
        private toast: ToastService
        ) {
        this.outputLinkedLimitSet = new EventEmitter();
    }

    ngOnInit() {
        console.debug('LinkedCircLimitSetsComponent, ngOnInit(), this',this);
    }

    reset() {
        this.usedSetLimitList = {};
        this.linkedSetList = [];
        this.linkedSet = null;
        if (this.combobox) { // lifecycle issues here; this method gets called on page load
            console.debug('LinkedCircLimitSetsComponent, reset(), this.combobox', this.combobox);
            this.combobox.selectedId = null;
        }
    }

    displayLinkedLimitSets() {
        this.createEmptyLimitSetObject();
    }

    createFilledLimitSetObject(element) {
        const newLinkedSetObject = new LinkedLimitSetObjects();
        if (element.fallthrough() === 'f') { element.fallthrough(false); }
        if (element.fallthrough() === 't') { element.fallthrough(true); }
        if (element.active() === 'f') { element.active(false); }
        if (element.active() === 't') { element.active(true); }
        newLinkedSetObject.linkedLimitSet = element;
        newLinkedSetObject.created = true;
        newLinkedSetObject.isNew = false;
        newLinkedSetObject.isDeleted = false;
        this.linkedSetList[this.getObjectKeys().length] = newLinkedSetObject;
    }

    createEmptyLimitSetObject() {
        const object = this.idl.create('ccmlsm');
        const newLinkedSetObject = new LinkedLimitSetObjects();
        newLinkedSetObject.linkedLimitSet = object;
        newLinkedSetObject.linkedLimitSet.fallthrough(false);
        newLinkedSetObject.linkedLimitSet.active(true);
        newLinkedSetObject.isNew = true;
        newLinkedSetObject.created = false;
        newLinkedSetObject.isDeleted = false;
        this.linkedSetList[this.getObjectKeys().length] = newLinkedSetObject;
    }

    onChange(object: any) {
        this.linkedSet = object;
    }

    getObjectKeys() {
        if (this.linkedSetList) {
            return Object.keys(this.linkedSetList);
        } else {
            this.linkedSetList = {};
            return Object.keys({});
        }
    }

    addLinkedSet() {
        if (this.linkedSet) {
            this.createEmptyLimitSetObject();
            this.linkedSetList[this.getObjectKeys().length - 1].linkedLimitSet.limit_set(this.linkedSet.id);
            this.linkedSetList[this.getObjectKeys().length - 1].created = true;
            this.emitLimitSet();
            this.usedSetLimitList[this.linkedSet.id] = this.linkedSet.label;
        }
    }

    emitLimitSet() {
        this.outputLinkedLimitSet.emit(this.linkedSetList);
    }

    removeLinkedSet(index) {
        delete this.usedSetLimitList[this.linkedSetList[index].linkedLimitSet.limit_set()];
        this.linkedSetList[index].isDeleted = true;
        this.emitLimitSet();
    }
}

