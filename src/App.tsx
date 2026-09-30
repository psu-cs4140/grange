import { Route, Routes } from "react-router-dom";
import Login from "./routes/Login";
import FarmMap from "./world/FarmMap";

export default function App() {
	return (
		<Routes>
			<Route path="/" element={<Login />} />
			<Route path="/world" element={<FarmMap />} />
		</Routes>
	);
}
