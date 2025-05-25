import {Component, OnInit, Input, Output} from '@angular/core';
import {ActivatedRoute, Router, ParamMap, NavigationStart} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {UploadComponent} from '../picklist/upload.component';


interface AssetCreationResponse {
    liProcessed: number;
    vqbrProcessed: number;
    bibsProcessed: number;
    lidProcessed: number;
    debitsProcessed: number;
    copiesProcessed: number;
}

@Component({
    templateUrl: 'create-assets.component.html'
})
export class CreateAssetsComponent implements OnInit {

    targetPo: number;
    creationRequested = false;
    creatingAssets = false;
    activatePo = false;

    creationStatus: AssetCreationResponse = {
        liProcessed: 0,
        vqbrProcessed: 0,
        bibsProcessed: 0,
        lidProcessed: 0,
        debitsProcessed: 0,
        copiesProcessed: 0
    };
    creationErrors: EgEvent[] = [];

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        private auth: AuthService,
        private net: NetService,
        private evt: EventService,
        private pcrud: PcrudService,
        private liService: LineitemService
    ) { }

    ngOnInit() {
        this.activatePo = history.state.activatePo ? true : false;
        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            this.targetPo = +params.get('poId');
        });
    }

    // using arrow notion here because we want 'this' to
    // refer to CreateAssetsComponent, not the component
    // that createAssets is passed to
    createAssets = (args: Object) => {
        this.creatingAssets = true;
        this.creationRequested = true;
        this.creationErrors = [];

        const assetArgs = {
            vandelay: args['vandelay']
        };

        this.net.request(
            'open-ils.acq',
            'open-ils.acq.purchase_order.assets.create',
            this.auth.token(),
            this.targetPo,
            assetArgs
        ).subscribe(
            { next: resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    this.creationErrors.push(evt);
                } else {
                    this.creationStatus['liProcessed'] = resp.li;
                    this.creationStatus['vqbrProcessed'] = resp.vqbr;
                    this.creationStatus['bibsProcessed'] = resp.bibs;
                    this.creationStatus['lidProcessed'] = resp.lid;
                    this.creationStatus['debitsProcessed'] = resp.debits_accrued;
                    this.creationStatus['copiesProcessed'] = resp.copies;
                }
            }, error: (err: unknown) => {}, complete: () => {
                if (!this.creationErrors.length) {
                    this.creatingAssets = false;
                    if (this.activatePo) {
                        this.router.navigate(
                            ['/staff/acq/po/' + this.targetPo],
                            { state: { finishPoActivation: true } }
                        );
                    }
                }
            } }
        );
    };
}

