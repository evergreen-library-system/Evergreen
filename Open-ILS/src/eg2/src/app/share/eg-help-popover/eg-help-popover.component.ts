import { Component, OnInit, Input } from '@angular/core';
import {NgbPopover} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-help-popover',
  templateUrl: './eg-help-popover.component.html',
  styleUrls: ['./eg-help-popover.component.css']
})
export class EgHelpPopoverComponent implements OnInit {

  @Input()
  helpText = '';

  @Input()
  helpLink = '';

  @Input()
  placement = '';

  constructor() { }

  ngOnInit() {
  }

}
