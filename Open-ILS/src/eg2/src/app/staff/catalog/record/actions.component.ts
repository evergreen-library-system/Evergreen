import { Component, OnInit, Input, Output, EventEmitter, inject } from '@angular/core';
import {HttpClient} from '@angular/common/http';
import {StoreService} from '@eg/core/store.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';
import {StringService} from '@eg/share/string/string.service';
import {ToastService} from '@eg/share/toast/toast.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { UploadJacketImageDialogComponent } from './upload-jacket-image-dialog.component';
import { AddToCarouselDialogComponent } from './add-to-carousel-dialog.component';

export const AC_CLEAR_CACHE_PATH = '/opac/extras/ac/clearcache/all/r/';

@Component({
    selector: 'eg-catalog-record-actions',
    templateUrl: 'actions.component.html',
    imports: [
        AddToCarouselDialogComponent,
        StaffCommonModule,
        UploadJacketImageDialogComponent
    ]
})
export class RecordActionsComponent implements OnInit {
    private store = inject(StoreService);
    private strings = inject(StringService);
    private toast = inject(ToastService);
    private staffCat = inject(StaffCatalogService);
    protected basket = inject(BasketService);
    private http = inject(HttpClient);


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

    addToBasket() {
        this.basket.addRecordIds([this.recId]);
    }

    removeFromBasket() {
        this.basket.removeRecordIds([this.recId]);
    }

    clearAddedContentCache() {
        const url = AC_CLEAR_CACHE_PATH + this.recId;
        this.http.get(url, {responseType: 'text'}).subscribe(
            { next: data => {
                console.debug(data);
                this.strings.interpolate('catalog.record.toast.clearAddedContentCache')
                    .then(txt => this.toast.success(txt));
            }, error: (err: unknown) => {
                this.strings.interpolate('catalog.record.toast.clearAddedContentCacheFailed')
                    .then(txt => this.toast.danger(txt));
            } }
        );
    }
}


