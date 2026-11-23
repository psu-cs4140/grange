import * as ex from "excalibur";
import { depthForY } from "./depth";
import { FARM_NPC_NAME, type NpcAnchor, npcPrompt } from "./farmNpcPosition";
import { farmBounds, TILE_SIZE } from "./mapData";
import { createNameLabel } from "./nameLabel";
import { farmWalkObstacles } from "./sceneObstacles";
import { addWaltGraphics, WALT_WALK, type WaltPose } from "./waltSprites";
import { moveAroundObstacles } from "./walkCollisions";

export const FARM_NPC_WIDTH = 44;
export const FARM_NPC_HEIGHT = 72;

/** Walt patrols close to the farmhouse and stops to greet nearby players. */
export class FarmNpc {
	private readonly body: ex.Actor;
	private readonly label: ex.Actor;
	private shown = false;
	private home: NpcAnchor | null = null;
	private patrolTime = 0;
	private greetingTime = 0;
	private walkTime = 0;

	constructor(scene: ex.Scene) {
		this.body = new ex.Actor({
			pos: ex.vec(0, 0),
			width: FARM_NPC_WIDTH,
			height: FARM_NPC_HEIGHT,
			anchor: ex.vec(0.5, 1),
			z: depthForY(0),
		});
		addWaltGraphics(this.body, FARM_NPC_HEIGHT);
		this.pose("idle");

		this.body.graphics.visible = false;
		this.label = createNameLabel(FARM_NPC_NAME, "#ffd76e");
		this.label.graphics.visible = false;

		scene.add(this.body);
		scene.add(this.label);
	}

	/** Returns Walt's current feet position so his prompt travels with him. */
	update(home: NpcAnchor | null, player: NpcAnchor, step: number, landLevel: number): NpcAnchor | null {
		this.setShown(home !== null);
		if (!home) {
			this.home = null;
			return null;
		}
		if (home.x !== this.home?.x || home.y !== this.home?.y) {
			this.home = home;
			this.place(home);
			this.patrolTime = 0;
			this.greetingTime = 0;
			this.walkTime = 0;
		}
		if (npcPrompt(player, this.body.pos)) {
			this.greetingTime += step;
			const gesture = this.greetingTime < 650 ? "wave" : this.greetingTime < 1350 ? "point" : "idle";
			this.pose(gesture, gesture === "point" || player.x < this.body.pos.x);
		} else {
			this.greetingTime = 0;
			this.patrol(home, step, landLevel);
		}
		return this.body.pos;
	}

	talkTo(player: NpcAnchor): void {
		this.pose("talk", player.x < this.body.pos.x);
	}

	private patrol(home: NpcAnchor, step: number, landLevel: number): void {
		this.patrolTime = (this.patrolTime + step) % 6000;
		const time = this.patrolTime;
		const offset = Math.max(0, Math.min(time - 1800, 1500, 5300 - time)) * (42 / 1500);
		const edge = (farmBounds(landLevel).maxColumn + 1) * TILE_SIZE - 16;
		const dx = Math.max(0, Math.min(offset, edge - home.x));
		const next = moveAroundObstacles(home.x, home.y, dx, 0, farmWalkObstacles);
		const moved = next.x - this.body.pos.x;
		this.place(next);
		this.walkTime = moved === 0 ? 0 : this.walkTime + step;
		this.pose(moved === 0 ? "idle" : WALT_WALK[Math.floor(this.walkTime / 115) % WALT_WALK.length], moved < 0);
	}

	private pose(pose: WaltPose, facingLeft = false): void {
		if (this.body.graphics.current !== this.body.graphics.getGraphic(pose)) {
			this.body.graphics.use(pose);
		}
		this.body.graphics.flipHorizontal = facingLeft;
	}

	private place(position: NpcAnchor): void {
		this.body.pos = ex.vec(position.x, position.y);
		this.body.z = depthForY(position.y);
		this.label.pos = ex.vec(position.x, position.y - FARM_NPC_HEIGHT - 6);
		this.label.z = this.body.z + 1;
	}

	private setShown(shown: boolean): void {
		if (shown === this.shown) return;
		this.shown = shown;
		this.body.graphics.visible = shown;
		this.label.graphics.visible = shown;
	}
}
