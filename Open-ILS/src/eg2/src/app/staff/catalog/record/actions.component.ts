import {Component, OnInit, Input, Output, EventEmitter} from '@angular/core';
import {Router} from '@angular/router';
import {StoreService} from '@eg/core/store.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {StaffCatalogService} from '../catalog.service';
import {StringService} from '@eg/share/string/string.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';

@Component({
    selector: 'eg-catalog-record-actions',
    templateUrl: 'actions.component.html'
})
export class RecordActionsComponent implements OnInit {

    @Output() addHoldingsRequested: EventEmitter<void>
        = new EventEmitter<void>();

    recId: number;
    initDone = false;
    searchContext: CatalogSearchContext;

    targets = {
        conjoined: {
            key: 'eg.cat.marked_conjoined_record',
            current: null
        },
        overlay: {
            key: 'eg.cat.marked_overlay_record',
            current: null
        },
        holdTransfer: {
            key: 'eg.circ.hold.title_transfer_target',
            current: null
        },
        holdingTransfer: {
            key: 'eg.cat.transfer_target_record',
            current: null,
            clear: [ // Clear these values on mark.
                'eg.cat.transfer_target_lib',
                'eg.cat.transfer_target_vol'
            ]
        }
    };

    get patronViewUrl(): string {
        if (!this.staffCat.patronViewUrl) {
            return `/eg/opac/record/${encodeURIComponent(this.recId)}`;
        }
        return encodeURI(this.staffCat.patronViewUrl.replace(
            /\{eg_record_id\}/g, ''+this.recId
        ));
    }

    @Input() set recordId(recId: number) {
        this.recId = recId;
        if (this.initDone) {
            // Fire any record specific actions here
        }
    }

    @Input() isHoldable: boolean;

    constructor(
        private router: Router,
        private store: StoreService,
        private strings: StringService,
        private toast: ToastService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private holdings: HoldingsService
    ) {}

    ngOnInit() {
        this.initDone = true;

        Object.keys(this.targets).forEach(name => {
            const target = this.targets[name];
            target.current = this.store.getLocalItem(target.key);
        });
    }

    mark(name: string) {
        const target = this.targets[name];
        target.current = this.recId;
        this.store.setLocalItem(target.key, this.recId);

        if (target.clear) {
            // Some marks require clearing other marks.
            target.clear.forEach(key => this.store.removeLocalItem(key));
        }

        this.strings.interpolate('catalog.record.toast.' + name)
            .then(txt => this.toast.success(txt));
    }

    clearMarks() {
        Object.keys(this.targets).forEach(name => {
            const target = this.targets[name];
            target.current = null;
            this.store.removeLocalItem(target.key);
        });
        this.strings.interpolate('catalog.record.toast.cleared')
            .then(txt => this.toast.success(txt));
    }

    addHoldings() {
        this.addHoldingsRequested.emit();
    }
}


