/**
 * Focus an element and explicitly dispatch the focus event.
 *
 * Some logic is based on the focus event, which does not seem
 * to be reliably sent within an Angular unit test context when
 * you just call element.focus().  This function explicitly does
 * both.
 *
 * @param element the DOM element you want to focus in your test
 */
export function focusElement(element: HTMLElement) {
    element.focus();
    element.dispatchEvent(new FocusEvent('focus'));
}
