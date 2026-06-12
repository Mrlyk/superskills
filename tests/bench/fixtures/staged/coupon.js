import { AppError } from './errors.js';

/**
 * Apply a percentage coupon to a total.
 * @param {number} totalCents total in integer cents
 * @param {number} percent discount percentage
 * @returns {number} discounted total in cents
 */
export function applyCoupon(totalCents, percent) {
  if (typeof totalCents !== 'number' || typeof percent !== 'number') {
    throw new AppError('E_TYPE', 'totalCents and percent must be numbers');
  }
  return totalCents - totalCents * (percent / 100);
}
