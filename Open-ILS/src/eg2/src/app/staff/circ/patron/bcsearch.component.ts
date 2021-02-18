import {Component, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {BarcodeSelectComponent} from '@eg/staff/share/barcodes/barcode-select.component';

@Component({
  templateUrl: 'bcsearch.component.html',
  selector: 'eg-patron-barcode-search'
})

export class BcSearchComponent implements OnInit, AfterViewInit {

    notFound = false;
    barcode = '';
    @ViewChild('barcodeSelect') private barcodeSelect: BarcodeSelectComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService
    ) {}

    ngOnInit() {
        this.barcode = this.route.snapshot.paramMap.get('barcode');
    }

    ngAfterViewInit() {
        const node = document.getElementById('barcode-search-input');
        if (node) { node.focus(); }
        if (this.barcode) { this.findUser(); }
    }

    findUser(): void {
        this.notFound = false;
        this.barcodeSelect.getBarcode('actor', this.barcode)
        .then(selection => {
            if (selection && selection.id) {
                this.router.navigate(['/staff/circ/patron', selection.id, 'checkout']);
            } else {
                this.notFound = true;
            }
        });
    }
}


