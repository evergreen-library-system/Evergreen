import { Component, EventEmitter, Input, OnInit, Output, ViewChild } from '@angular/core';
import { Tree, TreeNode } from '../tree/tree';
import { NgbTypeahead, NgbTypeaheadModule, NgbTypeaheadSelectItemEvent } from '@ng-bootstrap/ng-bootstrap';
import { Observable, Subject, debounceTime, distinctUntilChanged, filter, map, merge } from 'rxjs';
import { FormsModule } from '@angular/forms';

// non-collapsing space
const PAD_SPACE = ' '; // U+2007

@Component({
    selector: 'eg-tree-combobox',
    standalone: true,
    imports: [NgbTypeaheadModule, FormsModule],
    templateUrl: './tree-combobox.component.html'
})
export class TreeComboboxComponent implements OnInit {
  @Input() tree: Tree;
  @Input() placeholder: string;
  @Input() ariaLabel: string;
  @Input() domId: string;
  @Input() set defaultNode(node: TreeNode) {
      this.selectedNode = node;
  }

  @Output() nodeSelected$ = new EventEmitter<TreeNode>();

  @ViewChild('instance', { static: true }) instance: NgbTypeahead;

  focus$ = new Subject<string>();
  click$ = new Subject<string>();
  filter: (text$: Observable<string>) => Observable<TreeNode[]>;

  selectedNode: TreeNode;

  ngOnInit() {
      this.filter = (text$: Observable<string>): Observable<TreeNode[]> => {
          const debounceMilliseconds = 200;
          const debouncedText$ = text$.pipe(debounceTime(debounceMilliseconds), distinctUntilChanged());
          const clicksWithClosedPopup$ = this.click$.pipe(filter(() => !this.instance.isPopupOpen()), map(() => '_CLICK_'));
          const inputFocus$ = this.focus$.pipe(map(() => '_CLICK_'));

          return merge(debouncedText$, inputFocus$, clicksWithClosedPopup$).pipe(
              map((query) => {
                  return this.tree.nodeList(false, true).filter((node) => this.nodeMatchesQuery(node, query));
              }),
          );
      };
  }

  inputFormatter(node: TreeNode): string {
      return node.label;
  }

  emitNodeSelected(event: NgbTypeaheadSelectItemEvent): void {
      this.nodeSelected$.emit(event.item);
  }

  treeNodeAsText(node: TreeNode): string {
      return PAD_SPACE.repeat(node.depth) + node.label;
  }

  private nodeMatchesQuery(node: TreeNode, query: string): boolean {
      if (query === '' || !query || query === '_CLICK_') {
          return true;
      }
      return node.label.toLocaleLowerCase().includes(query.toLocaleLowerCase());
  }
}
