import type { ActiveFarm } from "../../shared/types";

/**
 * Owners always edit; visitors only while the owner has enabled editing.
 * The server re-checks the persisted flag on every action, so this is the UI
 * gate, not the authority.
 */
export function canEditFarm(
	farm: Pick<ActiveFarm, "visitor_edit"> | null | undefined,
	isOwner: boolean,
): boolean {
	return isOwner || Boolean(farm?.visitor_edit);
}

/**
 * Moving props follows the same edit gate, except admins may rearrange
 * buildings on any farm (including farms they are only visiting).
 */
export function canMoveProps(
	farm: Pick<ActiveFarm, "visitor_edit"> | null | undefined,
	isOwner: boolean,
	isAdmin: boolean,
): boolean {
	return canEditFarm(farm, isOwner) || isAdmin;
}
