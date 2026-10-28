import type { BarnDragPayload } from "./dragTypes";
import { InventorySlot } from "./InventorySlot";
import { useInventoryStore, type SlotRef } from "./inventoryStore";

interface Props {
	area: "grid" | "hotbar";
	index: number;
	/** Stores this exact stack when the overlay's Store button is pressed. */
	onDeposit: (from: SlotRef) => void;
	/** Accepts a stack dragged in from barn storage. */
	onReceiveBarn: (payload: BarnDragPayload) => void;
}

/**
 * A player inventory slot inside the barn window. Wraps the shared
 * `InventorySlot` with a sibling Store button, which would be invalid markup
 * nested inside the slot's own button.
 */
export function BarnPlayerSlot({
	area,
	index,
	onDeposit,
	onReceiveBarn,
}: Props) {
	const filled = useInventoryStore((s) =>
		Boolean((area === "grid" ? s.grid[index] : s.hotbar[index])?.itemId),
	);

	return (
		<div className="barn-slot-wrap">
			<InventorySlot area={area} index={index} onReceiveBarn={onReceiveBarn} />
			{filled && (
				<button
					type="button"
					className="barn-store"
					data-testid={`barn-store-${area}-${index}`}
					onClick={() => onDeposit({ area, index })}
				>
					Store
				</button>
			)}
		</div>
	);
}
