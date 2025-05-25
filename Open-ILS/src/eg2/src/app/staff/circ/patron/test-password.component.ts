import {Component, Input, OnInit, AfterViewInit} from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';

@Component({
    templateUrl: 'test-password.component.html',
    selector: 'eg-patron-test-password'
})
export class TestPatronPasswordComponent implements OnInit, AfterViewInit {

    @Input() patronId: number;
    patron: IdlObject;
    username = '';
    barcode = '';
    password = '';
    verified = null;
    notFound = false;

    constructor(
        private router: Router,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        public patronService: PatronService
    ) {}

    ngOnInit() {

        if (this.patronId) {
            this.patronService.getById(this.patronId,
                {flesh: 1, flesh_fields: {au: ['card']}})
                .then(p => {
                    this.patron = p;
                    this.username = p.usrname();
                    this.barcode = p.card().barcode();
                });
        }
    }

    ngAfterViewInit() {
        let domId = 'password-input';
        if (!this.patronId) { domId = 'username-input'; }
        const node = document.getElementById(domId) as HTMLInputElement;
        if (node) { node.focus(); }
    }

    retrieve() {
        this.verified = null;
        this.notFound = false;

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.retrieve_id_by_barcode_or_username',
            this.auth.token(), this.barcode, this.username
        ).subscribe(resp => {
            if (this.evt.parse(resp)) {
                this.notFound = true;
            } else {
                this.router.navigate(['/staff/circ/patron/', resp, 'checkout']);
            }
        });
    }

    verify() {
        if (!this.username && !this.barcode) { return; }

        this.net.request('open-ils.actor',
            'open-ils.actor.verify_user_password', this.auth.token(),
            this.barcode, this.username, null, this.password)

            .subscribe(resp => {
                const evt = this.evt.parse(resp);

                this.password = null;

                if (evt) {
                    console.error(evt);
                    alert(evt);
                } else if (Number(resp) === 1) {
                    this.verified = true;
                } else {
                    this.verified = false;
                }
            });
    }
}

