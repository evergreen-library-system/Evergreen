import {Component, OnInit, ViewEncapsulation} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {empty} from 'rxjs';
import {switchMap, tap} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {IdlObject} from '@eg/core/idl.service';
import {SckoService} from './scko.service';
import {PrintService} from '@eg/share/print/print.service';


@Component({
    templateUrl: 'fines.component.html'
})

export class SckoFinesComponent implements OnInit {

    xacts: IdlObject[] = [];

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private printer: PrintService,
        public  scko: SckoService
    ) {}

    ngOnInit() {

        if (!this.scko.patronSummary) {
            this.router.navigate(['/staff/selfcheck']);
            return;
        }

        this.scko.resetPatronTimeout();

        this.pcrud.search('mbts',
            {   usr: this.scko.patronSummary.id,
                xact_finish: null,
                balance_owed: {'<>' : 0}
            }, {}, {atomic: true}
        ).pipe(switchMap(sums => {

            if (sums.length === 0) { return empty(); }

            return this.pcrud.search('mbt', {id: sums.map(s => s.id())},
                {   order_by: {mbt: 'xact_start'},
                    flesh: 5,
                    flesh_fields: {
                        mbt: ['summary', 'circulation', 'grocery'],
                        circ: ['target_copy'],
                        acp: ['call_number'],
                        acn: ['record'],
                        bre: ['flat_display_entries']
                    },
                    select: {bre : ['id']}
                }
            ).pipe(tap(xact => this.xacts.push(xact)));
        })).toPromise();
    }

    displayValue(xact: IdlObject, field: string): string {
        const entry =
            xact.circulation().target_copy().call_number().record().flat_display_entries()
                .filter(e => e.name() === field)[0];

        return entry ? entry.value() : '';
    }

    getTitle(xact: IdlObject): string {
        const copy = xact.circulation().target_copy();

        if (Number(copy.call_number().id()) === -1) {
            return copy.dummy_title();
        }

        return this.displayValue(xact, 'title');
    }

    getDetails(xact: IdlObject): string {
        if (xact.summary().xact_type() === 'circulation') {
            return this.getTitle(xact);
        } else {
            return xact.summary().last_billing_type();
        }
    }

    printList() {

        const data = this.xacts.map(x => {
            return {
                xact: x, // full object if needed
                details: this.getDetails(x),
                total_owed: x.summary().total_owed(),
                total_paid: x.summary().total_paid(),
                balance_owed: x.summary().balance_owed(),
            };
        });

        this.printer.print({
            templateName: 'scko_fines',
            contextData: {
                xacts: data,
                user: this.scko.patronSummary.patron
            },
            printContext: 'default'
        });
    }
}

