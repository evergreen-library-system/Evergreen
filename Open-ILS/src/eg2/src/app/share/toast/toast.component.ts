import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {ToastService, ToastMessage} from '@eg/share/toast/toast.service';
import {ServerStoreService} from '@eg/core/server-store.service';

const EG_TOAST_TIMEOUT = 10000;

@Component({
    selector: 'eg-toast',
    templateUrl: './toast.component.html',
    styleUrls: ['./toast.component.css']
})
export class ToastComponent implements OnInit {

    messages: ToastMessage[] = [];
    duration: number = EG_TOAST_TIMEOUT;

    // track the most recent timeout event
    timeout: any;

    constructor(private toast: ToastService, private store: ServerStoreService) {
    }

    ngOnInit() {
        this.setDuration();
        this.toast.messages$.subscribe(msg => this.show(msg));
    }

    setDuration() {
        this.store.getItem('ui.toast_duration').then(setting => {
            if (setting) {
                this.duration = setting * 1000;
            }
        });
    }

    show(msg: ToastMessage) {
        this.messages.push(msg);
        console.info($localize`${new Date().toLocaleTimeString()} - ${msg.text}`);

        this.timeout = setTimeout(
            () => this.messages.shift(),
            this.duration
        );
    }

    // delete a specific toast when user clicks the 'x' button
    dismiss(index: number) {
        this.messages[index] = null;
    }
}


