import * as ex from "excalibur";
import { useEffect, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useNotificationStore } from "../notifications/notificationStore";
import { PauseMenu } from "../pause/PauseMenu";
import { usePauseStore } from "../pause/pauseStore";
import { emitLeaveFarm, emitVisitFarm } from "../socket";
import { useGameStore } from "../store";
import { Hud } from "../inventory/Hud";
import { farmToolForItem } from "../inventory/items";
import { InventoryPanel } from "../inventory/InventoryPanel";
import "../inventory/inventory.css";
import { useInventoryKeys } from "../inventory/useInventoryKeys";
import { useInventoryStore } from "../inventory/inventoryStore";
import { CasinoScene } from "./CasinoScene";
import { casinoResources } from "./casinoResources";
import { FarmMapScene } from "./FarmMapScene";
import type { FarmHudSnapshot } from "./farmHud";
import "./farmMap.css";
import { MAP_HEIGHT, MAP_WIDTH } from "./mapData";
import { MarketplaceScene } from "./MarketplaceScene";
import { marketplaceResources } from "./marketplaceResources";
import { resources } from "./resources";
import type { WorldArea } from "./WalkingScene";

const worldResources = [
	...new Set([...resources, ...marketplaceResources, ...casinoResources]),
];

export default function FarmMap() {
	const canvasRef = useRef<HTMLCanvasElement>(null);
	useInventoryKeys();
	const sceneRef = useRef<FarmMapScene | null>(null);
	const username = useGameStore((s) => s.username);
	const farm = useGameStore((s) => s.activeFarm);
	const tool = useGameStore((s) => s.tool);
	const setTool = useGameStore((s) => s.setTool);
	const selectedHotbar = useInventoryStore((s) => s.selectedHotbar);
	const hotbar = useInventoryStore((s) => s.hotbar);
	const setInventoryOpen = useInventoryStore((s) => s.setInventoryOpen);
	const pushNotice = useNotificationStore((s) => s.push);
	const paused = usePauseStore((s) => s.paused);
	const setPaused = usePauseStore((s) => s.setPaused);
	const { owner } = useParams<{ owner?: string }>();
	const navigate = useNavigate();
	const [hud, setHud] = useState<FarmHudSnapshot>({
		tomatoes: 0,
		message: "Hoe: click or drag on grass to till.",
		hovered: null,
	});

	const target = owner ?? username;
	const isOwner = target === username;

	useEffect(() => {
		if (!target) return;

		emitVisitFarm(target, (res) => {
			if (!res.ok) navigate("/dashboard", { replace: true });
		});

		return () => emitLeaveFarm();
	}, [target, navigate]);

	// Selecting a hotbar slot drives the active farm tool (the hotbar is the
	// single tool selector). Slots with no tool item leave the tool unchanged.
	useEffect(() => {
		const next = farmToolForItem(hotbar[selectedHotbar]?.itemId ?? null);
		if (next) setTool(next);
	}, [hotbar, selectedHotbar, setTool]);

	const [area, setArea] = useState<WorldArea>("Farm");
	const [travelPrompt, setTravelPrompt] = useState<string | null>(null);

	useEffect(() => {
		const canvas = canvasRef.current;
		if (!canvas || !target) return;

		let cancelled = false;
		const engine = new ex.Engine({
			canvasElement: canvas,
			viewport: { width: MAP_WIDTH, height: MAP_HEIGHT },
			resolution: { width: MAP_WIDTH, height: MAP_HEIGHT },
			displayMode: ex.DisplayMode.FitContainer,
			pixelArt: true,
			suppressConsoleBootMessage: true,
			backgroundColor: ex.Color.fromHex("#79a44d"),
		});

		const scene = new FarmMapScene(target, isOwner, setTravelPrompt, setArea);
		scene.onFarmUpdate = (snapshot) => setHud(snapshot);
		sceneRef.current = scene;
		engine.addScene("farm-map", scene);
		engine.addScene(
			"marketplace",
			new MarketplaceScene(setTravelPrompt, setArea),
		);
		engine.addScene("casino", new CasinoScene(setTravelPrompt, setArea));
		void Promise.all(worldResources.map((resource) => resource.load())).then(
			async () => {
				if (cancelled) return;
				await engine.start();
				if (!cancelled) await engine.goToScene("farm-map");
			},
		);

		return () => {
			cancelled = true;
			sceneRef.current = null;
			engine.stop();
			engine.dispose();
		};
	}, [target, isOwner]);

	useEffect(() => {
		sceneRef.current?.setTool(tool);
	}, [tool]);

	// Route farm hints and errors into the bottom-left feed.
	useEffect(() => {
		if (hud.message) pushNotice(hud.message, "system");
	}, [hud.message, pushNotice]);

	useEffect(() => {
		if (!target) return;
		pushNotice(
			isOwner ? "Welcome to your farm." : `Visiting ${target}'s farm.`,
			"system",
		);
	}, [target, isOwner, pushNotice]);

	// Leaving the world closes any open overlay so re-entry starts fresh.
	useEffect(() => {
		return () => {
			setPaused(false);
			setInventoryOpen(false);
		};
	}, [setPaused, setInventoryOpen]);

	return (
		<main className="farm-map-page">
			<canvas
				ref={canvasRef}
				className="farm-map-canvas"
				aria-label={`${area} map. Use WASD or arrow keys to walk.`}
			/>
			{travelPrompt && (
				<div className="farm-map-travel-prompt" data-testid="travel-prompt">
					{travelPrompt}
				</div>
			)}
			<Hud
				tomatoes={hud.tomatoes}
				tiles={farm?.tiles.length ?? 0}
				hovered={hud.hovered}
			/>
			<InventoryPanel />
			{paused && <PauseMenu />}
		</main>
	);
}
