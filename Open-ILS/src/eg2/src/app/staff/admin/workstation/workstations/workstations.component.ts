import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {StoreService} from '@eg/core/store.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {EventService} from '@eg/core/event.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {HatchService} from '@eg/core/hatch.service';

// Slim version of the WS that's stored in the cache.
interface Workstation {
    id: number;
    name: string;
    owning_lib: number;
}

@Component({
    templateUrl: 'workstations.component.html'
})
export class WorkstationsComponent implements OnInit {

    selectedName: string;
    workstations: Workstation[] = [];
    removeWorkstation: string;
    newOwner: IdlObject;
    newName: string;
    defaultName: string;

    @ViewChild('workstationExistsDialog', { static: true })
    private wsExistsDialog: ConfirmDialogComponent;

    // Org selector options.
    hideOrgs: number[];
    disableOrgs: number[];
    orgOnChange = (org: IdlObject): void => {
        this.newOwner = org;
    };

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private evt: EventService,
        private net: NetService,
        private store: StoreService,
        private auth: AuthService,
        private org: OrgService,
        private hatch: HatchService,
        private perm: PermService
    ) {}

    ngOnInit() {
        this.store.getWorkstations()

            .then(wsList => {
                this.workstations = wsList || [];

                // Populate the new WS name field with the hostname when available.
                return this.setNewName();

            }).then(
                ok => this.store.getDefaultWorkstation()

            ).then(def => {
                this.defaultName = def;
                this.selectedName = this.auth.workstation() || this.defaultName;
                const rm = this.route.snapshot.paramMap.get('remove');
                if (rm) { this.removeSelected(this.removeWorkstation = rm); }
            });

        // TODO: use the org selector limitPerm option
        this.perm.hasWorkPermAt(['REGISTER_WORKSTATION'], true)
            .then(perms => {
            // Disable org units that cannot have users and any
            // that this user does not have work perms for.
                this.disableOrgs =
                this.org.filterList({canHaveUsers : false}, true)
                    .concat(this.org.filterList(
                        {notInList : perms.REGISTER_WORKSTATION}, true));
            });
    }

    selected(): Workstation {
        return this.workstations.filter(
            ws => ws.name === this.selectedName)[0];
    }

    useNow(): void {
        if (this.selected()) {
            this.router.navigate(['/staff/login'],
                {queryParams: {ws: this.selected().name}});
        }
    }

    setDefault(): void {
        if (this.selected()) {
            this.defaultName = this.selected().name;
            this.store.setDefaultWorkstation(this.defaultName);
        }
    }

    removeSelected(name?: string): void {
        if (!name) {
            name = this.selected().name;
        }

        this.workstations = this.workstations.filter(w => w.name !== name);
        this.store.setWorkstations(this.workstations);
    }

    setNewName() {
        this.hatch.hostname().then(name => this.newName = name || '');
    }

    canDeleteSelected(): boolean {
        return true;
    }

    registerWorkstation(): void {
        console.log('Registering new workstation ' +
            `"${this.newName}" at ${this.newOwner.shortname()}`);

        this.newName = this.newOwner.shortname() + '-' + this.newName;

        this.registerWorkstationApi().then(
            wsId => this.registerWorkstationLocal(wsId),
            notOk => console.log('Workstation registration canceled/failed')
        );
    }

    private handleCollision(): Promise<number> {
        return new Promise((resolve, reject) => {
            this.wsExistsDialog.open().subscribe(override => {
                if (override) {
                    this.registerWorkstationApi(true).then(
                        wsId => resolve(wsId),
                        notOk => reject(notOk)
                    );
                }
            });
        });
    }


    private registerWorkstationApi(override?: boolean): Promise<number> {
        let method = 'open-ils.actor.workstation.register';
        if (override) {
            method += '.override';
        }

        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.actor', method,
                this.auth.token(), this.newName, this.newOwner.id()
            ).subscribe(wsId => {
                const evt = this.evt.parse(wsId);
                if (evt) {
                    if (evt.textcode === 'WORKSTATION_NAME_EXISTS') {
                        this.handleCollision().then(
                            id => resolve(id),
                            notOk => reject(notOk)
                        );
                    } else {
                        console.error(`Registration failed ${evt}`);
                        reject();
                    }
                } else {
                    resolve(wsId);
                }
            });
        });
    }

    private registerWorkstationLocal(wsId: number) {
        const ws: Workstation = {
            id: wsId,
            name: this.newName,
            owning_lib: this.newOwner.id()
        };

        this.workstations.push(ws);
        this.store.setWorkstations(this.workstations);
        this.newName = '';
        // when registering our first workstation, mark it as the
        // default and show it as selected in the ws selector.
        if (this.workstations.length === 1) {
            this.selectedName = ws.name;
            this.setDefault();
        }
    }
}


