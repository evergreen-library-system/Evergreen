import {Component, OnInit, ViewChild, Output, Input} from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

// Can be used to create match_set_point's and match_set_quality's
export class MatchSetPointValues {
    pointType: string;
    recordAttr: string;
    matchScore: number;
    negate: boolean;
    marcTag: string;
    marcSf: string;
    heading: string;
    boolOp: string;
    value: string;
}

@Component({
  selector: 'eg-match-set-new-point',
  templateUrl: 'match-set-new-point.component.html'
})
export class MatchSetNewPointComponent implements OnInit {

    public values: MatchSetPointValues;

    bibAttrDefs: IdlObject[];
    bibAttrDefEntries: ComboboxEntry[];

    // defining a new match_set_quality
    @Input() isForQuality: boolean;

    // biblio, authority, quality
    @Input() set pointType(type_: string) {
        this.values.pointType = type_;
        this.values.recordAttr = '';
        this.values.matchScore = 1;
        this.values.negate = false;
        this.values.marcTag = '';
        this.values.marcSf = '';
        this.values.boolOp = 'AND';
        this.values.value = '';
    }

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService
    ) {
        this.values = new MatchSetPointValues();
        this.bibAttrDefs = [];
        this.bibAttrDefEntries = [];
    }

    ngOnInit() {
        this.pcrud.retrieveAll('crad', {order_by: {crad: 'label'}})
        .subscribe(attr => {
            this.bibAttrDefs.push(attr);
            this.bibAttrDefEntries.push({id: attr.name(), label: attr.label()});
        });
    }

    setNewPointType(type_: string) {
    }
}

