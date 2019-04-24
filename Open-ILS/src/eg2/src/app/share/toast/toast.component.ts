import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {ToastService, ToastMessage} from '@eg/share/toast/toast.service';

const EG_TOAST_TIMEOUT = 3000;

@Component({
  selector: 'eg-toast',
  templateUrl: './toast.component.html',
  styleUrls: ['./toast.component.css']
})
export class ToastComponent implements OnInit {

    message: ToastMessage;

    // track the most recent timeout event
    timeout: any;

    constructor(private toast: ToastService) {
    }

    ngOnInit() {
        this.toast.messages$.subscribe(msg => this.show(msg));
    }

    show(msg: ToastMessage) {
        this.dismiss(this.message);
        this.message = msg;
        this.timeout = setTimeout(
            () => this.dismiss(this.message),
            EG_TOAST_TIMEOUT
        );
    }

    dismiss(msg: ToastMessage) {
        this.message = null;
        if (this.timeout) {
            clearTimeout(this.timeout);
            this.timeout = null;
        }
    }
}


