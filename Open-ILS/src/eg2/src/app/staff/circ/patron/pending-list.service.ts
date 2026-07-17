import { DOCUMENT } from '@angular/common';
import { inject, Injectable } from '@angular/core';
import { AuthService } from '@eg/core/auth.service';
import { EventService } from '@eg/core/event.service';
import { IdlObject } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { OrgService } from '@eg/core/org.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { Pager } from '@eg/share/util/pager';
import { catchError, EMPTY, forkJoin, map, Observable, tap } from 'rxjs';

// Relevant slice of the staged user server response
export interface PendingPatron {
    mailing_address: IdlObject;
    mailing_addresses: IdlObject[];
    user: IdlObject;
}

@Injectable()
export class PendingListService {

    private readonly auth = inject(AuthService);
    private readonly document = inject(DOCUMENT);
    private readonly evt = inject(EventService);
    private readonly net = inject(NetService);
    private readonly org = inject(OrgService);
    private readonly toast = inject(ToastService);

    defaultContextOrg(): number {
        return this.auth.user().ws_ou();
    }

    deletePendingPatrons(patrons: PendingPatron[]): Observable<unknown> {
        if (!patrons.length) { return EMPTY; }

        const successMsg = $localize`Pending patron(s) deleted`;
        const errorMsg = $localize`Failed to delete pending patron(s)`;

        return forkJoin(patrons.map(({ user }) =>
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.stage.delete',
                this.auth.token(), user.row_id()
            )
        )).pipe(
            tap(results => {
                const failed = results.filter(r => !!this.evt.parse(r));
                if (failed.length === patrons.length) {
                    // Swallow emission, no need to reload grid
                    throw new Error();
                }
                if (failed.length) {
                    // Some failed, so notify and emit to reload grid
                    this.toast.danger(errorMsg);
                } else {
                    this.toast.success(successMsg);
                }
            }),
            catchError(() => {
                this.toast.danger(errorMsg);
                return EMPTY;
            })
        );
    }

    getPendingPatrons(orgId: number, { limit, offset }: Pager): Observable<PendingPatron> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.stage.retrieve.by_org',
            this.auth.token(),
            orgId, limit, offset
        ).pipe(
            map(stagedUser => {
                // Adjust data a little for ease of use in grid columns
                stagedUser.user.home_ou(
                    this.org.get(stagedUser.user.home_ou())
                );
                stagedUser.mailing_address =
                    stagedUser.mailing_addresses[0];
                return stagedUser;
            }),
            catchError(() => {
                this.toast.danger(
                    $localize`Failed to retrieve pending patrons`
                );
                return EMPTY;
            })
        );
    }

    loadPendingPatron(patron: PendingPatron): void {
        const usrname = encodeURIComponent(patron.user.usrname());
        this.document.defaultView?.open(
            `/eg2/staff/circ/patron/register/stage/${usrname}`,
            '_blank'
        );
    }

}
