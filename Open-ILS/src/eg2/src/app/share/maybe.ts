// The Maybe monad, also known as Option<T>
export type Maybe<T> = Some<T>|None<T>

export class Some<T> {
    constructor(private readonly value: T) {}

    whenSome(callback: (val: T) => void): Some<T> {
        callback(this.value);
        return this;
    }
}

export class None<T> {
    whenSome(_callback: (val: T) => void): None<T> {
        // Since this is not Some, we do not run the callback
        return this;
    }
}
