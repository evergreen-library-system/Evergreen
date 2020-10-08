import {Component, OnInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {PoService} from './po.service';

@Component({
  templateUrl: 'po.component.html'
})
export class PoComponent implements OnInit {

    poId: number;

    constructor(
        private route: ActivatedRoute,
        public  poService: PoService
    ) {}

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.poId = +params.get('poId');
        });
    }

    isBasePage(): boolean {
        return !this.route.firstChild ||
            this.route.firstChild.snapshot.url.length === 0;
    }
}

