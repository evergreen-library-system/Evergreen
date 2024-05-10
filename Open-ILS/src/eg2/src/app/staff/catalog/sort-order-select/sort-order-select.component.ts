import { Component, EventEmitter, forwardRef, Input, Output} from '@angular/core';
import { CatalogService } from '@eg/share/catalog/catalog.service';
import { NG_VALUE_ACCESSOR } from '@angular/forms';

@Component({
    selector: 'eg-sort-order-select',
    templateUrl: './sort-order-select.component.html',
    providers: [
        {
            provide: NG_VALUE_ACCESSOR,
            useExisting: forwardRef(() => SortOrderSelectComponent),
            multi: true
        }
    ]
})
export class SortOrderSelectComponent {

    private _sortOrder = 'relevance';

    @Input()
    get sortOrder () {return this._sortOrder;}
    set sortOrder(value: string){
        if (!value) {this._sortOrder = 'relevance';} else {this._sortOrder = value;}
    }

  @Input() name : string;
  @Input() id : string;

  @Output() sortOrderChange : EventEmitter<any> = new EventEmitter<any>();

  constructor(
  ){

  }

  change(){
      this.sortOrderChange.emit(this._sortOrder);
  }

}
