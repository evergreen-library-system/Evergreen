import {Injectable, EventEmitter} from '@angular/core';

export interface ToastMessage {
    text: string;
    style: string;
}

@Injectable()
export class ToastService {

    messages$: EventEmitter<ToastMessage>;

    constructor() {
        this.messages$ = new EventEmitter<ToastMessage>();
    }

    sendMessage(msg: ToastMessage) {
        this.messages$.emit(msg);
    }

    success(text: string) {
        this.sendMessage({text: text, style: 'success'});
    }

    info(text: string) {
        this.sendMessage({text: text, style: 'info'});
    }

    warning(text: string) {
        this.sendMessage({text: text, style: 'warning'});
    }

    danger(text: string) {
        this.sendMessage({text: text, style: 'danger'});
    }

    // Others?
}

