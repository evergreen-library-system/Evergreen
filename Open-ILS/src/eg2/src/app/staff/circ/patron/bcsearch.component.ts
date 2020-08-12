import {Component, OnInit, AfterViewInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';

@Component({
  templateUrl: 'bcsearch.component.html',
  selector: 'eg-patron-barcode-search'
})

export class BcSearchComponent implements OnInit, AfterViewInit {

    barcode = '';

    constructor(
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService
    ) {}

    ngOnInit() {
        this.barcode = this.route.snapshot.paramMap.get('barcode');
        if (this.barcode) {
            this.findUser();
        }
    }

    ngAfterViewInit() {
        document.getElementById('barcode-search-input').focus();
    }

    findUser(): void {
        alert('Searching for user ' + this.barcode);
    }
}


