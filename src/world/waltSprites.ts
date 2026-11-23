import * as ex from "excalibur";

export const WALT_WALK = [
	"walk-1", "walk-2", "walk-3", "walk-4",
	"walk-5", "walk-6", "walk-7", "walk-8",
] as const;
const poses = ["idle", "wave", "point", "talk", ...WALT_WALK] as const;
export type WaltPose = (typeof poses)[number];

export const waltImages = poses.map(
	(pose) => new ex.ImageSource(`/assets/farm/walt/${pose}.webp`, {
		filtering: ex.ImageFiltering.Pixel,
	}),
);

export function addWaltGraphics(actor: ex.Actor, height: number): void {
	for (const [index, pose] of poses.entries()) {
		const image = waltImages[index];
		const sprite = image.toSprite();
		const scale = height / image.height;
		sprite.scale = ex.vec(scale, scale);
		actor.graphics.add(pose, sprite);
	}
}
