import {Component, OnInit, Renderer2} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';

@Component({
  templateUrl: 'bcsearch.component.html'
})

export class BcSearchComponent implements OnInit {

    barcode = '';

    constructor(
        private route: ActivatedRoute,
        private renderer: Renderer2,
        private net: NetService,
        private auth: AuthService
    ) {}

    ngOnInit() {

        this.renderer.selectRootElement('#barcode-search-input').focus();
        this.barcode = this.route.snapshot.paramMap.get('barcode');

        if (this.barcode) {
            this.findUser();
        }
    }

    findUser(): void {
        alert('Searching for user ' + this.barcode);
    }
}


