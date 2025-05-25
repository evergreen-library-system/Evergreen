import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {FormControl} from '@angular/forms';
import {takeLast} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {StringComponent} from '@eg/share/string/string.component';

@Component({
    selector: 'eg-add-to-carousel-dialog',
    templateUrl: './add-to-carousel-dialog.component.html'
})


export class AddToCarouselDialogComponent extends DialogComponent implements OnInit {

    // IDs of records to add to the carousel
    @Input() recordIds: number[];


    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    selectedCarousel = new FormControl('');

    private carousels = [];

    public addToCarousel: () => void;
    private reset: () => void;

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private evt: EventService,
        private net: NetService,
        private toast: ToastService
    ) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(ok => {
            this.reset();
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.carousel.retrieve_manual_by_staff',
                this.auth.token()
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            ).subscribe(carousels => this.carousels = carousels);
        });

        this.reset = () => {
            this.carousels = [];
        };

        this.addToCarousel = () => {
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.item.create.batch',
                this.auth.token(),
                'biblio_record_entry',
                this.selectedCarousel.value['id'],
                this.recordIds
            ).pipe(takeLast(1))
                .subscribe(
                    result => {
                        const evt = this.evt.parse(result);
                        if (evt) {
                            this.errorMsg.current().then(m => this.toast.danger(m));
                        } else {
                            this.successMsg.current().then(m => this.toast.success(m));
                            this.close(true);
                        }
                    }
                );
        };
    }

    formatCarouselEntries(): ComboboxEntry[] {
        return this.carousels.map(carousel => ({id: carousel['bucket'], label: carousel['name']}));
    }

}
