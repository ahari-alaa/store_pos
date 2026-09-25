/**
 * Unit conversion for supply/recipe quantities (spec §8).
 *
 * A recipe line can be entered in a unit different from the ingredient's
 * own storage unit — e.g. Café is stocked in `kg` but a recipe wants
 * `25 g` per cup. Only conversions inside the same family (weight or
 * volume) are valid; `unit` (countable items) never converts to
 * anything else. An attempt to cross families (e.g. g -> ml) throws,
 * because that would silently corrupt a stock calculation.
 */

const FAMILY = {
  g: 'weight',
  kg: 'weight',
  ml: 'volume',
  l: 'volume',
  unit: 'count',
};

// Every unit's size relative to its family's base unit (g for weight,
// ml for volume, unit for count).
const BASE_FACTOR = {
  g: 1,
  kg: 1000,
  ml: 1,
  l: 1000,
  unit: 1,
};

function familyOf(unit) {
  const family = FAMILY[unit];
  if (!family) throw new Error(`Unknown unit "${unit}"`);
  return family;
}

/** True if `a` and `b` can be converted between each other. */
function isCompatible(a, b) {
  if (!a || !b) return true; // missing unit = "assume same as the other side"
  return familyOf(a) === familyOf(b);
}

/**
 * Converts `quantity` expressed in `fromUnit` into `toUnit`. Returns the
 * quantity unchanged when either unit is missing (treated as "same
 * unit"). Throws on an incompatible pair (e.g. g -> ml) so a bad recipe
 * line fails loudly instead of producing a silently wrong yield number.
 */
function convertQuantity(quantity, fromUnit, toUnit) {
  const qty = Number(quantity) || 0;
  if (!fromUnit || !toUnit || fromUnit === toUnit) return qty;
  if (familyOf(fromUnit) !== familyOf(toUnit)) {
    throw new Error(`Cannot convert "${fromUnit}" to "${toUnit}" — incompatible units`);
  }
  const inBase = qty * BASE_FACTOR[fromUnit];
  return inBase / BASE_FACTOR[toUnit];
}

module.exports = { convertQuantity, isCompatible, familyOf };
