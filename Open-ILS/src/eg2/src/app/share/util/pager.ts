import {EventEmitter} from '@angular/core';

/**
 * Utility class for manage paged information.
 */
export class Pager {
    offset = 0;
    limit: number = null;
    resultCount: number;
    onChange$: EventEmitter<number>;

    constructor() {
        this.resultCount = null;
        this.onChange$ = new EventEmitter<number>();
    }

    reset() {
        this.resultCount = null;
        this.offset = 0;
    }

    setLimit(l: number) {
        if (l !== this.limit) {
            this.limit = l;
            this.setPage(1);
        }
    }

    isFirstPage(): boolean {
        return this.offset === 0;
    }

    isLastPage(): boolean {
        return this.currentPage() === this.pageCount();
    }

    currentPage(): number {
        return Math.floor(this.offset / this.limit) + 1;
    }

    increment(): void {
        this.setPage(this.currentPage() + 1);
    }

    decrement(): void {
        this.setPage(this.currentPage() - 1);
    }

    toFirst() {
        if (!this.isFirstPage()) {
            this.setPage(1);
        }
    }

    toLast() {
        if (!this.isLastPage()) {
            this.setPage(this.pageCount());
        }
    }

    setPage(page: number): void {
        this.offset = (this.limit * (page - 1));
        this.onChange$.emit(this.offset);
    }

    pageCount(): number {
        if (this.resultCount === null) { return -1; }
        let pages = this.resultCount / this.limit;
        if (Math.floor(pages) < pages) {
            pages = Math.floor(pages) + 1;
        }
        return pages;
    }

    // Returns a list of pages numbers with @pivot at the center
    // or as close to center as possible.
    // @pivot is 1-based for consistency with page numbers.
    // pageRange(25, 10) => [21,22,...29,30]
    pageRange(pivot: number, size: number): number[] {

        const diff = Math.floor(size / 2);
        let start = pivot <= diff ? 1 : pivot - diff + 1;

        const pcount = this.pageCount();

        if (start + size > pcount) {
            start = pcount - size + 1;
            if (start < 1) { start = 1; }
        }

        if (start + size > pcount) {
            size = pcount;
        }

        return this.pageList().slice(start - 1, start - 1 + size);
    }

    pageList(): number[] {
        const list = [];
        for (let i = 1; i <= this.pageCount(); i++) {
            list.push(i);
        }
        return list;
    }

    // Given a zero-based page-specific offset, return the where in the
    // entire data set the row lives, 1-based for UI friendliness.
    rowNumber(offset: number): number {
        return this.offset + offset + 1;
    }
}
