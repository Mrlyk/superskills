import { AppError } from './errors.js';

/**
 * Sum the total price of a list of items.
 * @param {Array<{priceCents: number, qty: number}>} items order items
 * @returns {number} total in integer cents
 */
export function totalCents(items) {
  if (!Array.isArray(items)) {
    throw new AppError('E_TYPE', 'items must be an array');
  }
  return items.reduce((sum, it) => sum + it.priceCents * it.qty, 0);
}
