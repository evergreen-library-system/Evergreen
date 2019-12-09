
import {Component, OnInit, Input,Output,EventEmitter} from '@angular/core';
import { IdlService} from '@eg/core/idl.service';
class LinkedLimitSetObjects {
    linkedLimitSet:any;
    created:boolean;
    isDeleted:boolean;
    isNew:boolean;
}

@Component({
    selector:'linked-circ-limit-sets',
    templateUrl: './linked-circ-limit-sets.component.html'
})


export class LinkedCircLimitSetsComponent implements OnInit {

    @Input() usedSetLimitList = [];
    @Input() limitSetNames = {};
    @Output() outputLinkedLimitSet: EventEmitter<any>;
    linkedSetList = {};
    linkedSet:any;
    showLinkLimitSets:boolean

    constructor( 
        private idl: IdlService
        ) {
        this.outputLinkedLimitSet = new EventEmitter();
    }

    ngOnInit() {}

    displayLinkedLimitSets() {
        this.createEmptyLimitSetObject()
    }

    createFilledLimitSetObject(element) {
        let newLinkedSetObject = new LinkedLimitSetObjects();
        if(element.fallthrough() == "f") element.fallthrough(false)
        if(element.fallthrough() == "t") element.fallthrough(true)
        if(element.active() == "f") element.active(false)
        if(element.active() == "t") element.active(true)
        newLinkedSetObject.linkedLimitSet = element;
        newLinkedSetObject.created = true;
        newLinkedSetObject.isNew = false;
        newLinkedSetObject.isDeleted = false;
        this.linkedSetList[this.getObjectKeys().length] = newLinkedSetObject;
    }

    createEmptyLimitSetObject() {
        let object = this.idl.create("ccmlsm")
        let newLinkedSetObject = new LinkedLimitSetObjects();
        newLinkedSetObject.linkedLimitSet = object;
        newLinkedSetObject.linkedLimitSet.fallthrough(false);
        newLinkedSetObject.linkedLimitSet.active(true);
        newLinkedSetObject.isNew = true;
        newLinkedSetObject.created = false;
        newLinkedSetObject.isDeleted = false;
        this.linkedSetList[this.getObjectKeys().length] = newLinkedSetObject;
    }

    onChange(object:any) {
        this.linkedSet = object;
    }

    getObjectKeys() {
        if(this.linkedSetList) {
            return Object.keys(this.linkedSetList);
        } else {
            this.linkedSetList = {}
            return Object.keys({})
        }
    }

    addLinkedSet() {
        if (this.linkedSet) {
            if( !this.usedSetLimitList.find(element => element == this.linkedSet.id)) {
                this.createEmptyLimitSetObject();
                this.linkedSetList[this.getObjectKeys().length-1].linkedLimitSet.limit_set(this.linkedSet.id);
                this.linkedSetList[this.getObjectKeys().length-1].created = true;
                this.emitLimitSet();
                this.usedSetLimitList.push(this.linkedSet.id)
            }
        }
    }

    emitLimitSet() {
        this.outputLinkedLimitSet.emit(this.linkedSetList)
    }

    removeLinkedSet(index) {
        if(!this.linkedSetList[index].isNew) {
            this.usedSetLimitList.splice(index,1);
        }
        this.linkedSetList[index].isDeleted = true;
        this.emitLimitSet();
    }
}

